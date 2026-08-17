import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../../core/sync/offline_mutation_queue.dart';
import '../../inventory/domain/branch_inventory.dart';
import '../../inventory/domain/expiry_status_calculator.dart';
import '../../inventory/domain/product_profit_calculator.dart';
import '../../inventory/domain/stock_quantity_rules.dart';
import '../../branches/domain/business_branch.dart';
import '../domain/inventory_movement.dart';
import '../domain/product.dart';
import '../../notifications/application/stock_alert_service.dart';
import 'products_repository.dart';

class FirestoreProductsRepository implements ProductsRepository {
  FirestoreProductsRepository({
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

  CollectionReference<Map<String, dynamic>> _products(String businessId) =>
      _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('products');

  CollectionReference<Map<String, dynamic>> _branchInventory(
    String businessId,
    String branchId,
  ) => _firestore
      .collection('businesses')
      .doc(businessId)
      .collection('branches')
      .doc(branchId)
      .collection('inventory');

  Query<Map<String, dynamic>> _allBranchInventory(String businessId) =>
      _firestore
          .collectionGroup('inventory')
          .where('businessId', isEqualTo: businessId);

  CollectionReference<Map<String, dynamic>> _movements(String businessId) =>
      _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('inventory_movements');

  CollectionReference<Map<String, dynamic>> _activity(String businessId) =>
      _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('activity');

  CollectionReference<Map<String, dynamic>> _batches(String businessId) =>
      _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('inventory_batches');

  @override
  Stream<List<Product>> watchProducts(String businessId, {String? branchId}) {
    if (businessId.trim().isEmpty) {
      return Stream<List<Product>>.value(const <Product>[]);
    }

    final productsStream = _products(businessId).orderBy('name').snapshots();
    final normalizedBranchId = normalizeBranchId(branchId);
    if (normalizedBranchId == null) {
      return _watchProductsAcrossBranches(businessId, productsStream);
    }
    final inventoryStream = _branchInventory(
      businessId,
      normalizedBranchId,
    ).snapshots();

    return _combineLatest(productsStream, inventoryStream, (
      productSnapshot,
      inventorySnapshot,
    ) {
      final inventoryByProduct = <String, List<BranchInventory>>{};
      for (final document in inventorySnapshot.docs) {
        final inventory = BranchInventory.fromFirestore(document);
        if (inventory.businessId != businessId) continue;
        inventoryByProduct
            .putIfAbsent(inventory.productId, () => <BranchInventory>[])
            .add(inventory);
      }

      return productSnapshot.docs
          .map((document) {
            final product = Product.fromFirestore(document);
            final rows =
                inventoryByProduct[product.id] ?? const <BranchInventory>[];
            BranchInventory? inventory;
            for (final row in rows) {
              if (row.branchId == normalizedBranchId) {
                inventory = row;
                break;
              }
            }
            if (inventory != null) {
              return _applyInventory(product, inventory);
            }

            // Legacy stock belongs to Main Branch until the migration runs.
            if (normalizedBranchId == 'main') return product;
            return _zeroStock(product);
          })
          .toList(growable: false);
    });
  }

  Stream<List<Product>> _watchProductsAcrossBranches(
    String businessId,
    Stream<QuerySnapshot<Map<String, dynamic>>> productsStream,
  ) {
    late StreamController<List<Product>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
    productsSubscription;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
    branchesSubscription;
    final inventorySubscriptions =
        <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
    final inventorySnapshots = <String, QuerySnapshot<Map<String, dynamic>>>{};
    QuerySnapshot<Map<String, dynamic>>? latestProducts;
    Set<String> branchIds = const <String>{};

    void emit() {
      final productSnapshot = latestProducts;
      if (productSnapshot == null || controller.isClosed) return;
      if (!branchIds.every(inventorySnapshots.containsKey)) return;
      final inventoryByProduct = <String, List<BranchInventory>>{};
      for (final snapshot in inventorySnapshots.values) {
        for (final document in snapshot.docs) {
          final inventory = BranchInventory.fromFirestore(document);
          if (inventory.businessId != businessId) continue;
          inventoryByProduct
              .putIfAbsent(inventory.productId, () => <BranchInventory>[])
              .add(inventory);
        }
      }
      controller.add(
        productSnapshot.docs
            .map((document) {
              final product = Product.fromFirestore(document);
              final rows =
                  inventoryByProduct[product.id] ?? const <BranchInventory>[];
              if (rows.isEmpty) return product;
              return _applyInventory(
                product,
                BranchInventory.aggregate(
                  businessId: businessId,
                  productId: product.id,
                  records: rows,
                  fallbackUnitCostMinor: product.costPriceMinor,
                  fallbackLowStockThreshold: product.lowStockThreshold,
                ),
              );
            })
            .toList(growable: false),
      );
    }

    Future<void> replaceInventorySubscriptions(Set<String> nextIds) async {
      for (final id
          in inventorySubscriptions.keys
              .where((id) => !nextIds.contains(id))
              .toList()) {
        await inventorySubscriptions.remove(id)?.cancel();
        inventorySnapshots.remove(id);
      }
      branchIds = nextIds;
      for (final id in nextIds) {
        if (inventorySubscriptions.containsKey(id)) continue;
        inventorySubscriptions[id] = _branchInventory(businessId, id)
            .snapshots()
            .listen((snapshot) {
              inventorySnapshots[id] = snapshot;
              emit();
            }, onError: controller.addError);
      }
      emit();
    }

    controller = StreamController<List<Product>>(
      onListen: () {
        productsSubscription = productsStream.listen((snapshot) {
          latestProducts = snapshot;
          emit();
        }, onError: controller.addError);
        branchesSubscription = _firestore
            .collection('businesses')
            .doc(businessId)
            .collection('branches')
            .snapshots()
            .listen(
              (snapshot) => replaceInventorySubscriptions(
                snapshot.docs.map((document) => document.id).toSet(),
              ),
              onError: controller.addError,
            );
      },
      onCancel: () async {
        await productsSubscription?.cancel();
        await branchesSubscription?.cancel();
        for (final subscription in inventorySubscriptions.values) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<Product?> getProduct(
    String businessId,
    String productId, {
    String? branchId,
  }) async {
    if (businessId.trim().isEmpty || productId.trim().isEmpty) return null;
    final snapshot = await _products(businessId).doc(productId).get();
    if (!snapshot.exists || snapshot.data() == null) return null;
    final product = Product.fromFirestore(snapshot);
    final normalizedBranchId = normalizeBranchId(branchId);

    if (normalizedBranchId != null) {
      final inventorySnapshot = await _branchInventory(
        businessId,
        normalizedBranchId,
      ).doc(productId).get();
      if (inventorySnapshot.exists && inventorySnapshot.data() != null) {
        return _applyInventory(
          product,
          BranchInventory.fromFirestore(inventorySnapshot),
        );
      }
      return normalizedBranchId == 'main' ? product : _zeroStock(product);
    }

    final branches = await _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('branches')
        .get();
    final inventoryDocuments = await Future.wait(
      branches.docs.map(
        (branch) =>
            _branchInventory(businessId, branch.id).doc(productId).get(),
      ),
    );
    final inventoryRecords = inventoryDocuments
        .where((document) => document.exists && document.data() != null)
        .map(BranchInventory.fromFirestore)
        .toList(growable: false);
    if (inventoryRecords.isEmpty) return product;
    final aggregate = BranchInventory.aggregate(
      businessId: businessId,
      productId: productId,
      records: inventoryRecords,
      fallbackUnitCostMinor: product.costPriceMinor,
      fallbackLowStockThreshold: product.lowStockThreshold,
    );
    return _applyInventory(product, aggregate);
  }

  @override
  Future<String> createProduct(
    String businessId,
    ProductDraft draft, {
    String? branchId,
    bool queueWhenOffline = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const ProductException('unauthenticated');
    _validateDraft(draft, requireOpeningStock: true);
    final writableBranchId = _requireBranchId(branchId);
    final productId = const Uuid().v4();
    final body = <String, dynamic>{
      'businessId': businessId,
      'branchId': writableBranchId,
      'productId': productId,
      'name': draft.name,
      'sku': draft.sku,
      'barcode': draft.barcode,
      'description': draft.description,
      'categoryName': draft.categoryName,
      'sellingPriceMinor': draft.sellingPriceMinor,
      'costPriceMinor': draft.costPriceMinor,
      'trackStock': draft.trackStock,
      'quantity': draft.trackStock ? draft.quantity : 0,
      'lowStockThreshold': draft.lowStockThreshold,
      'unit': draft.unit,
      'status': draft.status.name,
      'tracksExpiry': draft.tracksExpiry,
      'defaultExpiryReminderDays': draft.defaultExpiryReminderDays,
      'initialStockExpiryDate': encodeProductInitialExpiryDate(
        draft.initialStockExpiryDate,
      ),
      'initialStockExpiryDateKnown':
          draft.initialStockExpiryDateKnown &&
          draft.initialStockExpiryDate != null,
      'imageUrl': draft.imageUrl,
      'imageCid': draft.imageCid,
    };
    if (queueWhenOffline) {
      await _offlineQueue.enqueue(
        id: 'product_$productId',
        type: OfflineMutationType.productCreate,
        businessId: businessId,
        payload: body,
      );
      return productId;
    }
    try {
      final response = await _apiClient.postJson(
        '/api/inventory/products/create',
        body: body,
        timeout: const Duration(seconds: 20),
      );
      await _ensureOpeningQuantity(
        businessId: businessId,
        productId: productId,
        draft: draft,
        branchId: writableBranchId,
      );
      return response['productId'] as String? ?? productId;
    } on ApiException catch (error) {
      // Inventory create route may not be deployed yet on Vercel (404).
      // Fall back to the same Firestore write path the API uses.
      if (error.statusCode == 404 || error.statusCode == 405) {
        await _createProductInFirestore(
          businessId: businessId,
          productId: productId,
          draft: draft,
          branchId: writableBranchId,
          uid: user.uid,
          createdByName: user.displayName ?? user.email ?? 'Team member',
        );
        return productId;
      }
      if (error.statusCode == null) {
        await _offlineQueue.enqueue(
          id: 'product_$productId',
          type: OfflineMutationType.productCreate,
          businessId: businessId,
          payload: body,
        );
        return productId;
      }
      throw ProductException(
        error.code ?? 'unavailable',
        message: error.message,
      );
    }
  }

  Future<void> _ensureOpeningQuantity({
    required String businessId,
    required String productId,
    required ProductDraft draft,
    required String branchId,
  }) async {
    final expected = draft.trackStock ? draft.quantity : 0.0;
    if (expected <= 0) return;
    final inventory = await _branchInventory(
      businessId,
      branchId,
    ).doc(productId).get();
    final current = (inventory.data()?['quantity'] as num?)?.toDouble() ?? 0;
    final missing = expected - current;
    if (missing <= 0) return;
    await adjustStock(
      businessId,
      StockAdjustmentRequest(
        productId: productId,
        type: InventoryAdjustmentType.openingBalance,
        quantity: missing,
        reason: 'Opening stock',
        note: 'Opening quantity completed after product creation',
      ),
      branchId: branchId,
    );
  }

  // Kept isolated while the backend opening-stock response is verified.
  // ignore: unused_element
  Future<void> _repairMissingOpeningInventory({
    required String businessId,
    required String productId,
    required ProductDraft draft,
    required String branchId,
    required String uid,
    required String createdByName,
  }) async {
    final expectedQuantity = draft.trackStock ? draft.quantity : 0.0;
    if (expectedQuantity <= 0) return;
    final inventoryRef = _branchInventory(businessId, branchId).doc(productId);
    final existing = await inventoryRef.get();
    final existingQuantity =
        (existing.data()?['quantity'] as num?)?.toDouble() ?? 0;
    if (existing.exists && existingQuantity > 0) return;

    final productRef = _products(businessId).doc(productId);
    final batchRef = _batches(
      businessId,
    ).doc('${branchId}_${productId}_initial');
    final movementRef = _movements(businessId).doc();
    final activityRef = _activity(businessId).doc();
    await _firestore.runTransaction((transaction) async {
      final productSnapshot = await transaction.get(productRef);
      final inventorySnapshot = await transaction.get(inventoryRef);
      final batchSnapshot = await transaction.get(batchRef);
      if (!productSnapshot.exists) {
        throw const ProductException('not-found');
      }
      final currentQuantity =
          (inventorySnapshot.data()?['quantity'] as num?)?.toDouble() ?? 0;
      if (inventorySnapshot.exists && currentQuantity > 0) return;

      final expiryKnown =
          draft.tracksExpiry &&
          draft.initialStockExpiryDateKnown &&
          draft.initialStockExpiryDate != null;
      final expiryDate = expiryKnown ? draft.initialStockExpiryDate : null;
      final expiryStatus = !draft.tracksExpiry
          ? ProductExpiryStatus.notTracked
          : expiryDate == null
          ? ProductExpiryStatus.safe
          : ExpiryStatusCalculator.statusForDate(
              expiryDate: expiryDate,
              now: DateTime.now(),
              businessTimezone: 'Africa/Freetown',
              reminderThresholdDays: draft.defaultExpiryReminderDays,
            );
      final profit = ProductProfitCalculator.calculate(
        currentStock: expectedQuantity,
        currentUnitCostMinor: draft.costPriceMinor,
        currentSellingPriceMinor: draft.sellingPriceMinor,
      );
      transaction.set(inventoryRef, <String, Object?>{
        'businessId': businessId,
        'branchId': branchId,
        'productId': productId,
        'quantity': expectedQuantity,
        'reservedQuantity': 0,
        'availableQuantity': expectedQuantity,
        'lowStockThreshold': draft.lowStockThreshold,
        'averageUnitCostMinor': draft.costPriceMinor,
        'stockCostValueMinor': profit.stockCostValueMinor,
        'expectedStockRevenueMinor': profit.expectedStockRevenueMinor,
        'potentialProfitRemainingMinor': profit.potentialProfitRemainingMinor,
        'realizedGrossProfitMinor': 0,
        'expiryStatus': expiryStatus.storedValue,
        'nextExpiryDate': expiryDate == null
            ? null
            : Timestamp.fromDate(expiryDate),
        'nextExpiryBatchId': expiryDate == null ? null : batchRef.id,
        'nextExpiryBatchQuantity': expiryDate == null ? 0 : expectedQuantity,
        'unknownExpiryQuantity': draft.tracksExpiry && !expiryKnown
            ? expectedQuantity
            : 0,
        'expiringQuantity':
            expiryStatus == ProductExpiryStatus.expiringSoon ||
                expiryStatus == ProductExpiryStatus.expiresToday
            ? expectedQuantity
            : 0,
        'expiredQuantity': expiryStatus == ProductExpiryStatus.expired
            ? expectedQuantity
            : 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      }, SetOptions(merge: true));
      if (!batchSnapshot.exists) {
        transaction.set(batchRef, <String, Object?>{
          'businessId': businessId,
          'branchId': branchId,
          'productId': productId,
          'productName': draft.name,
          'sku': draft.sku,
          'sourceType': 'initial_stock',
          'sourceId': productId,
          'quantityReceived': expectedQuantity,
          'quantityRemaining': expectedQuantity,
          'unitCostMinor': draft.costPriceMinor,
          'sellingPriceAtReceiptMinor': draft.sellingPriceMinor,
          'expiryDate': expiryDate == null
              ? null
              : Timestamp.fromDate(expiryDate),
          'expiryDateKnown': expiryKnown,
          'receivedAt': FieldValue.serverTimestamp(),
          'status': 'active',
          'createdBy': uid,
          'createdByName': createdByName,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.set(movementRef, <String, Object?>{
        'id': movementRef.id,
        'businessId': businessId,
        'branchId': branchId,
        'productId': productId,
        'productName': draft.name,
        'batchId': batchRef.id,
        'type': InventoryAdjustmentType.openingBalance.storedValue,
        'quantityChange': expectedQuantity,
        'stockBefore': 0,
        'stockAfter': expectedQuantity,
        'reason': 'Opening stock',
        'referenceType': 'initial_stock_repair',
        'referenceId': batchRef.id,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(activityRef, <String, Object?>{
        'activityId': activityRef.id,
        'businessId': businessId,
        'branchId': branchId,
        'type': 'stockAdjustment',
        'title': 'Opening stock recorded',
        'subtitle': draft.name,
        'referenceId': productId,
        'createdBy': uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _createProductInFirestore({
    required String businessId,
    required String productId,
    required ProductDraft draft,
    required String uid,
    required String createdByName,
    required String branchId,
  }) async {
    final quantity = draft.trackStock ? draft.quantity : 0.0;
    final expiryKnown =
        draft.tracksExpiry &&
        quantity > 0 &&
        draft.initialStockExpiryDateKnown &&
        draft.initialStockExpiryDate != null;
    final expiryDate = expiryKnown ? draft.initialStockExpiryDate : null;
    final productRef = _products(businessId).doc(productId);
    final inventoryRef = _branchInventory(businessId, branchId).doc(productId);
    final batchRef = _batches(
      businessId,
    ).doc('${branchId}_${productId}_initial');
    final movementRef = _movements(businessId).doc();
    final activityRef = _activity(businessId).doc();
    final businessRef = _firestore.collection('businesses').doc(businessId);
    final branchRef = businessRef.collection('branches').doc(branchId);

    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(productRef);
      final branchSnapshot = await transaction.get(branchRef);
      if (!branchSnapshot.exists ||
          branchSnapshot.data()?['status'] != BranchStatus.active.storedValue) {
        throw const ProductException(
          'failed-precondition',
          message: 'Select an active branch before creating stock.',
        );
      }
      if (existing.exists) {
        throw const ProductException(
          'failed-precondition',
          message: 'This product already exists. Please try again.',
        );
      }
      final businessSnap = await transaction.get(businessRef);
      final timezone =
          (businessSnap.data()?['timezone'] as String?) ?? 'Africa/Freetown';
      final profit = ProductProfitCalculator.calculate(
        currentStock: quantity,
        currentUnitCostMinor: draft.costPriceMinor,
        currentSellingPriceMinor: draft.sellingPriceMinor,
      );
      final expiryStatus = !draft.tracksExpiry
          ? ProductExpiryStatus.notTracked
          : expiryDate == null
          ? ProductExpiryStatus.safe
          : ExpiryStatusCalculator.statusForDate(
              expiryDate: expiryDate,
              now: DateTime.now().toUtc(),
              businessTimezone: timezone,
              reminderThresholdDays: draft.defaultExpiryReminderDays,
            );

      transaction.set(productRef, <String, Object?>{
        'productId': productId,
        'businessId': businessId,
        'name': draft.name.trim(),
        'sku': draft.sku?.trim().isEmpty == true ? null : draft.sku?.trim(),
        'barcode': draft.barcode?.trim().isEmpty == true
            ? null
            : draft.barcode?.trim(),
        'description': draft.description?.trim().isEmpty == true
            ? null
            : draft.description?.trim(),
        'categoryId': null,
        'categoryName': draft.categoryName,
        'sellingPriceMinor': draft.sellingPriceMinor,
        'costPriceMinor': draft.costPriceMinor,
        'sellingPrice': draft.sellingPriceMinor / 100,
        'price': draft.sellingPriceMinor / 100,
        'costPrice': draft.costPriceMinor / 100,
        'quantity': quantity,
        'lowStockThreshold': draft.trackStock ? draft.lowStockThreshold : 0,
        'trackStock': draft.trackStock,
        'unit': draft.unit,
        'imageUrl': draft.imageUrl,
        'imageCid': draft.imageCid,
        'status': draft.status.name,
        'tracksExpiry': draft.tracksExpiry,
        'defaultExpiryReminderDays': draft.defaultExpiryReminderDays,
        'nextExpiryDate': expiryDate == null
            ? null
            : Timestamp.fromDate(expiryDate),
        'nextExpiryBatchId': expiryDate == null ? null : batchRef.id,
        'nextExpiryBatchQuantity': expiryDate == null ? 0 : quantity,
        'expiringQuantity':
            expiryStatus == ProductExpiryStatus.expiringSoon ||
                expiryStatus == ProductExpiryStatus.expiresToday
            ? quantity
            : 0,
        'expiredQuantity': expiryStatus == ProductExpiryStatus.expired
            ? quantity
            : 0,
        'unknownExpiryQuantity':
            draft.tracksExpiry && quantity > 0 && !expiryKnown ? quantity : 0,
        'expiryStatus': expiryStatus.storedValue,
        'unitPotentialProfitMinor': profit.unitPotentialProfitMinor,
        'stockCostValueMinor': profit.stockCostValueMinor,
        'expectedStockRevenueMinor': profit.expectedStockRevenueMinor,
        'potentialProfitRemainingMinor': profit.potentialProfitRemainingMinor,
        'realizedGrossProfitMinor': 0,
        'profitIsEstimated': false,
        'createdBy': uid,
        'createdByName': createdByName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.set(inventoryRef, <String, Object?>{
        'businessId': businessId,
        'branchId': branchId,
        'productId': productId,
        'quantity': quantity,
        'reservedQuantity': 0,
        'availableQuantity': quantity,
        'lowStockThreshold': draft.trackStock ? draft.lowStockThreshold : 0,
        'averageUnitCostMinor': draft.costPriceMinor,
        'stockCostValueMinor': profit.stockCostValueMinor,
        'expectedStockRevenueMinor': profit.expectedStockRevenueMinor,
        'potentialProfitRemainingMinor': profit.potentialProfitRemainingMinor,
        'realizedGrossProfitMinor': 0,
        'nextExpiryDate': expiryDate == null
            ? null
            : Timestamp.fromDate(expiryDate),
        'nextExpiryBatchId': expiryDate == null ? null : batchRef.id,
        'nextExpiryBatchQuantity': expiryDate == null ? 0 : quantity,
        'expiringQuantity':
            expiryStatus == ProductExpiryStatus.expiringSoon ||
                expiryStatus == ProductExpiryStatus.expiresToday
            ? quantity
            : 0,
        'expiredQuantity': expiryStatus == ProductExpiryStatus.expired
            ? quantity
            : 0,
        'unknownExpiryQuantity':
            draft.tracksExpiry && quantity > 0 && !expiryKnown ? quantity : 0,
        'expiryStatus': expiryStatus.storedValue,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      });

      if (draft.trackStock && quantity > 0) {
        transaction.set(batchRef, <String, Object?>{
          'businessId': businessId,
          'branchId': branchId,
          'productId': productId,
          'productName': draft.name.trim(),
          'sku': draft.sku?.trim().isEmpty == true ? null : draft.sku?.trim(),
          'sourceType': 'initial_stock',
          'sourceId': productId,
          'sourceNumber': null,
          'quantityReceived': quantity,
          'quantityRemaining': quantity,
          'unitCostMinor': draft.costPriceMinor,
          'sellingPriceAtReceiptMinor': draft.sellingPriceMinor,
          'expiryDate': expiryDate == null
              ? null
              : Timestamp.fromDate(expiryDate),
          'expiryDateKnown': expiryKnown,
          'receivedAt': FieldValue.serverTimestamp(),
          'status': expiryStatus == ProductExpiryStatus.expired
              ? 'expired'
              : 'active',
          'createdBy': uid,
          'createdByName': createdByName,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'depletedAt': null,
        });
        transaction.set(movementRef, <String, Object?>{
          'id': movementRef.id,
          'businessId': businessId,
          'branchId': branchId,
          'productId': productId,
          'productName': draft.name.trim(),
          'batchId': batchRef.id,
          'type': 'opening_balance',
          'quantityChange': quantity,
          'stockBefore': 0,
          'stockAfter': quantity,
          'reason': 'Opening stock',
          'note': null,
          'referenceType': 'initial_stock',
          'referenceId': batchRef.id,
          'createdBy': uid,
          'createdByName': createdByName,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      transaction.set(activityRef, <String, Object?>{
        'activityId': activityRef.id,
        'businessId': businessId,
        'branchId': branchId,
        'type': 'productAdded',
        'title': 'Product added',
        'subtitle': draft.name.trim(),
        'amount': null,
        'referenceId': productId,
        'createdBy': uid,
        'createdByName': createdByName,
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> updateProduct(
    String businessId,
    String productId,
    ProductDraft draft, {
    String? branchId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const ProductException('unauthenticated');
    _validateDraft(draft, requireOpeningStock: false);
    final writableBranchId = _requireBranchId(branchId);

    final reference = _products(businessId).doc(productId);
    final inventoryRef = _branchInventory(
      businessId,
      writableBranchId,
    ).doc(productId);
    final branchRef = _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('branches')
        .doc(writableBranchId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final inventorySnapshot = await transaction.get(inventoryRef);
      final branchSnapshot = await transaction.get(branchRef);
      if (!snapshot.exists) throw const ProductException('not-found');
      if (!branchSnapshot.exists ||
          branchSnapshot.data()?['status'] != BranchStatus.active.storedValue) {
        throw const ProductException(
          'failed-precondition',
          message: 'This branch is inactive and cannot receive stock changes.',
        );
      }
      final current = Product.fromFirestore(snapshot);
      transaction.update(reference, <String, Object?>{
        'name': draft.name.trim(),
        'sku': draft.sku?.trim().isEmpty == true ? null : draft.sku?.trim(),
        'barcode': draft.barcode?.trim().isEmpty == true
            ? null
            : draft.barcode?.trim(),
        'description': draft.description?.trim().isEmpty == true
            ? null
            : draft.description?.trim(),
        'categoryName': draft.categoryName,
        'imageUrl': draft.imageUrl,
        'imageCid': draft.imageCid,
        'sellingPriceMinor': draft.sellingPriceMinor,
        'costPriceMinor': draft.costPriceMinor,
        'sellingPrice': draft.sellingPriceMinor / 100,
        'price': draft.sellingPriceMinor / 100,
        'costPrice': draft.costPriceMinor / 100,
        'lowStockThreshold': draft.lowStockThreshold,
        'trackStock': draft.trackStock,
        'tracksExpiry': draft.tracksExpiry,
        'defaultExpiryReminderDays': draft.defaultExpiryReminderDays,
        'expiryStatus': draft.tracksExpiry
            ? current.expiryStatus.storedValue
            : ProductExpiryStatus.notTracked.storedValue,
        'unit': draft.unit,
        'status': draft.status.name,
        // Keep quantity untouched on normal edits.
        'quantity': current.quantity,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      });
      transaction.set(inventoryRef, <String, Object?>{
        'businessId': businessId,
        'branchId': writableBranchId,
        'productId': productId,
        'quantity':
            (inventorySnapshot.data()?['quantity'] as num?)?.toDouble() ??
            (writableBranchId == 'main' ? current.quantity : 0),
        'reservedQuantity':
            (inventorySnapshot.data()?['reservedQuantity'] as num?)
                ?.toDouble() ??
            0,
        'lowStockThreshold': draft.trackStock ? draft.lowStockThreshold : 0,
        'averageUnitCostMinor':
            (inventorySnapshot.data()?['averageUnitCostMinor'] as num?)
                ?.round() ??
            current.costPriceMinor,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
        if (!inventorySnapshot.exists)
          'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  @override
  Future<void> setProductStatus(
    String businessId,
    String productId,
    ProductStatus status, {
    String? branchId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const ProductException('unauthenticated');
    await _products(businessId).doc(productId).update(<String, Object?>{
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });
  }

  @override
  Future<void> deleteArchivedProduct(
    String businessId,
    String productId, {
    String? branchId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const ProductException('unauthenticated');
    final writableBranchId = _requireBranchId(branchId);
    final branchSnapshot = await _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('branches')
        .doc(writableBranchId)
        .get();
    if (!branchSnapshot.exists ||
        branchSnapshot.data()?['status'] != BranchStatus.active.storedValue) {
      throw const ProductException(
        'failed-precondition',
        message: 'Switch to an active branch before deleting this product.',
      );
    }

    final reference = _products(businessId).doc(productId);
    final inventorySnapshot = await _allBranchInventory(
      businessId,
    ).where('productId', isEqualTo: productId).get();
    if (inventorySnapshot.docs.any((document) {
      final data = document.data();
      return ((data['quantity'] as num?)?.toDouble() ?? 0) > 0 ||
          ((data['reservedQuantity'] as num?)?.toDouble() ?? 0) > 0;
    })) {
      throw const ProductException(
        'failed-precondition',
        message: 'Reduce stock to zero in every branch before deleting.',
      );
    }

    final snapshot = await reference.get();
    if (!snapshot.exists || snapshot.data() == null) {
      throw const ProductException('not-found');
    }
    final product = Product.fromFirestore(snapshot);
    if (!product.isArchived) {
      throw const ProductException(
        'failed-precondition',
        message: 'Archive this product first before deleting it.',
      );
    }
    if (inventorySnapshot.docs.isEmpty &&
        product.trackStock &&
        product.quantity > 0) {
      throw const ProductException(
        'failed-precondition',
        message: 'Reduce legacy Main Branch stock to zero before deleting.',
      );
    }

    final batch = _firestore.batch();
    batch.delete(reference);
    for (final document in inventorySnapshot.docs) {
      batch.delete(document.reference);
    }
    await batch.commit();

    final activityRef = _activity(businessId).doc();
    await activityRef.set(<String, Object?>{
      'activityId': activityRef.id,
      'businessId': businessId,
      'branchId': writableBranchId,
      'type': 'productDeleted',
      'title': 'Product deleted',
      'subtitle': productId,
      'amount': null,
      'referenceId': productId,
      'createdBy': user.uid,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> adjustStock(
    String businessId,
    StockAdjustmentRequest request, {
    String? branchId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const ProductException('unauthenticated');
    final writableBranchId = _requireBranchId(branchId);
    if (request.quantity == 0) {
      throw const ProductException(
        'failed-precondition',
        message: 'Enter a non-zero quantity for this adjustment.',
      );
    }

    if (request.type == InventoryAdjustmentType.stockIn) {
      try {
        await _apiClient.postJson(
          '/api/inventory/stock-in',
          body: <String, dynamic>{
            'businessId': businessId,
            'branchId': writableBranchId,
            'productId': request.productId,
            'quantity': request.quantity,
            'unitCostMinor': request.unitCostMinor,
            'expiryDate': request.expiryDate?.toIso8601String(),
            'expiryDateKnown':
                request.expiryDateKnown && request.expiryDate != null,
            'reference': request.reference,
            'reason': request.reason,
            'note': request.note,
          },
          timeout: const Duration(seconds: 60),
        );
        return;
      } on ApiException catch (error) {
        throw ProductException(
          error.code ?? 'unavailable',
          message: error.message,
        );
      }
    }

    final productRef = _products(businessId).doc(request.productId);
    final inventoryRef = _branchInventory(
      businessId,
      writableBranchId,
    ).doc(request.productId);
    final branchRef = _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('branches')
        .doc(writableBranchId);
    final movementRef = _movements(businessId).doc();
    final activityRef = _activity(businessId).doc();
    final batchRef = request.type == InventoryAdjustmentType.stockIn
        ? _batches(businessId).doc()
        : null;

    await _firestore.runTransaction((transaction) async {
      final productSnapshot = await transaction.get(productRef);
      final inventorySnapshot = await transaction.get(inventoryRef);
      final branchSnapshot = await transaction.get(branchRef);
      if (!productSnapshot.exists) throw const ProductException('not-found');
      if (!branchSnapshot.exists ||
          branchSnapshot.data()?['status'] != BranchStatus.active.storedValue) {
        throw const ProductException(
          'failed-precondition',
          message: 'This branch is inactive and cannot receive stock changes.',
        );
      }

      final product = Product.fromFirestore(productSnapshot);
      if (!product.trackStock) {
        throw const ProductException(
          'failed-precondition',
          message: 'Stock tracking is disabled for this product.',
        );
      }

      final inventoryData = inventorySnapshot.data();
      final before =
          (inventoryData?['quantity'] as num?)?.toDouble() ??
          (writableBranchId == 'main' ? product.quantity : 0);
      final reserved =
          (inventoryData?['reservedQuantity'] as num?)?.toDouble() ?? 0;
      final delta = request.type.signedQuantity(request.quantity);
      final after = before + delta;
      if (after < 0 || after < reserved) {
        throw const ProductException(
          'failed-precondition',
          message: 'This stock change would result in unavailable stock.',
        );
      }

      final currentUnitCost =
          (inventoryData?['averageUnitCostMinor'] as num?)?.round() ??
          product.costPriceMinor;
      final unitCost = request.unitCostMinor ?? currentUnitCost;
      final nextUnitCost =
          request.type == InventoryAdjustmentType.stockIn &&
              request.unitCostMinor != null &&
              after > 0
          ? ((before * currentUnitCost +
                        request.quantity.abs() * request.unitCostMinor!) /
                    after)
                .round()
          : currentUnitCost;
      final profit = ProductProfitCalculator.calculate(
        currentStock: after,
        currentUnitCostMinor: nextUnitCost,
        currentSellingPriceMinor: product.sellingPriceMinor,
      );

      transaction.set(inventoryRef, <String, Object?>{
        'businessId': businessId,
        'branchId': writableBranchId,
        'productId': product.id,
        'quantity': after,
        'reservedQuantity': reserved,
        'availableQuantity': after - reserved,
        'lowStockThreshold':
            (inventoryData?['lowStockThreshold'] as num?)?.toDouble() ??
            product.lowStockThreshold,
        'averageUnitCostMinor': nextUnitCost,
        'stockCostValueMinor': profit.stockCostValueMinor,
        'expectedStockRevenueMinor': profit.expectedStockRevenueMinor,
        'potentialProfitRemainingMinor': profit.potentialProfitRemainingMinor,
        'realizedGrossProfitMinor':
            (inventoryData?['realizedGrossProfitMinor'] as num?)?.round() ?? 0,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
        if (!inventorySnapshot.exists)
          'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Maintain the old product quantity as an aggregate compatibility mirror.
      // Branch inventory remains authoritative.
      transaction.update(productRef, <String, Object?>{
        'quantity': FieldValue.increment(delta),
        if (request.type == InventoryAdjustmentType.stockIn &&
            request.unitCostMinor != null)
          'costPriceMinor': nextUnitCost,
        if (request.type == InventoryAdjustmentType.stockIn &&
            request.unitCostMinor != null)
          'costPrice': nextUnitCost / 100,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      });

      if (batchRef != null && request.type == InventoryAdjustmentType.stockIn) {
        transaction.set(batchRef, <String, Object?>{
          'businessId': businessId,
          'branchId': writableBranchId,
          'productId': product.id,
          'productName': product.name,
          'sku': product.sku,
          'sourceType': 'manual_stock_in',
          'sourceId': movementRef.id,
          'sourceNumber': request.reference,
          'quantityReceived': request.quantity.abs(),
          'quantityRemaining': request.quantity.abs(),
          'unitCostMinor': unitCost,
          'sellingPriceAtReceiptMinor': product.sellingPriceMinor,
          'expiryDate': request.expiryDate == null
              ? null
              : Timestamp.fromDate(request.expiryDate!),
          'expiryDateKnown':
              request.expiryDateKnown && request.expiryDate != null,
          'receivedAt': FieldValue.serverTimestamp(),
          'status': 'active',
          'createdBy': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'depletedAt': null,
        });
      }

      transaction.set(movementRef, <String, Object?>{
        'id': movementRef.id,
        'businessId': businessId,
        'branchId': writableBranchId,
        'productId': product.id,
        'productName': product.name,
        'batchId': batchRef?.id,
        'type': request.type.storedValue,
        'quantityChange': delta,
        'stockBefore': before,
        'stockAfter': after,
        'reason': request.reason?.trim().isEmpty == true
            ? null
            : request.reason?.trim(),
        'note': request.note?.trim().isEmpty == true
            ? null
            : request.note?.trim(),
        'referenceType': 'manual_adjustment',
        'referenceId': batchRef?.id,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(activityRef, <String, Object?>{
        'activityId': activityRef.id,
        'businessId': businessId,
        'branchId': writableBranchId,
        'type': 'stockAdjustment',
        'title': 'Stock adjusted',
        'subtitle': '${product.name} · ${request.type.label}',
        'amount': null,
        'referenceId': product.id,
        'createdBy': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
    });

    try {
      final bizSnap = await _firestore
          .collection('businesses')
          .doc(businessId)
          .get();
      final businessName = (bizSnap.data()?['name'] as String?) ?? 'Business';
      final product = await getProduct(
        businessId,
        request.productId,
        branchId: writableBranchId,
      );
      if (product != null) {
        await StockAlertService().evaluateProduct(
          businessId: businessId,
          businessName: businessName,
          branchId: writableBranchId,
          product: product,
        );
      }
    } catch (_) {
      // Alerts must not fail stock adjustments.
    }
  }

  @override
  Future<void> disposeExpiredStock(
    String businessId, {
    required String batchId,
    required double quantity,
    required String reason,
    String? branchId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const ProductException('unauthenticated');
    final writableBranchId = _requireBranchId(branchId);
    if (quantity <= 0 || reason.trim().length < 2) {
      throw const ProductException(
        'failed-precondition',
        message: 'Enter a disposal quantity and reason.',
      );
    }
    try {
      await _apiClient.postJson(
        '/api/inventory/batches/dispose',
        body: <String, dynamic>{
          'businessId': businessId,
          'branchId': writableBranchId,
          'batchId': batchId,
          'quantity': quantity,
          'reason': reason.trim(),
        },
        timeout: const Duration(seconds: 60),
      );
    } on ApiException catch (error) {
      throw ProductException(
        error.code ?? 'unavailable',
        message: error.message,
      );
    }
  }

  @override
  Stream<List<InventoryMovement>> watchMovements(
    String businessId,
    String productId, {
    int limit = 20,
    String? branchId,
  }) {
    if (businessId.trim().isEmpty || productId.trim().isEmpty) {
      return Stream<List<InventoryMovement>>.value(const <InventoryMovement>[]);
    }
    return _movements(businessId)
        .where('productId', isEqualTo: productId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => matchesBranchScope(doc.data(), branchId))
              .map(InventoryMovement.fromFirestore)
              .toList(),
        );
  }

  Product _applyInventory(Product product, BranchInventory inventory) {
    return product.withStockSnapshot(
      quantity: inventory.availableQuantity,
      lowStockThreshold: inventory.effectiveLowStockThreshold(
        product.lowStockThreshold,
      ),
      averageUnitCostMinor: inventory.averageUnitCostMinor == 0
          ? product.costPriceMinor
          : inventory.averageUnitCostMinor,
      stockCostValueMinor: inventory.stockCostValueMinor,
      expectedStockRevenueMinor: inventory.expectedStockRevenueMinor,
      potentialProfitRemainingMinor: inventory.potentialProfitRemainingMinor,
      realizedGrossProfitMinor: inventory.realizedGrossProfitMinor,
      expiringQuantity: inventory.expiringQuantity,
      expiredQuantity: inventory.expiredQuantity,
      unknownExpiryQuantity: inventory.unknownExpiryQuantity,
      expiryStatus: inventory.expiryStatus,
      nextExpiryDate: inventory.nextExpiryDate,
      nextExpiryBatchId: inventory.nextExpiryBatchId,
      nextExpiryBatchQuantity: inventory.nextExpiryBatchQuantity,
    );
  }

  Product _zeroStock(Product product) {
    return product.withStockSnapshot(
      quantity: 0,
      lowStockThreshold: product.lowStockThreshold,
      averageUnitCostMinor: product.costPriceMinor,
      stockCostValueMinor: 0,
      expectedStockRevenueMinor: 0,
      potentialProfitRemainingMinor: 0,
      realizedGrossProfitMinor: 0,
      expiringQuantity: 0,
      expiredQuantity: 0,
      unknownExpiryQuantity: 0,
      expiryStatus: product.tracksExpiry
          ? ProductExpiryStatus.safe
          : ProductExpiryStatus.notTracked,
    );
  }

  String _requireBranchId(String? branchId) {
    final normalized = normalizeBranchId(branchId);
    if (normalized == null || normalized.toLowerCase() == 'all') {
      throw const ProductException(
        'failed-precondition',
        message: 'Switch to an active branch before changing inventory.',
      );
    }
    return normalized;
  }

  Stream<R> _combineLatest<A, B, R>(
    Stream<A> first,
    Stream<B> second,
    R Function(A first, B second) combine,
  ) {
    late StreamController<R> controller;
    StreamSubscription<A>? firstSubscription;
    StreamSubscription<B>? secondSubscription;
    A? latestFirst;
    B? latestSecond;
    var hasFirst = false;
    var hasSecond = false;

    void emit() {
      if (hasFirst && hasSecond && !controller.isClosed) {
        controller.add(combine(latestFirst as A, latestSecond as B));
      }
    }

    controller = StreamController<R>(
      onListen: () {
        firstSubscription = first.listen((value) {
          latestFirst = value;
          hasFirst = true;
          emit();
        }, onError: controller.addError);
        secondSubscription = second.listen((value) {
          latestSecond = value;
          hasSecond = true;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await firstSubscription?.cancel();
        await secondSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  void _validateDraft(ProductDraft draft, {required bool requireOpeningStock}) {
    if (draft.name.trim().length < 2) {
      throw const ProductException(
        'failed-precondition',
        message: 'Product name must be at least 2 characters.',
      );
    }
    if (draft.sellingPriceMinor < 0) {
      throw const ProductException(
        'failed-precondition',
        message: 'Selling price cannot be negative.',
      );
    }
    if (draft.costPriceMinor < 0) {
      throw const ProductException(
        'failed-precondition',
        message: 'Cost price cannot be negative.',
      );
    }
    if (draft.lowStockThreshold < 0) {
      throw const ProductException(
        'failed-precondition',
        message: 'Low-stock threshold cannot be negative.',
      );
    }
    if (draft.trackStock && requireOpeningStock && draft.quantity < 0) {
      throw const ProductException(
        'failed-precondition',
        message: 'Opening stock cannot be negative.',
      );
    }
    final quantityError = StockQuantityRules.validate(
      quantity: draft.trackStock ? draft.quantity : 0,
      unit: draft.unit,
    );
    if (quantityError != null) {
      throw ProductException('failed-precondition', message: quantityError);
    }
    if (draft.defaultExpiryReminderDays < 0 ||
        draft.defaultExpiryReminderDays > 365) {
      throw const ProductException(
        'failed-precondition',
        message: 'Expiry reminder days must be between 0 and 365.',
      );
    }
    if (draft.initialStockExpiryDateKnown &&
        draft.initialStockExpiryDate == null) {
      throw const ProductException(
        'failed-precondition',
        message: 'Select a valid expiry date.',
      );
    }
  }
}
