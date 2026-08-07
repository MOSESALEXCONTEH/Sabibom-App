import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../branches/application/current_branch_providers.dart';
import '../data/firestore_products_repository.dart';
import '../data/products_repository.dart';
import '../domain/inventory_movement.dart';
import '../domain/product.dart';

final productsRepositoryProvider = Provider<ProductsRepository>(
  (ref) => FirestoreProductsRepository(),
);

final productsListProvider = StreamProvider.family<List<Product>, String>((
  ref,
  businessId,
) {
  final branchId = ref.watch(currentBranchReadScopeProvider);
  return ref
      .watch(productsRepositoryProvider)
      .watchProducts(businessId, branchId: branchId);
});

final productDetailProvider = FutureProvider.family<Product?, (String, String)>(
  (ref, request) {
    final branchId = ref.watch(currentBranchReadScopeProvider);
    return ref
        .watch(productsRepositoryProvider)
        .getProduct(request.$1, request.$2, branchId: branchId);
  },
);

final productMovementsProvider =
    StreamProvider.family<List<InventoryMovement>, (String, String)>((
      ref,
      request,
    ) {
      final branchId = ref.watch(currentBranchReadScopeProvider);
      return ref
          .watch(productsRepositoryProvider)
          .watchMovements(request.$1, request.$2, branchId: branchId);
    });

bool hasDuplicateBarcode({
  required Iterable<Product> products,
  required String barcode,
  String? excludingProductId,
}) {
  final normalized = barcode.trim();
  if (normalized.isEmpty) return false;
  return products.any(
    (product) =>
        product.id != excludingProductId &&
        product.barcode?.trim() == normalized,
  );
}

List<Product> filterProducts({
  required List<Product> products,
  required String query,
  required ProductStockFilter filter,
  String? category,
}) {
  final normalized = query.trim().toLowerCase();
  return products.where((product) {
    final matchesFilter = switch (filter) {
      ProductStockFilter.all => product.isActive,
      ProductStockFilter.inStock =>
        product.isActive && product.trackStock && product.quantity > 0,
      ProductStockFilter.lowStock => product.isActive && product.isLowStock,
      ProductStockFilter.outOfStock => product.isActive && product.isOutOfStock,
      ProductStockFilter.expiringSoon =>
        product.isActive &&
            product.tracksExpiry &&
            (product.expiryStatus == ProductExpiryStatus.expiringSoon ||
                (product.expiryStatus == ProductExpiryStatus.mixed &&
                    product.expiringQuantity > 0)),
      ProductStockFilter.expiresToday =>
        product.isActive &&
            product.tracksExpiry &&
            product.expiryStatus == ProductExpiryStatus.expiresToday,
      ProductStockFilter.expired =>
        product.isActive &&
            product.tracksExpiry &&
            (product.expiryStatus == ProductExpiryStatus.expired ||
                product.expiredQuantity > 0),
      ProductStockFilter.expiryUnknown =>
        product.isActive &&
            product.tracksExpiry &&
            product.unknownExpiryQuantity > 0,
      ProductStockFilter.noExpiryTracking =>
        product.isActive && !product.tracksExpiry,
      ProductStockFilter.untracked => product.isActive && product.isUntracked,
      ProductStockFilter.archived => product.isArchived,
    };
    if (!matchesFilter) return false;

    if (category != null &&
        category.trim().isNotEmpty &&
        (product.categoryName ?? '') != category) {
      return false;
    }

    if (normalized.isEmpty) return true;
    return product.name.toLowerCase().contains(normalized) ||
        (product.sku ?? '').toLowerCase().contains(normalized) ||
        (product.barcode ?? '').toLowerCase().contains(normalized);
  }).toList();
}

List<Product> sortProducts({
  required List<Product> products,
  required ProductSort sort,
}) {
  final sorted = List<Product>.from(products);
  int compareNullableDates(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  sorted.sort((left, right) {
    return switch (sort) {
      ProductSort.name => left.name.toLowerCase().compareTo(
        right.name.toLowerCase(),
      ),
      ProductSort.nearestExpiry => compareNullableDates(
        left.nextExpiryDate,
        right.nextExpiryDate,
      ),
      ProductSort.stockQuantity => right.quantity.compareTo(left.quantity),
      ProductSort.potentialProfit =>
        right.potentialProfitRemainingMinor.compareTo(
          left.potentialProfitRemainingMinor,
        ),
      ProductSort.realizedProfit => right.realizedGrossProfitMinor.compareTo(
        left.realizedGrossProfitMinor,
      ),
      ProductSort.stockValue => right.stockCostValueMinor.compareTo(
        left.stockCostValueMinor,
      ),
      ProductSort.recentlyAdded => compareNullableDates(
        right.createdAt,
        left.createdAt,
      ),
    };
  });
  return sorted;
}
