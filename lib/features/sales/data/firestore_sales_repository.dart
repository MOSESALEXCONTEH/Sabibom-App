// ignore_for_file: avoid_types_as_parameter_names

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../../core/sync/offline_mutation_queue.dart';
import '../../branches/domain/business_branch.dart';
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
    OfflineMutationQueue? offlineQueue,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _apiClient = apiClient ?? AuthenticatedApiClient(),
       _offlineQueue = offlineQueue ?? OfflineMutationQueue();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final AuthenticatedApiClient _apiClient;
  final OfflineMutationQueue _offlineQueue;
  final bool _useAuthoritativeInventoryApi = true;

  @override
  Future<CompletedSale> completeSale(CompleteSaleRequest request) async {
    final user = _auth.currentUser;
    if (user == null) throw const SaleException('unauthenticated');
    if (request.business.businessId.trim().isEmpty ||
        request.branchId.trim().isEmpty) {
      throw const SaleException(
        'failed-precondition',
        message: 'Select an active branch before completing the sale.',
      );
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

    final apiBody = _saleRequestBody(request, totals);
    if (request.queueWhenOffline) {
      return _queueSale(request, totals, apiBody);
    }

    if (_useAuthoritativeInventoryApi) {
      try {
        final response = await _apiClient.postJson(
          '/api/inventory/sales/complete',
          body: apiBody,
          timeout: const Duration(seconds: 20),
        );
        await _evaluatePostSaleAlerts(request, totals);
        return CompletedSale(
          saleId: response['saleId'] as String? ?? request.saleId,
          businessId:
              response['businessId'] as String? ?? request.business.businessId,
          branchId: response['branchId'] as String? ?? request.branchId,
          branchNameSnapshot:
              response['branchNameSnapshot'] as String? ??
              request.branchNameSnapshot,
          branchCodeSnapshot:
              response['branchCodeSnapshot'] as String? ??
              request.branchCodeSnapshot,
          receiptNumber: response['receiptNumber'] as String? ?? request.saleId,
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
          if (error.statusCode == null) {
            return _queueSale(request, totals, apiBody);
          }
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
    final branch = business.collection('branches').doc(request.branchId);
    final counter = branch.collection('counters').doc('sales');
    final activity = business.collection('activity').doc();
    final today = DateFormat('yyyyMMdd').format(DateTime.now());
    final analytics = business
        .collection('analytics')
        .doc('daily_${today}_${request.branchId}');

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
        branch: branch,
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

  Map<String, dynamic> _saleRequestBody(
    CompleteSaleRequest request,
    SaleTotals totals,
  ) => <String, dynamic>{
    'saleId': request.saleId,
    'businessId': request.business.businessId,
    'branchId': request.branchId,
    'branchNameSnapshot': request.branchNameSnapshot,
    'branchCodeSnapshot': request.branchCodeSnapshot,
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
  };

  Future<CompletedSale> _queueSale(
    CompleteSaleRequest request,
    SaleTotals totals,
    Map<String, dynamic> body,
  ) async {
    await _offlineQueue.enqueue(
      id: 'sale_${request.saleId}',
      type: OfflineMutationType.saleComplete,
      businessId: request.business.businessId,
      payload: <String, dynamic>{
        'request': body,
        'summary': <String, dynamic>{
          'saleId': request.saleId,
          'businessId': request.business.businessId,
          'branchId': request.branchId,
          'branchNameSnapshot': request.branchNameSnapshot,
          'branchCodeSnapshot': request.branchCodeSnapshot,
          'receiptNumber': 'Pending ${request.saleId.substring(0, 8)}',
          'customerId': request.cart.customer?.customerId,
          'customerName': request.cart.customer?.name ?? 'Walk-in Customer',
          'customerPhone': request.cart.customer?.phone,
          'items': body['items'],
          'subtotalMinor': totals.subtotalMinor,
          'discountMinor': totals.itemDiscountMinor + totals.orderDiscountMinor,
          'taxMinor': totals.taxMinor,
          'totalMinor': totals.totalMinor,
          'amountPaidMinor': totals.amountPaidMinor,
          'balanceDueMinor': totals.balanceDueMinor,
          'changeMinor': totals.changeMinor,
          'currencyCode': request.business.currency.code,
          'currencySymbol': request.business.currency.symbol,
          'paymentMethod': request.cart.paymentMethod.storedValue,
          'paymentStatus': totals.balanceDueMinor == 0
              ? PaymentStatus.paid.name
              : PaymentStatus.partiallyPaid.name,
          'saleStatus': SaleStatus.completed.name,
          'note': body['note'],
          'createdByName': request.cashierName,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      },
    );
    return CompletedSale(
      saleId: request.saleId,
      businessId: request.business.businessId,
      branchId: request.branchId,
      branchNameSnapshot: request.branchNameSnapshot,
      branchCodeSnapshot: request.branchCodeSnapshot,
      receiptNumber: 'Pending ${request.saleId.substring(0, 8)}',
      totalMinor: totals.totalMinor,
      amountPaidMinor: totals.amountPaidMinor,
      balanceDueMinor: totals.balanceDueMinor,
      changeMinor: totals.changeMinor,
      paymentMethod: request.cart.paymentMethod,
      isPendingSync: true,
    );
  }

  Future<CompletedSale> _runCompleteSaleTransaction({
    required CompleteSaleRequest request,
    required SaleTotals totals,
    required User user,
    required DocumentReference<Map<String, dynamic>> business,
    required DocumentReference<Map<String, dynamic>> sale,
    required DocumentReference<Map<String, dynamic>> branch,
    required DocumentReference<Map<String, dynamic>> counter,
    required DocumentReference<Map<String, dynamic>> activity,
    required DocumentReference<Map<String, dynamic>> analytics,
    required String today,
    required Map<String, Object?> receiptTemplateSnapshot,
  }) async {
    final completed = await _firestore.runTransaction((transaction) async {
      final businessSnapshot = await transaction.get(business);
      final branchSnapshot = await transaction.get(branch);
      if (!businessSnapshot.exists) throw const SaleException('not-found');
      if (!branchSnapshot.exists ||
          branchSnapshot.data()?['status'] != BranchStatus.active.storedValue) {
        throw const SaleException(
          'failed-precondition',
          message: 'This branch is inactive and cannot receive new sales.',
        );
      }
      final existing = await transaction.get(sale);
      if (existing.exists) {
        final data = existing.data()!;
        return _completedFromExisting(request.saleId, data);
      }

      final productSnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      final inventorySnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final item in request.cart.items.where(
        (item) => item.trackStock && item.productId != null,
      )) {
        final productId = item.productId!;
        if (productSnapshots.containsKey(productId)) continue;
        productSnapshots[productId] = await transaction.get(
          business.collection('products').doc(productId),
        );
        inventorySnapshots[productId] = await transaction.get(
          branch.collection('inventory').doc(productId),
        );
      }
      for (final item in request.cart.items.where(
        (item) => item.trackStock && item.productId != null,
      )) {
        final productId = item.productId!;
        final product = productSnapshots[productId];
        if (product == null || !product.exists) {
          throw SaleException(
            'failed-precondition',
            message: '${item.name} is no longer available.',
          );
        }
        final inventory = inventorySnapshots[productId];
        final available =
            (inventory?.data()?['availableQuantity'] as num?)?.toDouble() ??
            (inventory?.data()?['quantity'] as num?)?.toDouble() ??
            (request.branchId == 'main'
                ? (product.data()?['quantity'] as num?)?.toDouble() ?? 0
                : 0);
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
          '${request.branchCodeSnapshot}-${nextNumber.toString().padLeft(6, '0')}';

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
        'branchNameSnapshot': request.branchNameSnapshot,
        'branchCodeSnapshot': request.branchCodeSnapshot,
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
        final inventoryReference = branch
            .collection('inventory')
            .doc(productId);
        final productSnapshot = productSnapshots[productId]!;
        final inventorySnapshot = inventorySnapshots[productId]!;
        final inventoryData = inventorySnapshot.data();
        final before =
            runningStock[productId] ??
            (inventoryData?['quantity'] as num?)?.toDouble() ??
            (request.branchId == 'main'
                ? (productSnapshot.data()?['quantity'] as num?)?.toDouble() ?? 0
                : 0);
        final reserved =
            (inventoryData?['reservedQuantity'] as num?)?.toDouble() ?? 0;
        final after = before - item.quantity;
        runningStock[productId] = after;
        transaction.set(inventoryReference, <String, Object?>{
          'businessId': request.business.businessId,
          'branchId': request.branchId,
          'productId': productId,
          'quantity': after,
          'reservedQuantity': reserved,
          'availableQuantity': after - reserved,
          'lowStockThreshold':
              (inventoryData?['lowStockThreshold'] as num?)?.toDouble() ??
              (productSnapshot.data()?['lowStockThreshold'] as num?)
                  ?.toDouble() ??
              0,
          'averageUnitCostMinor':
              (inventoryData?['averageUnitCostMinor'] as num?)?.round() ??
              item.costPriceMinor,
          'realizedGrossProfitMinor': FieldValue.increment(
            (item.unitPriceMinor - item.costPriceMinor) * item.quantity.round(),
          ),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': user.uid,
          if (!inventorySnapshot.exists)
            'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        // Compatibility aggregate only. Branch inventory is authoritative.
        transaction.update(productReference, <String, Object?>{
          if (request.branchId == 'main')
            'quantity': FieldValue.increment(-item.quantity),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        final movement = business.collection('inventory_movements').doc();
        transaction.set(movement, <String, Object?>{
          'id': movement.id,
          'businessId': request.business.businessId,
          'branchId': request.branchId,
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
              'branchId': request.branchId,
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
        'branchId': request.branchId,
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
        'branchId': request.branchId,
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
        businessId: request.business.businessId,
        branchId: request.branchId,
        branchNameSnapshot: request.branchNameSnapshot,
        branchCodeSnapshot: request.branchCodeSnapshot,
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
      final definition = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('products')
          .doc(productId)
          .get();
      final inventory = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('branches')
          .doc(request.branchId)
          .collection('inventory')
          .doc(productId)
          .get();
      if (!definition.exists) continue;
      var product = Product.fromFirestore(definition);
      if (inventory.exists && inventory.data() != null) {
        final data = inventory.data()!;
        product = product.withStockSnapshot(
          quantity:
              (data['availableQuantity'] as num?)?.toDouble() ??
              (data['quantity'] as num?)?.toDouble() ??
              0,
          lowStockThreshold:
              (data['lowStockThreshold'] as num?)?.toDouble() ??
              product.lowStockThreshold,
          averageUnitCostMinor:
              (data['averageUnitCostMinor'] as num?)?.round() ??
              product.costPriceMinor,
          stockCostValueMinor:
              (data['stockCostValueMinor'] as num?)?.round() ?? 0,
          expectedStockRevenueMinor:
              (data['expectedStockRevenueMinor'] as num?)?.round() ?? 0,
          potentialProfitRemainingMinor:
              (data['potentialProfitRemainingMinor'] as num?)?.round() ?? 0,
          realizedGrossProfitMinor:
              (data['realizedGrossProfitMinor'] as num?)?.round() ?? 0,
          expiringQuantity: (data['expiringQuantity'] as num?)?.toDouble() ?? 0,
          expiredQuantity: (data['expiredQuantity'] as num?)?.toDouble() ?? 0,
          unknownExpiryQuantity:
              (data['unknownExpiryQuantity'] as num?)?.toDouble() ?? 0,
          expiryStatus: ProductExpiryStatus.fromStorage(data['expiryStatus']),
          nextExpiryDate: (data['nextExpiryDate'] as Timestamp?)?.toDate(),
          nextExpiryBatchId: data['nextExpiryBatchId'] as String?,
          nextExpiryBatchQuantity:
              (data['nextExpiryBatchQuantity'] as num?)?.toDouble() ?? 0,
        );
      }
      await StockAlertService().evaluateProduct(
        businessId: businessId,
        businessName: businessName,
        branchId: request.branchId,
        product: product,
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
        branchId: request.branchId,
        saleId: request.saleId,
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
    required String branchId,
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
    final writableBranchId = normalizeBranchId(branchId);
    if (writableBranchId == null) {
      throw const SaleException(
        'failed-precondition',
        message: 'Select an active branch before voiding the sale.',
      );
    }

    if (_useAuthoritativeInventoryApi) {
      try {
        await _apiClient.postJson(
          '/api/inventory/sales/void',
          body: <String, dynamic>{
            'businessId': businessId,
            'branchId': writableBranchId,
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
        final saleBranchId = normalizeBranchId(data['branchId'] as String?);
        if (saleBranchId == null) {
          throw const SaleException(
            'failed-precondition',
            message:
                'This legacy sale must be migrated before it can be voided.',
          );
        }
        if (saleBranchId != writableBranchId) {
          throw const SaleException(
            'failed-precondition',
            message: 'The sale does not belong to the selected branch.',
          );
        }
        final branchRef = business.collection('branches').doc(saleBranchId);
        final branchSnapshot = await transaction.get(branchRef);
        if (!branchSnapshot.exists ||
            branchSnapshot.data()?['status'] !=
                BranchStatus.active.storedValue) {
          throw const SaleException(
            'failed-precondition',
            message: 'Reactivate the original branch before voiding this sale.',
          );
        }
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

        // Read all tracked products and their original branch stock before
        // writing anything.
        final productSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        final inventorySnaps =
            <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final item in rawItems) {
          final productId = (item['productId'] as String?)?.trim();
          final trackStock = item['trackStock'] as bool? ?? false;
          if (!trackStock || productId == null || productId.isEmpty) continue;
          if (productSnaps.containsKey(productId)) continue;
          productSnaps[productId] = await transaction.get(
            business.collection('products').doc(productId),
          );
          inventorySnaps[productId] = await transaction.get(
            branchRef.collection('inventory').doc(productId),
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
        final balanceDueMinor = (data['balanceDueMinor'] as num?)?.toInt() ?? 0;
        final receiptNumber = (data['receiptNumber'] as String?) ?? saleId;
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
          final inventorySnap = inventorySnaps[productId];
          if (productSnap == null || !productSnap.exists) continue;
          final inventoryData = inventorySnap?.data();
          final before =
              runningStock[productId] ??
              (inventoryData?['quantity'] as num?)?.toDouble() ??
              (saleBranchId == 'main'
                  ? (productSnap.data()?['quantity'] as num?)?.toDouble() ?? 0
                  : 0);
          final reserved =
              (inventoryData?['reservedQuantity'] as num?)?.toDouble() ?? 0;
          final after = before + qty;
          runningStock[productId] = after;
          transaction.set(
            branchRef.collection('inventory').doc(productId),
            <String, Object?>{
              'businessId': businessId,
              'branchId': saleBranchId,
              'productId': productId,
              'quantity': after,
              'reservedQuantity': reserved,
              'availableQuantity': after - reserved,
              'lowStockThreshold':
                  (inventoryData?['lowStockThreshold'] as num?)?.toDouble() ??
                  (productSnap.data()?['lowStockThreshold'] as num?)
                      ?.toDouble() ??
                  0,
              'averageUnitCostMinor':
                  (inventoryData?['averageUnitCostMinor'] as num?)?.round() ??
                  (item['costPriceMinor'] as num?)?.round() ??
                  0,
              'updatedAt': FieldValue.serverTimestamp(),
              'updatedBy': actorUid,
              if (!(inventorySnap?.exists ?? false))
                'createdAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          transaction.update(
            business.collection('products').doc(productId),
            <String, Object?>{
              'quantity': FieldValue.increment(qty),
              'updatedAt': FieldValue.serverTimestamp(),
              'updatedBy': actorUid,
            },
          );
          final movement = business.collection('inventory_movements').doc();
          transaction.set(movement, <String, Object?>{
            'id': movement.id,
            'businessId': businessId,
            'branchId': saleBranchId,
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
            transaction
                .set(customerRef.collection('ledger').doc(), <String, Object?>{
                  'type': 'sale_void',
                  'saleId': saleId,
                  'receiptNumber': receiptNumber,
                  'branchId': saleBranchId,
                  'debitMinor': 0,
                  'creditMinor': balanceDueMinor,
                  'balanceBeforeMinor': previousBalance,
                  'balanceAfterMinor': updatedBalance,
                  'createdBy': actorUid,
                  'createdByName': voidedByName,
                  'createdAt': FieldValue.serverTimestamp(),
                });
          }
        }

        transaction.set(activity, <String, Object?>{
          'activityId': activity.id,
          'businessId': businessId,
          'branchId': saleBranchId,
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
          business
              .collection('analytics')
              .doc('daily_${dateKey}_$saleBranchId'),
          <String, Object?>{
            'dateKey': dateKey,
            'branchId': saleBranchId,
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
    String? branchId,
    int limit = 25,
  }) {
    if (businessId.trim().isEmpty) {
      return Stream<List<SaleHistoryItem>>.value(const <SaleHistoryItem>[]);
    }
    var query = _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('sales')
        .orderBy('createdAt', descending: true);
    final normalizedBranchId = normalizeBranchId(branchId);
    if (normalizedBranchId != null && normalizedBranchId != 'main') {
      query = query.where('branchId', isEqualTo: normalizedBranchId);
    }
    return query
        .limit(
          normalizedBranchId == null || normalizedBranchId == 'main'
              ? limit * 4
              : limit,
        )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => matchesBranchScope(doc.data(), branchId))
              .map((doc) => SaleHistoryItem.fromFirestore(doc.id, doc.data()))
              .take(limit)
              .toList(),
        );
  }

  @override
  Future<Map<String, dynamic>?> getSale(
    String businessId,
    String saleId, {
    String? branchId,
  }) async {
    if (businessId.trim().isEmpty || saleId.trim().isEmpty) return null;
    final snapshot = await _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('sales')
        .doc(saleId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    if (!matchesBranchScope(data, branchId)) return null;
    return <String, dynamic>{...data, 'saleId': snapshot.id};
  }

  @override
  Future<Sale?> getSaleDocument(
    String businessId,
    String saleId, {
    String? branchId,
  }) async {
    if (businessId.trim().isEmpty || saleId.trim().isEmpty) return null;
    final snapshot = await _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('sales')
        .doc(saleId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    if (!matchesBranchScope(data, branchId)) return null;
    return Sale.fromFirestore(snapshot);
  }

  CompletedSale _completedFromExisting(
    String saleId,
    Map<String, dynamic> data,
  ) => CompletedSale(
    saleId: saleId,
    businessId: data['businessId'] as String? ?? '',
    branchId: data['branchId'] as String? ?? '',
    branchNameSnapshot: data['branchNameSnapshot'] as String? ?? 'Branch',
    branchCodeSnapshot: data['branchCodeSnapshot'] as String? ?? '',
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
