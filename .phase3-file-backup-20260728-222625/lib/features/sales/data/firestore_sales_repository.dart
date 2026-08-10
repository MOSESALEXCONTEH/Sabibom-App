// ignore_for_file: avoid_types_as_parameter_names

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../notifications/application/operational_alert_service.dart';
import '../../notifications/application/stock_alert_service.dart';
import '../../products/domain/product.dart';
import '../../receipts/data/firestore_receipt_template_repository.dart';
import '../domain/sale.dart';
import '../domain/sale_calculator.dart';
import '../domain/sale_models.dart';
import 'sales_repository.dart';

class FirestoreSalesRepository implements SalesRepository {
  FirestoreSalesRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    AuthenticatedApiClient? apiClient,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _apiClient = apiClient ?? AuthenticatedApiClient();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final AuthenticatedApiClient _apiClient;
  final bool _useAuthoritativeInventoryApi = true;

  @override
  Future<CompletedSale> completeSale(CompleteSaleRequest request) async {
    final user = _auth.currentUser;
    if (user == null) throw const SaleException('unauthenticated');
    if (request.business.businessId.trim().isEmpty) {
      throw const SaleException('failed-precondition');
    }
    if (request.cart.items.isEmpty) {
      throw const SaleException(
        'failed-precondition',
        message: 'Add at least one item to the sale.',
      );
    }

    final totals = request.cart.totals(
      taxEnabled: request.business.taxEnabled,
      taxPercentage: request.business.taxPercentage,
    );
    if (request.cart.paymentMethod == PaymentMethod.cash &&
        totals.amountPaidMinor < totals.totalMinor) {
      throw const SaleException(
        'failed-precondition',
        message: 'Cash received must cover the total.',
      );
    }
    if (totals.balanceDueMinor > 0 && request.cart.customer == null) {
      throw const SaleException(
        'failed-precondition',
        message: 'Select a customer for credit or partial payment.',
      );
    }

    if (_useAuthoritativeInventoryApi) {
      try {
        final response = await _apiClient.postJson(
          '/api/inventory/sales/complete',
          body: <String, dynamic>{
            'saleId': request.saleId,
            'businessId': request.business.businessId,
            'items': request.cart.items
                .map(
                  (item) => <String, dynamic>{
                    'saleItemId': item.saleItemId,
                    'productId': item.productId,
                    'isCustomItem': item.isCustomItem,
                    'name': item.name,
                    'sku': item.sku,
                    'barcode': item.barcode,
                    'unit': item.unit,
                    'quantity': item.quantity,
                    'quantityInput': item.quantityInput,
                    'unitPriceMinor': item.unitPriceMinor,
                    'unitPriceInput': item.unitPriceInput,
                    'costPriceMinor': item.costPriceMinor,
                    'trackStock': item.trackStock,
                    'discountType': item.discountType?.name,
                    'discountValue': item.discountValue,
                  },
                )
                .toList(),
            'paymentMethod': request.cart.paymentMethod.storedValue,
            'amountPaidMinor': totals.amountPaidMinor,
            'customerId': request.cart.customer?.customerId,
            'customerName': request.cart.customer?.name,
            'customerPhone': request.cart.customer?.phone,
            'orderDiscountType': request.cart.orderDiscountType?.name,
            'orderDiscountValue': request.cart.orderDiscountValue,
            'taxEnabled': request.business.taxEnabled,
            'taxPercentage': request.business.taxPercentage,
            'note': request.cart.note.isEmpty ? null : request.cart.note,
            'cashierName': request.cashierName,
          },
          timeout: const Duration(seconds: 90),
        );
        await _evaluatePostSaleAlerts(request, totals);
        return CompletedSale(
          saleId: response['saleId'] as String? ?? request.saleId,
          receiptNumber:
              response['receiptNumber'] as String? ?? request.saleId,
          totalMinor:
              (response['totalMinor'] as num?)?.round() ?? totals.totalMinor,
          amountPaidMinor:
              (response['amountPaidMinor'] as num?)?.round() ??
              totals.amountPaidMinor,
          balanceDueMinor:
              (response['balanceDueMinor'] as num?)?.round() ??
              totals.balanceDueMinor,
          changeMinor:
              (response['changeMinor'] as num?)?.round() ?? totals.changeMinor,
          paymentMethod: request.cart.paymentMethod,
        );
      } on ApiException catch (error) {
        // Inventory complete route may not be deployed yet on Vercel (404).
        // Fall through to the Firestore completion path below.
        if (error.statusCode != 404 && error.statusCode != 405) {
          throw SaleException(
            error.code ?? 'unavailable',
            message: error.message,
          );
        }
      }
    }

    final business = _firestore
        .collection('businesses')
        .doc(request.business.businessId);
    final sale = business.collection('sales').doc(request.saleId);
    final counter = business.collection('counters').doc('sales');
    final activity = business.collection('activity').doc();
    final today = DateFormat('yyyyMMdd').format(DateTime.now());
    final analytics = business.collection('analytics').doc('daily_$today');

    final receiptTemplate =
        await ReceiptTemplateRepository(
          firestore: _firestore,
          auth: _auth,
        ).getDefaultTemplate(
          request.business.businessId,
          preferredId: request.business.defaultReceiptTemplateId,
        );
    final receiptTemplateSnapshot = <String, Object?>{
      ...receiptTemplate.toSnapshot(
        logoUrl: request.business.logoUrl,
        logoCid: request.business.logoCid,
      ),
      'businessName': request.business.name,
      'businessPhone': request.business.phoneNumber,
      'businessEmail': request.business.email,
      'businessAddress': request.business.address,
      'businessWebsite': request.business.website,
      'businessTagline': request.business.businessTagline,
    };

    try {
      return await _runCompleteSaleTransaction(
        request: request,
        totals: totals,
        user: user,
        business: business,
        sale: sale,
        counter: counter,
        activity: activity,
        analytics: analytics,
        today: today,
        receiptTemplateSnapshot: receiptTemplateSnapshot,
      );
    } on SaleException {
      rethrow;
    } on FirebaseException catch (error) {
      throw SaleException(error.code, message: error.message);
    }
  }

  Future<CompletedSale> _runCompleteSaleTransaction({
    required CompleteSaleRequest request,
    required SaleTotals totals,
    required User user,
    required DocumentReference<Map<String, dynamic>> business,
    required DocumentReference<Map<String, dynamic>> sale,
    required DocumentReference<Map<String, dynamic>> counter,
    required DocumentReference<Map<String, dynamic>> activity,
    required DocumentReference<Map<String, dynamic>> analytics,
    required String today,
    required Map<String, Object?> receiptTemplateSnapshot,
  }) async {
    final completed = await _firestore.runTransaction((transaction) async {
      final businessSnapshot = await transaction.get(business);
      if (!businessSnapshot.exists) throw const SaleException('not-found');
      final existing = await transaction.get(sale);
      if (existing.exists) {
        final data = existing.data()!;
        return _completedFromExisting(request.saleId, data);
      }

      final productSnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final item in request.cart.items.where(
        (item) => item.trackStock && item.productId != null,
      )) {
        productSnapshots[item.productId!] = await transaction.get(
          business.collection('products').doc(item.productId),
        );
      }
      for (final item in request.cart.items.where(
        (item) => item.trackStock && item.productId != null,
      )) {
        final product = productSnapshots[item.productId!];
        if (product == null || !product.exists) {
          throw SaleException(
            'failed-precondition',
            message: '${item.name} is no longer available.',
          );
        }
        final available =
            (product.data()?['quantity'] as num?)?.toDouble() ?? 0;
        if (available < item.quantity) {
          throw SaleException(
            'failed-precondition',
            message:
                'Not enough stock for ${item.name}. Only $available remaining.',
          );
        }
      }

      final counterSnapshot = await transaction.get(counter);
      final nextNumber =
          ((counterSnapshot.data()?['nextNumber'] as num?)?.toInt() ?? 1);
      final receiptNumber =
          'SB-$today-${nextNumber.toString().padLeft(4, '0')}';

      // Firestore transactions require every read to happen before the
      // first write, so the customer document must be read here.
      DocumentReference<Map<String, dynamic>>? customerReference;
      DocumentSnapshot<Map<String, dynamic>>? customerSnapshot;
      final selectedCustomer = request.cart.customer;
      if (selectedCustomer != null) {
        customerReference = business
            .collection('customers')
            .doc(selectedCustomer.customerId);
        customerSnapshot = await transaction.get(customerReference);
        if (!customerSnapshot.exists) {
          throw const SaleException(
            'failed-precondition',
            message: 'The selected customer no longer exists.',
          );
        }
      }

      transaction.set(counter, <String, Object?>{
        'nextNumber': nextNumber + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final paymentStatus = totals.balanceDueMinor == 0
          ? PaymentStatus.paid
          : totals.amountPaidMinor == 0
          ? PaymentStatus.unpaid
          : PaymentStatus.partiallyPaid;
      final itemMaps = request.cart.items.map((item) {
        final subtotal = SaleCalculator.lineSubtotal(item);
        final discount = SaleCalculator.lineDiscount(item);
        return <String, Object?>{
          'saleItemId': item.saleItemId,
          'productId': item.productId,
          'isCustomItem': item.isCustomItem,
          'name': item.name,
          'sku': item.sku,
          'barcode': item.barcode,
          'unit': item.unit,
          'quantityInput': item.quantityInput,
          'quantity': item.quantity,
          'unitPriceInput': item.unitPriceInput,
          'unitPriceMinor': item.unitPriceMinor,
          'costPriceMinor': item.costPriceMinor,
          'discountType': item.discountType?.name,
          'discountValue': item.discountValue,
          'discountAmountMinor': discount,
          'lineSubtotalMinor': subtotal,
          'lineTotalMinor': subtotal - discount,
          'trackStock': item.trackStock,
        };
      }).toList();

      transaction.set(sale, <String, Object?>{
        'saleId': request.saleId,
        'businessId': request.business.businessId,
        'branchId': request.branchId,
        'receiptNumber': receiptNumber,
        'customerId': request.cart.customer?.customerId,
        'customerName': request.cart.customer?.name,
        'customerPhone': request.cart.customer?.phone,
        'items': itemMaps,
        'itemCount': request.cart.items.length,
        'subtotalMinor': totals.subtotalMinor,
        'discountMinor': totals.itemDiscountMinor + totals.orderDiscountMinor,
        'taxMinor': totals.taxMinor,
        'totalMinor': totals.totalMinor,
        'amountPaidMinor': totals.amountPaidMinor,
        'balanceDueMinor': totals.balanceDueMinor,
        'changeMinor': totals.changeMinor,
        // Compatibility fields used by existing dashboard queries.
        'total': minorToMoney(totals.totalMinor),
        'amountPaid': minorToMoney(totals.amountPaidMinor),
        'currencyCode': request.business.currency.code,
        'currencySymbol': request.business.currency.symbol,
        'paymentMethod': request.cart.paymentMethod.storedValue,
        'paymentStatus': paymentStatus.name,
        'saleStatus': SaleStatus.completed.name,
        'status': SaleStatus.completed.name,
        'note': request.cart.note.isEmpty ? null : request.cart.note,
        'receiptTemplateSnapshot': receiptTemplateSnapshot,
        'createdBy': user.uid,
        'createdByName': request.cashierName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final runningStock = <String, double>{};
      for (final item in request.cart.items.where(
        (item) => item.trackStock && item.productId != null,
      )) {
        final productId = item.productId!;
        final productReference = business.collection('products').doc(productId);
        final productSnapshot = productSnapshots[productId]!;
        final before =
            runningStock[productId] ??
            ((productSnapshot.data()?['quantity'] as num?)?.toDouble() ?? 0);
        final after = before - item.quantity;
        runningStock[productId] = after;
        transaction.update(productReference, <String, Object?>{
          'quantity': after,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        final movement = business.collection('inventory_movements').doc();
        transaction.set(movement, <String, Object?>{
          'id': movement.id,
          'productId': productId,
          'productName': item.name,
          'type': 'stock_out',
          'quantityChange': -item.quantity,
          'stockBefore': before,
          'stockAfter': after,
          'reason': 'Sale',
          'note': receiptNumber,
          'referenceType': 'sale',
          'referenceId': request.saleId,
          'createdBy': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (customerReference != null &&
          customerSnapshot != null &&
          customerSnapshot.exists) {
        final previousBalance =
            (customerSnapshot.data()?['balanceMinor'] as num?)?.toInt() ??
            moneyToMinor(customerSnapshot.data()?['balance']);
        final updatedBalance = previousBalance + totals.balanceDueMinor;
        transaction.update(customerReference, <String, Object?>{
          'balanceMinor': updatedBalance,
          'balance': minorToMoney(updatedBalance),
          'totalCreditMinor': FieldValue.increment(totals.balanceDueMinor),
          'totalSalesMinor': FieldValue.increment(totals.totalMinor),
          'totalPaidMinor': FieldValue.increment(totals.amountPaidMinor),
          'purchaseCount': FieldValue.increment(1),
          'lastPurchaseAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (totals.balanceDueMinor > 0) {
          transaction.set(
            customerReference.collection('ledger').doc(),
            <String, Object?>{
              'type': 'sale_credit',
              'saleId': request.saleId,
              'receiptNumber': receiptNumber,
              'debitMinor': totals.balanceDueMinor,
              'creditMinor': 0,
              'balanceBeforeMinor': previousBalance,
              'balanceAfterMinor': updatedBalance,
              'createdBy': user.uid,
              'createdAt': FieldValue.serverTimestamp(),
            },
          );
        }
      }

      transaction.set(activity, <String, Object?>{
        'activityId': activity.id,
        'businessId': request.business.businessId,
        'type': 'sale',
        'title': 'Sale completed',
        'subtitle': 'Receipt $receiptNumber',
        'amount': minorToMoney(totals.totalMinor),
        'amountMinor': totals.totalMinor,
        'currencyCode': request.business.currency.code,
        'referenceId': request.saleId,
        'createdBy': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
      transaction.set(analytics, <String, Object?>{
        'dateKey': today,
        'grossSalesMinor': FieldValue.increment(totals.subtotalMinor),
        'discountMinor': FieldValue.increment(
          totals.itemDiscountMinor + totals.orderDiscountMinor,
        ),
        'taxMinor': FieldValue.increment(totals.taxMinor),
        'netSalesMinor': FieldValue.increment(totals.totalMinor),
        'amountPaidMinor': FieldValue.increment(totals.amountPaidMinor),
        'creditCreatedMinor': FieldValue.increment(totals.balanceDueMinor),
        'orderCount': FieldValue.increment(1),
        'itemsSold': FieldValue.increment(
          request.cart.items.fold<double>(
            0,
            (totalQty, item) => totalQty + item.quantity,
          ),
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return CompletedSale(
        saleId: request.saleId,
        receiptNumber: receiptNumber,
        totalMinor: totals.totalMinor,
        amountPaidMinor: totals.amountPaidMinor,
        balanceDueMinor: totals.balanceDueMinor,
        changeMinor: totals.changeMinor,
        paymentMethod: request.cart.paymentMethod,
      );
    });

    // Post-sale alerts — outside the transaction, never from build().
    try {
      await _evaluatePostSaleAlerts(request, totals);
    } catch (_) {}

    return completed;
  }

  Future<void> _evaluatePostSaleAlerts(
    CompleteSaleRequest request,
    SaleTotals totals,
  ) async {
    final businessId = request.business.businessId;
    final businessName = request.business.name;
    final productIds = request.cart.items
        .map((i) => i.productId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final productId in productIds) {
      final snap = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('products')
          .doc(productId)
          .get();
      if (!snap.exists) continue;
      await StockAlertService().evaluateProduct(
        businessId: businessId,
        businessName: businessName,
        product: Product.fromFirestore(snap),
      );
    }

    if (totals.balanceDueMinor > 0 &&
        request.cart.customer != null &&
        request.cart.customer!.customerId.isNotEmpty) {
      final customerId = request.cart.customer!.customerId;
      final customerSnap = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('customers')
          .doc(customerId)
          .get();
      final bal =
          (customerSnap.data()?['balanceMinor'] as num?)?.toInt() ??
          totals.balanceDueMinor;
      await OperationalAlertService().onCustomerCreditCreated(
        businessId: businessId,
        businessName: businessName,
        customerId: customerId,
        customerName:
            (customerSnap.data()?['name'] as String?) ??
            request.cart.customer!.name,
        balanceMinor: bal,
        currencySymbol: request.business.currency.symbol,
      );
    }
  }

  @override
  Future<void> voidSale(
    String businessId,
    String saleId, {
    required String reason,
    String? voidedByUid,
    String? voidedByName,
  }) async {
    final user = _auth.currentUser;
    final actorUid = voidedByUid ?? user?.uid;
    if (actorUid == null || actorUid.isEmpty) {
      throw const SaleException('unauthenticated');
    }
    final trimmed = reason.trim();
    if (trimmed.length < 2) {
      throw const SaleException(
        'failed-precondition',
        message: 'Enter a void reason.',
      );
    }
    if (businessId.trim().isEmpty || saleId.trim().isEmpty) {
      throw const SaleException('failed-precondition');
    }

    if (_useAuthoritativeInventoryApi) {
      try {
        await _apiClient.postJson(
          '/api/inventory/sales/void',
          body: <String, dynamic>{
            'businessId': businessId,
            'saleId': saleId,
            'reason': trimmed,
            'voidedByUid': actorUid,
            'voidedByName': voidedByName,
          },
          timeout: const Duration(seconds: 90),
        );
        return;
      } on ApiException catch (error) {
        // Inventory void route may not be deployed yet on Vercel (404).
        if (error.statusCode != 404 && error.statusCode != 405) {
          throw SaleException(
            error.code ?? 'unavailable',
            message: error.message,
          );
        }
      }
    }

    final business = _firestore.collection('businesses').doc(businessId);
    final sale = business.collection('sales').doc(saleId);
    final activity = business.collection('activity').doc();

    try {
      await _firestore.runTransaction((transaction) async {
        final saleSnap = await transaction.get(sale);
        if (!saleSnap.exists) {
          throw const SaleException('not-found', message: 'Sale not found.');
        }
        final data = saleSnap.data()!;
        final status = SaleStatus.values.firstWhere(
          (s) => s.name == (data['saleStatus'] ?? data['status']),
          orElse: () => SaleStatus.completed,
        );
        if (status == SaleStatus.voided) {
          throw const SaleException(
            'already-voided',
            message: 'This sale is already voided.',
          );
        }

        final rawItems = (data['items'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        // Read all tracked products before writes.
        final productSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final item in rawItems) {
          final productId = (item['productId'] as String?)?.trim();
          final trackStock = item['trackStock'] as bool? ?? false;
          if (!trackStock || productId == null || productId.isEmpty) continue;
          if (productSnaps.containsKey(productId)) continue;
          productSnaps[productId] = await transaction.get(
            business.collection('products').doc(productId),
          );
        }

        DocumentReference<Map<String, dynamic>>? customerRef;
        DocumentSnapshot<Map<String, dynamic>>? customerSnap;
        final customerId = (data['customerId'] as String?)?.trim();
        if (customerId != null && customerId.isNotEmpty) {
          customerRef = business.collection('customers').doc(customerId);
          customerSnap = await transaction.get(customerRef);
        }

        final totalMinor =
            (data['totalMinor'] as num?)?.toInt() ??
            moneyToMinor(data['total']);
        final subtotalMinor =
            (data['subtotalMinor'] as num?)?.toInt() ??
            moneyToMinor(data['subtotal']);
        final discountMinor =
            (data['discountMinor'] as num?)?.toInt() ??
            moneyToMinor(data['discount']);
        final taxMinor =
            (data['taxMinor'] as num?)?.toInt() ?? moneyToMinor(data['tax']);
        final amountPaidMinor =
            (data['amountPaidMinor'] as num?)?.toInt() ??
            moneyToMinor(data['amountPaid']);
        final balanceDueMinor =
            (data['balanceDueMinor'] as num?)?.toInt() ?? 0;
        final receiptNumber =
            (data['receiptNumber'] as String?) ?? saleId;
        final createdAt =
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        final dateKey = DateFormat('yyyyMMdd').format(createdAt.toLocal());
        final itemsSold = rawItems.fold<double>(
          0,
          (total, item) =>
              total + ((item['quantity'] as num?)?.toDouble() ?? 0),
        );

        transaction.update(sale, <String, Object?>{
          'saleStatus': SaleStatus.voided.name,
          'status': SaleStatus.voided.name,
          'voidReason': trimmed,
          'voidedBy': actorUid,
          'voidedByName': voidedByName ?? user?.displayName ?? user?.email,
          'voidedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': actorUid,
        });

        final runningStock = <String, double>{};
        for (final item in rawItems) {
          final productId = (item['productId'] as String?)?.trim();
          final trackStock = item['trackStock'] as bool? ?? false;
          final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
          if (!trackStock ||
              productId == null ||
              productId.isEmpty ||
              qty <= 0) {
            continue;
          }
          final productSnap = productSnaps[productId];
          if (productSnap == null || !productSnap.exists) continue;
          final before =
              runningStock[productId] ??
              ((productSnap.data()?['quantity'] as num?)?.toDouble() ?? 0);
          final after = before + qty;
          runningStock[productId] = after;
          transaction.update(
            business.collection('products').doc(productId),
            <String, Object?>{
              'quantity': after,
              'updatedAt': FieldValue.serverTimestamp(),
              'updatedBy': actorUid,
            },
          );
          final movement = business.collection('inventory_movements').doc();
          transaction.set(movement, <String, Object?>{
            'id': movement.id,
            'productId': productId,
            'productName': item['name'] as String? ?? 'Item',
            'type': 'stock_in',
            'quantityChange': qty,
            'stockBefore': before,
            'stockAfter': after,
            'reason': 'Sale void',
            'note': trimmed,
            'referenceType': 'sale_void',
            'referenceId': saleId,
            'createdBy': actorUid,
            'createdByName': voidedByName,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        if (customerRef != null &&
            customerSnap != null &&
            customerSnap.exists) {
          final previousBalance =
              (customerSnap.data()?['balanceMinor'] as num?)?.toInt() ??
              moneyToMinor(customerSnap.data()?['balance']);
          final updatedBalance = previousBalance - balanceDueMinor;
          transaction.update(customerRef, <String, Object?>{
            'balanceMinor': updatedBalance,
            'balance': minorToMoney(updatedBalance),
            'totalCreditMinor': FieldValue.increment(-balanceDueMinor),
            'totalSalesMinor': FieldValue.increment(-totalMinor),
            'totalPaidMinor': FieldValue.increment(-amountPaidMinor),
            'purchaseCount': FieldValue.increment(-1),
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': actorUid,
          });
          if (balanceDueMinor > 0) {
            transaction.set(
              customerRef.collection('ledger').doc(),
              <String, Object?>{
                'type': 'sale_void',
                'saleId': saleId,
                'receiptNumber': receiptNumber,
                'debitMinor': 0,
                'creditMinor': balanceDueMinor,
                'balanceBeforeMinor': previousBalance,
                'balanceAfterMinor': updatedBalance,
                'createdBy': actorUid,
                'createdByName': voidedByName,
                'createdAt': FieldValue.serverTimestamp(),
              },
            );
          }
        }

        transaction.set(activity, <String, Object?>{
          'activityId': activity.id,
          'businessId': businessId,
          'type': 'sale_void',
          'title': 'Sale voided',
          'subtitle': 'Receipt $receiptNumber · $trimmed',
          'amount': minorToMoney(totalMinor),
          'amountMinor': totalMinor,
          'currencyCode': data['currencyCode'] as String? ?? 'SLE',
          'referenceId': saleId,
          'createdBy': actorUid,
          'createdByName': voidedByName,
          'timestamp': FieldValue.serverTimestamp(),
        });

        transaction.set(
          business.collection('analytics').doc('daily_$dateKey'),
          <String, Object?>{
            'dateKey': dateKey,
            'grossSalesMinor': FieldValue.increment(-subtotalMinor),
            'discountMinor': FieldValue.increment(-discountMinor),
            'taxMinor': FieldValue.increment(-taxMinor),
            'netSalesMinor': FieldValue.increment(-totalMinor),
            'amountPaidMinor': FieldValue.increment(-amountPaidMinor),
            'creditCreatedMinor': FieldValue.increment(-balanceDueMinor),
            'orderCount': FieldValue.increment(-1),
            'itemsSold': FieldValue.increment(-itemsSold),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    } on SaleException {
      rethrow;
    } on FirebaseException catch (e) {
      throw SaleException(e.code, message: e.message);
    }
  }

  @override
  Stream<List<SaleHistoryItem>> watchRecentSales(
    String businessId, {
    int limit = 25,
  }) {
    if (businessId.trim().isEmpty) {
      return Stream<List<SaleHistoryItem>>.value(const <SaleHistoryItem>[]);
    }
    return _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('sales')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => SaleHistoryItem.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  @override
  Future<Map<String, dynamic>?> getSale(
    String businessId,
    String saleId,
  ) async {
    if (businessId.trim().isEmpty || saleId.trim().isEmpty) return null;
    final snapshot = await _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('sales')
        .doc(saleId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return <String, dynamic>{...data, 'saleId': snapshot.id};
  }

  @override
  Future<Sale?> getSaleDocument(String businessId, String saleId) async {
    if (businessId.trim().isEmpty || saleId.trim().isEmpty) return null;
    final snapshot = await _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('sales')
        .doc(saleId)
        .get();
    if (!snapshot.exists || snapshot.data() == null) return null;
    return Sale.fromFirestore(snapshot);
  }

  CompletedSale _completedFromExisting(
    String saleId,
    Map<String, dynamic> data,
  ) => CompletedSale(
    saleId: saleId,
    receiptNumber: data['receiptNumber'] as String? ?? saleId,
    totalMinor:
        (data['totalMinor'] as num?)?.toInt() ?? moneyToMinor(data['total']),
    amountPaidMinor:
        (data['amountPaidMinor'] as num?)?.toInt() ??
        moneyToMinor(data['amountPaid']),
    balanceDueMinor: (data['balanceDueMinor'] as num?)?.toInt() ?? 0,
    changeMinor: (data['changeMinor'] as num?)?.toInt() ?? 0,
    paymentMethod: PaymentMethod.values.firstWhere(
      (method) => method.storedValue == data['paymentMethod'],
      orElse: () => PaymentMethod.cash,
    ),
  );
}

class SaleException implements Exception {
  const SaleException(this.code, {this.message});

  final String code;
  final String? message;

  String get friendlyMessage =>
      message ??
      switch (code) {
        'permission-denied' =>
          'You do not have permission to complete this sale.',
        'unavailable' => 'The sales service is temporarily unavailable.',
        'unauthenticated' => 'Your session expired. Please sign in again.',
        'failed-precondition' => 'Some items no longer have enough stock.',
        'deadline-exceeded' =>
          'The sale took too long to process. Please try again.',
        'already-exists' => 'This sale has already been completed.',
        'already-voided' => 'This sale is already voided.',
        'not-found' => 'Sale not found.',
        _ => 'Something went wrong while completing the sale.',
      };

  @override
  String toString() => 'SaleException($code): $friendlyMessage';
}
