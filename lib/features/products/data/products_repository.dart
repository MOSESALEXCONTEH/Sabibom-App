import '../domain/inventory_movement.dart';
import '../domain/product.dart';

String? encodeProductInitialExpiryDate(DateTime? value) {
  if (value == null) return null;
  return DateTime.utc(value.year, value.month, value.day, 12).toIso8601String();
}

class ProductDraft {
  const ProductDraft({
    required this.name,
    required this.sellingPriceMinor,
    required this.costPriceMinor,
    required this.trackStock,
    required this.quantity,
    required this.lowStockThreshold,
    required this.unit,
    required this.status,
    this.tracksExpiry = false,
    this.defaultExpiryReminderDays = 30,
    this.initialStockExpiryDate,
    this.initialStockExpiryDateKnown = false,
    this.sku,
    this.barcode,
    this.description,
    this.categoryName,
    this.imageUrl,
    this.imageCid,
  });

  final String name;
  final String? sku;
  final String? barcode;
  final String? description;
  final String? categoryName;
  final String? imageUrl;
  final String? imageCid;
  final int sellingPriceMinor;
  final int costPriceMinor;
  final bool trackStock;
  final double quantity;
  final double lowStockThreshold;
  final String unit;
  final ProductStatus status;
  final bool tracksExpiry;
  final int defaultExpiryReminderDays;
  final DateTime? initialStockExpiryDate;
  final bool initialStockExpiryDateKnown;
}

class StockAdjustmentRequest {
  const StockAdjustmentRequest({
    required this.productId,
    required this.type,
    required this.quantity,
    this.reason,
    this.note,
    this.unitCostMinor,
    this.expiryDate,
    this.expiryDateKnown = false,
    this.reference,
  });

  final String productId;
  final InventoryAdjustmentType type;
  final double quantity;
  final String? reason;
  final String? note;
  final int? unitCostMinor;
  final DateTime? expiryDate;
  final bool expiryDateKnown;
  final String? reference;
}

abstract interface class ProductsRepository {
  Stream<List<Product>> watchProducts(String businessId, {String? branchId});
  Future<Product?> getProduct(
    String businessId,
    String productId, {
    String? branchId,
  });
  Future<String> createProduct(
    String businessId,
    ProductDraft draft, {
    String? branchId,
    bool queueWhenOffline = false,
  });
  Future<void> updateProduct(
    String businessId,
    String productId,
    ProductDraft draft, {
    String? branchId,
  });
  Future<void> setProductStatus(
    String businessId,
    String productId,
    ProductStatus status, {
    String? branchId,
  });

  /// Permanently removes an archived product with zero stock.
  /// Sales history is kept; the product record is deleted.
  Future<void> deleteArchivedProduct(
    String businessId,
    String productId, {
    String? branchId,
  });

  Future<void> adjustStock(
    String businessId,
    StockAdjustmentRequest request, {
    String? branchId,
  });
  Future<void> disposeExpiredStock(
    String businessId, {
    required String batchId,
    required double quantity,
    required String reason,
    String? branchId,
  });
  Stream<List<InventoryMovement>> watchMovements(
    String businessId,
    String productId, {
    int limit = 20,
    String? branchId,
  });
}

class ProductException implements Exception {
  const ProductException(this.code, {this.message});

  final String code;
  final String? message;

  String get friendlyMessage =>
      message ??
      switch (code) {
        'permission-denied' =>
          'You do not have permission to access this business information.',
        'unavailable' =>
          'This information is temporarily unavailable. Please try again.',
        'not-found' =>
          'This record could not be found. It may have been removed or archived.',
        'failed-precondition' =>
          'This stock change would result in a negative quantity.',
        'unauthenticated' => 'Your session expired. Please sign in again.',
        _ => 'Something went wrong. Please try again.',
      };

  @override
  String toString() => 'ProductException($code): $friendlyMessage';
}
