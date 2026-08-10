import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/authenticated_api_client.dart';
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
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _apiClient = apiClient ?? AuthenticatedApiClient();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final AuthenticatedApiClient _apiClient;

  CollectionReference<Map<String, dynamic>> _products(String businessId) =>
      _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('products');

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
    return _products(businessId)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .where((doc) => matchesBranchScope(doc.data(), branchId))
            .map(Product.fromFirestore)
            .toList());
  }

  @override
  Future<Product?> getProduct(String businessId, String productId, {String? branchId}) async {
    if (businessId.trim().isEmpty || productId.trim().isEmpty) return null;
    final snapshot = await _products(businessId).doc(productId).get();
    if (!snapshot.exists || snapshot.data() == null) return null;
    if (!matchesBranchScope(snapshot.data()!, branchId)) return null;
    return Product.fromFirestore(snapshot);
  }

  @override
  Future<String> createProduct(String businessId, ProductDraft draft, {String? branchId}) async {
    final user = _auth.currentUser;
    if (user == null) throw const ProductException('unauthenticated');
    _validateDraft(draft, requireOpeningStock: true);
    final productId = const Uuid().v4();
    final body = <String, dynamic>{
      'businessId': businessId,
      'branchId': branchId,
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
      'initialStockExpiryDate': draft.initialStockExpiryDate?.toIso8601String(),
      'initialStockExpiryDateKnown':
          draft.initialStockExpiryDateKnown &&
          draft.initialStockExpiryDate != null,
    };
    try {
      final response = await _apiClient.postJson(
        '/api/inventory/products/create',
        body: body,
        timeout: const Duration(seconds: 60),
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
          branchId: branchId,
          uid: user.uid,
          createdByName: user.displayName ?? user.email ?? 'Team member',
        );
        return productId;
      }
      throw ProductException(
        error.code ?? 'unavailable',
        message: error.message,
      );
    }
  }

  Future<void> _createProductInFirestore({
    required String businessId,
    required String productId,
    required ProductDraft draft,
    required String uid,
    required String createdByName,
    String? branchId,
  }) async {
    final quantity = draft.trackStock ? draft.quantity : 0.0;
    final expiryKnown =
        draft.tracksExpiry &&
        quantity > 0 &&
        draft.initialStockExpiryDateKnown &&
        draft.initialStockExpiryDate != null;
    final expiryDate = expiryKnown ? draft.initialStockExpiryDate : null;
    final productRef = _products(businessId).doc(productId);
    final batchRef = _batches(businessId).doc('${productId}_initial');
    final movementRef = _movements(businessId).doc();
    final activityRef = _activity(businessId).doc();
    final businessRef = _firestore.collection('businesses').doc(businessId);

    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(productRef);
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
        'branchId': branchId,
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
        'imageUrl': null,
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

      if (draft.trackStock && quantity > 0) {
        transaction.set(batchRef, <String, Object?>{
          'businessId': businessId,
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
  }
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw const ProductException('unauthenticated');
    _validateDraft(draft, requireOpeningStock: false);

    final reference = _products(businessId).doc(productId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) throw const ProductException('not-found');
      final current = Product.fromFirestore(snapshot);
      transaction.update(reference, <String, Object?>{
        'branchId': branchId,
        'name': draft.name.trim(),
        'sku': draft.sku?.trim().isEmpty == true ? null : draft.sku?.trim(),
        'barcode': draft.barcode?.trim().isEmpty == true
            ? null
            : draft.barcode?.trim(),
        'description': draft.description?.trim().isEmpty == true
            ? null
            : draft.description?.trim(),
        'categoryName': draft.categoryName,
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
    });
  }

  @override
  Future<void> setProductStatus(
    String businessId,
    String productId,
    ProductStatus status, {
    String? branchId,
  }
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw const ProductException('unauthenticated');
    await _products(businessId).doc(productId).update(<String, Object?>{
      'branchId': branchId,
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
  }
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw const ProductException('unauthenticated');
    final reference = _products(businessId).doc(productId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      if (!snapshot.exists) throw const ProductException('not-found');
      final product = Product.fromFirestore(snapshot);
      if (!product.isArchived) {
        throw const ProductException(
          'failed-precondition',
          message: 'Archive this product first before deleting it.',
        );
      }
      if (product.trackStock && product.quantity > 0) {
        throw const ProductException(
          'failed-precondition',
          message: 'Reduce stock to zero before deleting this product.',
        );
      }
      if (!matchesBranchScope(snapshot.data()!, branchId)) {
        throw const ProductException('failed-precondition');
      }
      transaction.delete(reference);
    });

    final activityRef = _activity(businessId).doc();
    await activityRef.set(<String, Object?>{
      'activityId': activityRef.id,
      'businessId': businessId,
      'branchId': branchId,
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
  }
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw const ProductException('unauthenticated');
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
        if (error.statusCode != 404 && error.statusCode != 405) {
          throw ProductException(
            error.code ?? 'unavailable',
            message: error.message,
          );
        }
        // Fall through to local stock-in when inventory API is not deployed.
      }
    }

    final productRef = _products(businessId).doc(request.productId);
    final movementRef = _movements(businessId).doc();
    final activityRef = _activity(businessId).doc();
    final batchRef = request.type == InventoryAdjustmentType.stockIn
        ? _batches(businessId).doc()
        : null;

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(productRef);
      if (!snapshot.exists) throw const ProductException('not-found');
      final product = Product.fromFirestore(snapshot);
      if (!product.trackStock) {
        throw const ProductException(
          'failed-precondition',
          message: 'Stock tracking is disabled for this product.',
        );
      }

      final delta = request.type.signedQuantity(request.quantity);
      final before = product.quantity;
      final after = before + delta;
      if (after < 0) {
        throw const ProductException(
          'failed-precondition',
          message: 'This stock change would result in a negative quantity.',
        );
      }

      final unitCost = request.unitCostMinor ?? product.costPriceMinor;
      transaction.update(productRef, <String, Object?>{
        'branchId': branchId,
        'quantity': after,
        if (request.type == InventoryAdjustmentType.stockIn &&
            request.unitCostMinor != null)
          'costPriceMinor': unitCost,
        if (request.type == InventoryAdjustmentType.stockIn &&
            request.unitCostMinor != null)
          'costPrice': unitCost / 100,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      });
      if (batchRef != null && request.type == InventoryAdjustmentType.stockIn) {
        transaction.set(batchRef, <String, Object?>{
          'businessId': businessId,
          'productId': product.id,
          'productName': product.name,
          'sku': product.sku,
          'sourceType': 'manual_stock_in',
          'sourceId': movementRef.id,
          'sourceNumber': request.reference,
          'quantityReceived': request.quantity,
          'quantityRemaining': request.quantity,
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
        'branchId': branchId,
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
        'type': 'stockAdjustment',
        'title': 'Stock adjusted',
        'subtitle': '${product.name} · ${request.type.label}',
        'amount': null,
        'referenceId': product.id,
        'createdBy': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
    });

    // Post-transaction: evaluate inventory alerts (never inside build()).
    try {
      final bizSnap = await _firestore
          .collection('businesses')
          .doc(businessId)
          .get();
      final businessName = (bizSnap.data()?['name'] as String?) ?? 'Business';
      final productSnap = await productRef.get();
      if (productSnap.exists) {
        await StockAlertService().evaluateProduct(
          businessId: businessId,
          businessName: businessName,
          product: Product.fromFirestore(productSnap),
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
          'branchId': branchId,
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
