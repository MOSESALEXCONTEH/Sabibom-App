import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../branches/domain/business_branch.dart';
import '../../sales/domain/sale_models.dart';
import '../domain/purchase.dart';
import '../domain/purchase_calculator.dart';

class CompletePurchaseRequest {
  const CompletePurchaseRequest({
    required this.purchaseId,
    required this.businessId,
    required this.branchId,
    required this.branchNameSnapshot,
    required this.branchCodeSnapshot,
    required this.supplierId,
    required this.supplierName,
    required this.items,
    required this.amountPaidMinor,
    this.orderDiscountType,
    this.orderDiscountValue = 0,
    this.taxPercentage = 0,
    this.deliveryMinor = 0,
    this.paymentMethod,
  });

  final String purchaseId;
  final String businessId;
  final String branchId;
  final String branchNameSnapshot;
  final String branchCodeSnapshot;
  final String supplierId;
  final String supplierName;
  final List<PurchaseItem> items;
  final DiscountType? orderDiscountType;
  final double orderDiscountValue;
  final double taxPercentage;
  final int deliveryMinor;
  final int amountPaidMinor;
  final String? paymentMethod;
}

class CreatePurchaseReturnRequest {
  const CreatePurchaseReturnRequest({
    required this.returnId,
    required this.businessId,
    required this.purchaseId,
    required this.quantities,
    this.note,
  });

  final String returnId;
  final String businessId;
  final String purchaseId;
  final Map<String, double> quantities;
  final String? note;
}

abstract class PurchasesRepository {
  Stream<List<Purchase>> watchPurchases(String businessId, {String? branchId});
  Future<Purchase?> getPurchase(
    String businessId,
    String purchaseId, {
    String? branchId,
  });
  Future<Purchase> completePurchase(CompletePurchaseRequest request);
  Future<void> createPurchaseReturn(
    CreatePurchaseReturnRequest request, {
    String? branchId,
  });
  Future<void> voidPurchase(
    String businessId,
    String purchaseId, {
    required String reason,
    String? branchId,
  });
}

class FirestorePurchasesRepository implements PurchasesRepository {
  FirestorePurchasesRepository({
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
  Stream<List<Purchase>> watchPurchases(String businessId, {String? branchId}) {
    if (businessId.trim().isEmpty) return Stream.value(const <Purchase>[]);
    var query = _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('purchases')
        .orderBy('createdAt', descending: true);
    final normalizedBranchId = normalizeBranchId(branchId);
    if (normalizedBranchId != null && normalizedBranchId != 'main') {
      query = query.where('branchId', isEqualTo: normalizedBranchId);
    }
    return query
        .limit(
          normalizedBranchId == null || normalizedBranchId == 'main'
              ? 800
              : 500,
        )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => matchesBranchScope(doc.data(), branchId))
              .map(Purchase.fromFirestore)
              .take(500)
              .toList(),
        );
  }

  @override
  Future<Purchase?> getPurchase(
    String businessId,
    String purchaseId, {
    String? branchId,
  }) async {
    if (businessId.trim().isEmpty || purchaseId.trim().isEmpty) return null;
    final document = await _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('purchases')
        .doc(purchaseId)
        .get();
    if (!document.exists || document.data() == null) return null;
    if (!matchesBranchScope(document.data()!, branchId)) return null;
    return Purchase.fromFirestore(document);
  }

  @override
  Future<Purchase> completePurchase(CompletePurchaseRequest request) async {
    final user = _auth.currentUser;
    if (user == null) throw const PurchaseException('unauthenticated');
    final writableBranchId = normalizeBranchId(request.branchId);
    if (writableBranchId == null) {
      throw const PurchaseException(
        'failed-precondition',
        message: 'Switch to an active branch before completing a purchase.',
      );
    }
    if (request.businessId.trim().isEmpty ||
        request.purchaseId.trim().isEmpty ||
        request.supplierId.trim().isEmpty ||
        request.items.isEmpty) {
      throw const PurchaseException(
        'failed-precondition',
        message: 'Select a supplier and add at least one product.',
      );
    }
    if (_useAuthoritativeInventoryApi) {
      try {
        await _apiClient.postJson(
          '/api/inventory/purchases/complete',
          body: <String, dynamic>{
            'purchaseId': request.purchaseId,
            'businessId': request.businessId,
            'branchId': writableBranchId,
            'branchNameSnapshot': request.branchNameSnapshot,
            'branchCodeSnapshot': request.branchCodeSnapshot,
            'supplierId': request.supplierId,
            'supplierName': request.supplierName,
            'items': request.items.map((item) => item.toMap()).toList(),
            'orderDiscountType': request.orderDiscountType?.name,
            'orderDiscountValue': request.orderDiscountValue,
            'taxPercentage': request.taxPercentage,
            'deliveryMinor': request.deliveryMinor,
            'amountPaidMinor': request.amountPaidMinor,
            'paymentMethod': request.paymentMethod,
          },
          timeout: const Duration(seconds: 90),
        );
        final completed = await getPurchase(
          request.businessId,
          request.purchaseId,
          branchId: writableBranchId,
        );
        if (completed == null) {
          throw const PurchaseException(
            'unavailable',
            message:
                'The purchase was saved but could not be refreshed. Try again.',
          );
        }
        return completed;
      } on ApiException catch (error) {
        // Inventory purchase route may not be deployed yet on Vercel (404).
        // Fall through to the Firestore completion path below.
        if (error.statusCode != 404 && error.statusCode != 405) {
          throw PurchaseException(
            error.code ?? 'unavailable',
            message: error.message,
          );
        }
      }
    }
    final totals = PurchaseCalculator.calculate(
      items: request.items,
      orderDiscountType: request.orderDiscountType,
      orderDiscountValue: request.orderDiscountValue,
      taxPercentage: request.taxPercentage,
      deliveryMinor: request.deliveryMinor,
      amountPaidMinor: request.amountPaidMinor,
    );
    final business = _firestore
        .collection('businesses')
        .doc(request.businessId);
    final purchase = business.collection('purchases').doc(request.purchaseId);
    final branch = business.collection('branches').doc(writableBranchId);
    final counter = branch.collection('counters').doc('purchases');
    final supplier = business.collection('suppliers').doc(request.supplierId);
    final today = DateFormat('yyyyMMdd').format(DateTime.now());
    final analytics = business
        .collection('analytics')
        .doc('daily_${today}_$writableBranchId');
    final activity = business.collection('activity').doc();

    try {
      return await _firestore.runTransaction((transaction) async {
        final businessSnapshot = await transaction.get(business);
        final branchSnapshot = await transaction.get(branch);
        final existing = await transaction.get(purchase);
        if (existing.exists) return Purchase.fromFirestore(existing);
        if (!businessSnapshot.exists) {
          throw const PurchaseException('not-found');
        }
        if (!branchSnapshot.exists ||
            branchSnapshot.data()?['status'] !=
                BranchStatus.active.storedValue) {
          throw const PurchaseException(
            'failed-precondition',
            message: 'This branch is inactive and cannot receive purchases.',
          );
        }
        final supplierSnapshot = await transaction.get(supplier);
        if (!supplierSnapshot.exists ||
            (supplierSnapshot.data()?['status'] as String? ?? 'active') !=
                'active') {
          throw const PurchaseException(
            'failed-precondition',
            message: 'The selected supplier is no longer active.',
          );
        }
        final counterSnapshot = await transaction.get(counter);
        final products = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        final inventories = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final item in request.items) {
          if (products.containsKey(item.productId)) continue;
          products[item.productId] = await transaction.get(
            business.collection('products').doc(item.productId),
          );
          inventories[item.productId] = await transaction.get(
            branch.collection('inventory').doc(item.productId),
          );
        }
        for (final item in request.items) {
          if (!(products[item.productId]?.exists ?? false)) {
            throw PurchaseException(
              'failed-precondition',
              message: '${item.name} is no longer available.',
            );
          }
        }

        final nextNumber =
            (counterSnapshot.data()?['nextNumber'] as num?)?.toInt() ?? 1;
        final branchCode = (branchSnapshot.data()?['code'] as String?)
            ?.trim()
            .toUpperCase();
        final purchaseNumber = branchCode == null || branchCode.isEmpty
            ? formatPurchaseNumber(today, nextNumber)
            : 'PUR-$branchCode-${nextNumber.toString().padLeft(6, '0')}';
        final paymentStatus = totals.balanceDueMinor == 0
            ? PurchasePaymentStatus.paid
            : totals.amountPaidMinor == 0
            ? PurchasePaymentStatus.unpaid
            : PurchasePaymentStatus.partiallyPaid;
        final itemMaps = request.items.map((item) {
          final subtotal = PurchaseCalculator.lineSubtotal(item);
          final discount = PurchaseCalculator.lineDiscount(item);
          return <String, Object?>{
            ...item.toMap(),
            'lineSubtotalMinor': subtotal,
            'discountAmountMinor': discount,
            'lineTotalMinor': subtotal - discount,
          };
        }).toList();

        transaction.set(counter, <String, Object?>{
          'nextNumber': nextNumber + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        transaction.set(purchase, <String, Object?>{
          'purchaseId': request.purchaseId,
          'businessId': request.businessId,
          'branchId': writableBranchId,
          'branchNameSnapshot':
              (branchSnapshot.data()?['name'] as String?)?.trim() ??
              request.branchNameSnapshot,
          'branchCodeSnapshot':
              (branchSnapshot.data()?['code'] as String?)?.trim() ??
              request.branchCodeSnapshot,
          'purchaseNumber': purchaseNumber,
          'supplierId': request.supplierId,
          'supplierName': request.supplierName,
          'items': itemMaps,
          'itemCount': request.items.length,
          'subtotalMinor': totals.subtotalMinor,
          'discountMinor': totals.itemDiscountMinor + totals.orderDiscountMinor,
          'taxMinor': totals.taxMinor,
          'deliveryMinor': totals.deliveryMinor,
          'totalMinor': totals.totalMinor,
          'amountPaidMinor': totals.amountPaidMinor,
          'balanceDueMinor': totals.balanceDueMinor,
          'paymentMethod': request.paymentMethod,
          'paymentStatus': paymentStatus.name,
          'status': PurchaseStatus.completed.name,
          'createdBy': user.uid,
          'createdByName': user.displayName ?? user.email,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final strategy =
            businessSnapshot.data()?['costPriceStrategy'] as String? ??
            'weighted_average';
        final runningStock = <String, double>{};
        final runningCost = <String, int>{};
        for (final item in request.items) {
          final productRef = business
              .collection('products')
              .doc(item.productId);
          final inventoryRef = branch
              .collection('inventory')
              .doc(item.productId);
          final product = products[item.productId]!;
          final productData = product.data()!;
          final inventorySnapshot = inventories[item.productId]!;
          final inventoryData = inventorySnapshot.data();
          final before =
              runningStock[item.productId] ??
              (inventoryData?['quantity'] as num?)?.toDouble() ??
              (writableBranchId == 'main'
                  ? (productData['quantity'] as num?)?.toDouble() ?? 0
                  : 0);
          final reserved =
              (inventoryData?['reservedQuantity'] as num?)?.toDouble() ?? 0;
          final after = item.trackStock ? before + item.quantity : before;
          runningStock[item.productId] = after;
          final currentCost =
              runningCost[item.productId] ??
              (inventoryData?['averageUnitCostMinor'] as num?)?.round() ??
              (productData['costPriceMinor'] as num?)?.round() ??
              moneyToMinor(productData['costPrice']);
          final newCost = switch (strategy) {
            'keep' => currentCost,
            'latest' => item.unitCostMinor,
            _ =>
              after <= 0
                  ? item.unitCostMinor
                  : ((before * currentCost +
                                item.quantity * item.unitCostMinor) /
                            after)
                        .round(),
          };
          runningCost[item.productId] = newCost;

          if (item.trackStock) {
            final sellingPriceMinor =
                (productData['sellingPriceMinor'] as num?)?.round() ??
                moneyToMinor(
                  productData['sellingPrice'] ?? productData['price'],
                );
            transaction.set(inventoryRef, <String, Object?>{
              'businessId': request.businessId,
              'branchId': writableBranchId,
              'productId': item.productId,
              'quantity': after,
              'reservedQuantity': reserved,
              'availableQuantity': after - reserved,
              'lowStockThreshold':
                  (inventoryData?['lowStockThreshold'] as num?)?.toDouble() ??
                  (productData['lowStockThreshold'] as num?)?.toDouble() ??
                  0,
              'averageUnitCostMinor': newCost,
              'stockCostValueMinor': (after * newCost).round(),
              'expectedStockRevenueMinor': (after * sellingPriceMinor).round(),
              'potentialProfitRemainingMinor':
                  (after * (sellingPriceMinor - newCost)).round(),
              'realizedGrossProfitMinor':
                  (inventoryData?['realizedGrossProfitMinor'] as num?)
                      ?.round() ??
                  0,
              'updatedAt': FieldValue.serverTimestamp(),
              'updatedBy': user.uid,
              if (!inventorySnapshot.exists)
                'createdAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            // Compatibility aggregate; branch inventory is authoritative.
            transaction.update(productRef, <String, Object?>{
              if (writableBranchId == 'main')
                'quantity': FieldValue.increment(item.quantity),
              'costPriceMinor': newCost,
              'costPrice': minorToMoney(newCost),
              'updatedAt': FieldValue.serverTimestamp(),
            });

            final movement = business.collection('inventory_movements').doc();
            transaction.set(movement, <String, Object?>{
              'id': movement.id,
              'businessId': request.businessId,
              'branchId': writableBranchId,
              'productId': item.productId,
              'productName': item.name,
              'type': 'stock_in',
              'quantityChange': item.quantity,
              'stockBefore': before,
              'stockAfter': after,
              'reason': 'Purchase',
              'note': purchaseNumber,
              'referenceType': 'purchase',
              'referenceId': request.purchaseId,
              'createdBy': user.uid,
              'createdAt': FieldValue.serverTimestamp(),
            });
          } else {
            transaction.update(productRef, <String, Object?>{
              'costPriceMinor': newCost,
              'costPrice': minorToMoney(newCost),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }

        final previousBalance =
            (supplierSnapshot.data()?['balanceMinor'] as num?)?.round() ??
            moneyToMinor(supplierSnapshot.data()?['balance']);
        final updatedBalance = previousBalance + totals.balanceDueMinor;
        transaction.update(supplier, <String, Object?>{
          'balanceMinor': updatedBalance,
          'balance': minorToMoney(updatedBalance),
          'totalPurchasesMinor': FieldValue.increment(totals.totalMinor),
          'purchaseCount': FieldValue.increment(1),
          'lastPurchaseAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (totals.balanceDueMinor > 0) {
          transaction
              .set(supplier.collection('ledger').doc(), <String, Object?>{
                'type': 'purchase_credit',
                'purchaseId': request.purchaseId,
                'purchaseNumber': purchaseNumber,
                'branchId': writableBranchId,
                'debitMinor': totals.balanceDueMinor,
                'creditMinor': 0,
                'balanceBeforeMinor': previousBalance,
                'balanceAfterMinor': updatedBalance,
                'createdBy': user.uid,
                'createdAt': FieldValue.serverTimestamp(),
              });
        }
        transaction.set(activity, <String, Object?>{
          'activityId': activity.id,
          'businessId': request.businessId,
          'branchId': writableBranchId,
          'type': 'purchase',
          'title': 'Purchase completed',
          'subtitle': purchaseNumber,
          'amountMinor': totals.totalMinor,
          'referenceId': request.purchaseId,
          'createdBy': user.uid,
          'timestamp': FieldValue.serverTimestamp(),
        });
        transaction.set(analytics, <String, Object?>{
          'dateKey': today,
          'branchId': writableBranchId,
          'purchaseMinor': FieldValue.increment(totals.totalMinor),
          'purchaseCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return Purchase(
          purchaseId: request.purchaseId,
          businessId: request.businessId,
          branchId: writableBranchId,
          branchNameSnapshot:
              (branchSnapshot.data()?['name'] as String?)?.trim() ??
              request.branchNameSnapshot,
          branchCodeSnapshot:
              (branchSnapshot.data()?['code'] as String?)?.trim() ??
              request.branchCodeSnapshot,
          purchaseNumber: purchaseNumber,
          supplierId: request.supplierId,
          supplierName: request.supplierName,
          items: request.items,
          subtotalMinor: totals.subtotalMinor,
          discountMinor: totals.itemDiscountMinor + totals.orderDiscountMinor,
          taxMinor: totals.taxMinor,
          deliveryMinor: totals.deliveryMinor,
          totalMinor: totals.totalMinor,
          amountPaidMinor: totals.amountPaidMinor,
          balanceDueMinor: totals.balanceDueMinor,
          status: PurchaseStatus.completed,
          paymentStatus: paymentStatus,
          paymentMethod: request.paymentMethod,
        );
      });
    } on PurchaseException {
      rethrow;
    } on FirebaseException catch (error) {
      throw PurchaseException(error.code, message: error.message);
    }
  }

  @override
  Future<void> createPurchaseReturn(
    CreatePurchaseReturnRequest request, {
    String? branchId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const PurchaseException('unauthenticated');
    final writableBranchId = normalizeBranchId(branchId);
    if (writableBranchId == null) {
      throw const PurchaseException(
        'failed-precondition',
        message: 'Switch to the purchase branch before creating a return.',
      );
    }
    if (request.quantities.values.any(
      (quantity) => !quantity.isFinite || quantity <= 0,
    )) {
      throw const PurchaseException(
        'failed-precondition',
        message: 'Return quantities must be greater than zero.',
      );
    }

    final business = _firestore
        .collection('businesses')
        .doc(request.businessId);
    final purchaseRef = business
        .collection('purchases')
        .doc(request.purchaseId);
    final returnRef = business
        .collection('purchase_returns')
        .doc(request.returnId);
    final branchRef = business.collection('branches').doc(writableBranchId);

    await _firestore.runTransaction((transaction) async {
      final purchaseSnapshot = await transaction.get(purchaseRef);
      final existingReturn = await transaction.get(returnRef);
      if (existingReturn.exists) return;
      if (!purchaseSnapshot.exists || purchaseSnapshot.data() == null) {
        throw const PurchaseException('not-found');
      }

      final purchaseData = purchaseSnapshot.data()!;
      final purchaseBranchId = normalizeBranchId(
        purchaseData['branchId'] as String?,
      );
      if (purchaseBranchId == null) {
        throw const PurchaseException(
          'failed-precondition',
          message: 'Legacy branchless purchases cannot be returned.',
        );
      }
      if (purchaseBranchId != writableBranchId) {
        throw const PurchaseException(
          'failed-precondition',
          message: 'Switch to the branch where this purchase was created.',
        );
      }
      final branchSnapshot = await transaction.get(branchRef);
      if (!branchSnapshot.exists ||
          branchSnapshot.data()?['status'] != BranchStatus.active.storedValue) {
        throw const PurchaseException(
          'failed-precondition',
          message: 'This branch is inactive and cannot process returns.',
        );
      }

      final purchase = Purchase.fromFirestore(purchaseSnapshot);
      if (purchase.status != PurchaseStatus.completed &&
          purchase.status != PurchaseStatus.returned) {
        throw const PurchaseException(
          'failed-precondition',
          message: 'Only completed purchases can be returned.',
        );
      }

      final selected = <PurchaseItem>[];
      final returned = Map<String, dynamic>.from(
        purchaseData['returnedQuantities'] as Map? ?? const {},
      );
      for (final entry in request.quantities.entries) {
        final item = purchase.items
            .where((item) => item.purchaseItemId == entry.key)
            .firstOrNull;
        if (item == null ||
            entry.value + ((returned[entry.key] as num?)?.toDouble() ?? 0) >
                item.quantity) {
          throw const PurchaseException(
            'failed-precondition',
            message: 'Return quantity exceeds the original purchase.',
          );
        }
        selected.add(
          PurchaseItem(
            purchaseItemId: item.purchaseItemId,
            productId: item.productId,
            name: item.name,
            quantity: entry.value,
            unitCostMinor: item.unitCostMinor,
            trackStock: item.trackStock,
            sku: item.sku,
            unit: item.unit,
            discountType: item.discountType,
            discountValue: item.discountValue,
          ),
        );
      }
      if (selected.isEmpty) {
        throw const PurchaseException(
          'failed-precondition',
          message: 'Select at least one item to return.',
        );
      }

      final productSnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      final inventorySnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final item in selected.where((item) => item.trackStock)) {
        if (productSnapshots.containsKey(item.productId)) continue;
        productSnapshots[item.productId] = await transaction.get(
          business.collection('products').doc(item.productId),
        );
        inventorySnapshots[item.productId] = await transaction.get(
          branchRef.collection('inventory').doc(item.productId),
        );
      }

      final supplierRef = business
          .collection('suppliers')
          .doc(purchase.supplierId);
      final supplierSnapshot = await transaction.get(supplierRef);
      for (final item in selected.where((item) => item.trackStock)) {
        final productSnapshot = productSnapshots[item.productId];
        final inventorySnapshot = inventorySnapshots[item.productId];
        if (productSnapshot == null || !productSnapshot.exists) {
          throw PurchaseException(
            'failed-precondition',
            message: '${item.name} is no longer available.',
          );
        }
        final quantity =
            (inventorySnapshot?.data()?['quantity'] as num?)?.toDouble() ??
            (writableBranchId == 'main'
                ? (productSnapshot.data()?['quantity'] as num?)?.toDouble() ?? 0
                : 0);
        if (quantity + 1e-9 < item.quantity) {
          throw PurchaseException(
            'failed-precondition',
            message:
                'Insufficient ${branchSnapshot.data()?['name'] ?? 'branch'} stock to return ${item.name}.',
          );
        }
      }

      final returnedTotals = PurchaseCalculator.calculate(items: selected);
      final previousBalance =
          (supplierSnapshot.data()?['balanceMinor'] as num?)?.round() ?? 0;
      // Only the unpaid share of returned goods reduces supplier payable.
      final returnCredit = purchase.totalMinor == 0
          ? 0
          : (purchase.balanceDueMinor *
                    returnedTotals.totalMinor /
                    purchase.totalMinor)
                .round();
      final reversal = previousBalance < returnCredit
          ? previousBalance
          : returnCredit;

      for (final item in selected.where((item) => item.trackStock)) {
        final productRef = business.collection('products').doc(item.productId);
        final inventoryRef = branchRef
            .collection('inventory')
            .doc(item.productId);
        final productData = productSnapshots[item.productId]!.data()!;
        final inventoryData = inventorySnapshots[item.productId]?.data();
        final before =
            (inventoryData?['quantity'] as num?)?.toDouble() ??
            (writableBranchId == 'main'
                ? (productData['quantity'] as num?)?.toDouble() ?? 0
                : 0);
        final reserved =
            (inventoryData?['reservedQuantity'] as num?)?.toDouble() ?? 0;
        final after = before - item.quantity;
        final averageCost =
            (inventoryData?['averageUnitCostMinor'] as num?)?.round() ??
            (productData['costPriceMinor'] as num?)?.round() ??
            moneyToMinor(productData['costPrice']);
        final sellingPrice =
            (productData['sellingPriceMinor'] as num?)?.round() ??
            moneyToMinor(productData['sellingPrice'] ?? productData['price']);

        transaction.set(inventoryRef, <String, Object?>{
          'businessId': request.businessId,
          'branchId': writableBranchId,
          'productId': item.productId,
          'quantity': after,
          'reservedQuantity': reserved,
          'availableQuantity': (after - reserved).clamp(0, double.infinity),
          'averageUnitCostMinor': averageCost,
          'stockCostValueMinor': (after * averageCost).round(),
          'expectedStockRevenueMinor': (after * sellingPrice).round(),
          'potentialProfitRemainingMinor':
              (after * (sellingPrice - averageCost)).round(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': user.uid,
          if (!(inventorySnapshots[item.productId]?.exists ?? false))
            'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        // Legacy aggregate mirror only; branch inventory is authoritative.
        transaction.update(productRef, <String, Object?>{
          'quantity': FieldValue.increment(-item.quantity),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final movement = business.collection('inventory_movements').doc();
        transaction.set(movement, <String, Object?>{
          'id': movement.id,
          'businessId': request.businessId,
          'branchId': writableBranchId,
          'productId': item.productId,
          'productName': item.name,
          'type': 'returned',
          'quantityChange': -item.quantity,
          'stockBefore': before,
          'stockAfter': after,
          'reason': 'Purchase return',
          'note': request.note,
          'referenceType': 'purchase_return',
          'referenceId': request.returnId,
          'createdBy': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      for (final item in selected) {
        returned[item.purchaseItemId] =
            ((returned[item.purchaseItemId] as num?)?.toDouble() ?? 0) +
            item.quantity;
      }
      final fullyReturned = purchase.items.every(
        (item) =>
            ((returned[item.purchaseItemId] as num?)?.toDouble() ?? 0) >=
            item.quantity,
      );
      transaction.update(purchaseRef, <String, Object?>{
        'returnedQuantities': returned,
        'status': fullyReturned
            ? PurchaseStatus.returned.name
            : PurchaseStatus.completed.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(returnRef, <String, Object?>{
        'returnId': request.returnId,
        'businessId': request.businessId,
        'branchId': writableBranchId,
        'purchaseId': request.purchaseId,
        'supplierId': purchase.supplierId,
        'items': selected.map((item) => item.toMap()).toList(),
        'totalMinor': returnedTotals.totalMinor,
        'note': request.note,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (supplierSnapshot.exists && reversal > 0) {
        transaction.update(supplierRef, <String, Object?>{
          'balanceMinor': previousBalance - reversal,
          'balance': minorToMoney(previousBalance - reversal),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction
            .set(supplierRef.collection('ledger').doc(), <String, Object?>{
              'type': 'purchase_return',
              'purchaseId': request.purchaseId,
              'returnId': request.returnId,
              'branchId': writableBranchId,
              'debitMinor': 0,
              'creditMinor': reversal,
              'balanceBeforeMinor': previousBalance,
              'balanceAfterMinor': previousBalance - reversal,
              'createdBy': user.uid,
              'createdAt': FieldValue.serverTimestamp(),
            });
      }
    });
  }

  @override
  Future<void> voidPurchase(
    String businessId,
    String purchaseId, {
    required String reason,
    String? branchId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const PurchaseException('unauthenticated');
    final writableBranchId = normalizeBranchId(branchId);
    if (writableBranchId == null) {
      throw const PurchaseException(
        'failed-precondition',
        message: 'Switch to the purchase branch before voiding it.',
      );
    }
    final trimmed = reason.trim();
    if (trimmed.length < 2) {
      throw const PurchaseException(
        'failed-precondition',
        message: 'Enter a void reason.',
      );
    }

    final businessRef = _firestore.collection('businesses').doc(businessId);
    final purchaseRef = businessRef.collection('purchases').doc(purchaseId);
    final branchRef = businessRef.collection('branches').doc(writableBranchId);
    await _firestore.runTransaction((transaction) async {
      final purchaseSnapshot = await transaction.get(purchaseRef);
      if (!purchaseSnapshot.exists || purchaseSnapshot.data() == null) {
        throw const PurchaseException('not-found');
      }
      final purchaseData = purchaseSnapshot.data()!;
      final originalBranchId = normalizeBranchId(
        purchaseData['branchId'] as String?,
      );
      if (originalBranchId == null) {
        throw const PurchaseException(
          'failed-precondition',
          message: 'Legacy branchless purchases cannot be voided.',
        );
      }
      if (originalBranchId != writableBranchId) {
        throw const PurchaseException(
          'failed-precondition',
          message: 'Switch to the branch where this purchase was created.',
        );
      }
      final branchSnapshot = await transaction.get(branchRef);
      if (!branchSnapshot.exists ||
          branchSnapshot.data()?['status'] != BranchStatus.active.storedValue) {
        throw const PurchaseException(
          'failed-precondition',
          message: 'This branch is inactive and cannot void purchases.',
        );
      }

      final purchase = Purchase.fromFirestore(purchaseSnapshot);
      if (purchase.status == PurchaseStatus.voided) {
        throw const PurchaseException(
          'already-voided',
          message: 'This purchase is already voided.',
        );
      }
      if (purchase.status == PurchaseStatus.returned ||
          (purchaseData['returnedQuantities'] as Map?)?.isNotEmpty == true) {
        throw const PurchaseException(
          'failed-precondition',
          message:
              'A purchase with returns cannot be voided. Review the return history instead.',
        );
      }
      if (purchase.amountPaidMinor > 0) {
        throw const PurchaseException(
          'failed-precondition',
          message:
              'A paid purchase cannot be voided until its payment is reversed.',
        );
      }

      final productSnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      final inventorySnapshots =
          <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final item in purchase.items.where((item) => item.trackStock)) {
        if (productSnapshots.containsKey(item.productId)) continue;
        productSnapshots[item.productId] = await transaction.get(
          businessRef.collection('products').doc(item.productId),
        );
        inventorySnapshots[item.productId] = await transaction.get(
          branchRef.collection('inventory').doc(item.productId),
        );
      }
      for (final item in purchase.items.where((item) => item.trackStock)) {
        final product = productSnapshots[item.productId];
        final inventory = inventorySnapshots[item.productId];
        final available =
            (inventory?.data()?['quantity'] as num?)?.toDouble() ??
            (writableBranchId == 'main'
                ? (product?.data()?['quantity'] as num?)?.toDouble() ?? 0
                : 0);
        if (product == null ||
            !product.exists ||
            available + 1e-9 < item.quantity) {
          throw PurchaseException(
            'failed-precondition',
            message: 'Not enough branch stock remains to void ${item.name}.',
          );
        }
      }

      for (final item in purchase.items.where((item) => item.trackStock)) {
        final productRef = businessRef
            .collection('products')
            .doc(item.productId);
        final inventoryRef = branchRef
            .collection('inventory')
            .doc(item.productId);
        final productData = productSnapshots[item.productId]!.data()!;
        final inventoryData = inventorySnapshots[item.productId]?.data();
        final before =
            (inventoryData?['quantity'] as num?)?.toDouble() ??
            (writableBranchId == 'main'
                ? (productData['quantity'] as num?)?.toDouble() ?? 0
                : 0);
        final reserved =
            (inventoryData?['reservedQuantity'] as num?)?.toDouble() ?? 0;
        final after = before - item.quantity;
        final averageCost =
            (inventoryData?['averageUnitCostMinor'] as num?)?.round() ??
            (productData['costPriceMinor'] as num?)?.round() ??
            moneyToMinor(productData['costPrice']);
        final sellingPrice =
            (productData['sellingPriceMinor'] as num?)?.round() ??
            moneyToMinor(productData['sellingPrice'] ?? productData['price']);

        transaction.set(inventoryRef, <String, Object?>{
          'businessId': businessId,
          'branchId': writableBranchId,
          'productId': item.productId,
          'quantity': after,
          'reservedQuantity': reserved,
          'availableQuantity': (after - reserved).clamp(0, double.infinity),
          'averageUnitCostMinor': averageCost,
          'stockCostValueMinor': (after * averageCost).round(),
          'expectedStockRevenueMinor': (after * sellingPrice).round(),
          'potentialProfitRemainingMinor':
              (after * (sellingPrice - averageCost)).round(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': user.uid,
        }, SetOptions(merge: true));
        transaction.update(productRef, <String, Object?>{
          'quantity': FieldValue.increment(-item.quantity),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        final movement = businessRef.collection('inventory_movements').doc();
        transaction.set(movement, <String, Object?>{
          'id': movement.id,
          'businessId': businessId,
          'branchId': writableBranchId,
          'productId': item.productId,
          'productName': item.name,
          'type': 'purchase_void',
          'quantityChange': -item.quantity,
          'stockBefore': before,
          'stockAfter': after,
          'reason': 'Purchase void',
          'note': trimmed,
          'referenceType': 'purchase_void',
          'referenceId': purchaseId,
          'createdBy': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      final supplierRef = businessRef
          .collection('suppliers')
          .doc(purchase.supplierId);
      final supplierSnapshot = await transaction.get(supplierRef);
      if (supplierSnapshot.exists && purchase.balanceDueMinor > 0) {
        final previousBalance =
            (supplierSnapshot.data()?['balanceMinor'] as num?)?.round() ?? 0;
        final reversal = previousBalance < purchase.balanceDueMinor
            ? previousBalance
            : purchase.balanceDueMinor;
        transaction.update(supplierRef, <String, Object?>{
          'balanceMinor': previousBalance - reversal,
          'balance': minorToMoney(previousBalance - reversal),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (reversal > 0) {
          transaction
              .set(supplierRef.collection('ledger').doc(), <String, Object?>{
                'type': 'purchase_void',
                'purchaseId': purchaseId,
                'branchId': writableBranchId,
                'debitMinor': 0,
                'creditMinor': reversal,
                'balanceBeforeMinor': previousBalance,
                'balanceAfterMinor': previousBalance - reversal,
                'createdBy': user.uid,
                'createdAt': FieldValue.serverTimestamp(),
              });
        }
      }

      transaction.update(purchaseRef, <String, Object?>{
        'status': PurchaseStatus.voided.name,
        'voidReason': trimmed,
        'voidedBy': user.uid,
        'voidedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final activityRef = businessRef.collection('activity').doc();
      transaction.set(activityRef, <String, Object?>{
        'activityId': activityRef.id,
        'businessId': businessId,
        'branchId': writableBranchId,
        'type': 'purchaseVoid',
        'title': 'Purchase voided',
        'subtitle': purchase.purchaseNumber,
        'referenceId': purchaseId,
        'createdBy': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
  }
}
