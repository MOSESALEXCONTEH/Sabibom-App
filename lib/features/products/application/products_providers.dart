import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../branches/application/current_branch_providers.dart';
import '../../../core/sync/offline_mutation_queue.dart';
import '../data/firestore_products_repository.dart';
import '../data/products_repository.dart';
import '../domain/inventory_movement.dart';
import '../domain/product.dart';

final productsRepositoryProvider = Provider<ProductsRepository>(
  (ref) => FirestoreProductsRepository(
    offlineQueue: ref.watch(offlineMutationQueueProvider),
  ),
);

final productsListProvider = StreamProvider.family<List<Product>, String>((
  ref,
  businessId,
) {
  final branchId = ref.watch(currentBranchReadScopeProvider);
  final source = ref
      .watch(productsRepositoryProvider)
      .watchProducts(businessId, branchId: branchId);
  final queue = ref.watch(offlineMutationQueueProvider);
  late StreamController<List<Product>> controller;
  StreamSubscription<List<Product>>? productsSubscription;
  StreamSubscription<void>? queueSubscription;
  var products = const <Product>[];

  Future<void> emit() async {
    final pending = await queue.pending(businessId: businessId);
    final additions = pending
        .where(
          (item) =>
              item.type == OfflineMutationType.productCreate &&
              (branchId == null || item.payload['branchId'] == branchId),
        )
        .map((item) {
          final data = <String, dynamic>{
            ...item.payload,
            'businessId': businessId,
            'status': item.payload['status'] ?? 'active',
          };
          return Product.fromMap(item.payload['productId'] as String, data);
        });
    final merged = <String, Product>{
      for (final product in products) product.id: product,
    };
    for (final product in additions) {
      merged[product.id] = product;
    }
    final stockChanges = pendingPurchaseStockAdditions(
      mutations: pending,
      businessId: businessId,
      branchId: branchId,
    );
    for (final mutation in pending.where(
      (item) =>
          item.type == OfflineMutationType.saleComplete &&
          (branchId == null ||
              (item.payload['summary'] as Map?)?['branchId'] == branchId),
    )) {
      final request = mutation.payload['request'] as Map?;
      for (final raw
          in (request?['items'] as List? ?? const <Object?>[])
              .whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        final productId = item['productId'] as String?;
        if (productId == null || item['trackStock'] != true) continue;
        stockChanges.update(
          productId,
          (value) => value - ((item['quantity'] as num?)?.toDouble() ?? 0),
          ifAbsent: () => -((item['quantity'] as num?)?.toDouble() ?? 0),
        );
      }
    }
    for (final entry in stockChanges.entries) {
      final product = merged[entry.key];
      if (product == null) continue;
      merged[entry.key] = product.withStockSnapshot(
        quantity: (product.quantity + entry.value).clamp(0, double.infinity),
        lowStockThreshold: product.lowStockThreshold,
        averageUnitCostMinor: product.costPriceMinor,
        stockCostValueMinor: product.stockCostValueMinor,
        expectedStockRevenueMinor: product.expectedStockRevenueMinor,
        potentialProfitRemainingMinor: product.potentialProfitRemainingMinor,
        realizedGrossProfitMinor: product.realizedGrossProfitMinor,
        expiringQuantity: product.expiringQuantity,
        expiredQuantity: product.expiredQuantity,
        unknownExpiryQuantity: product.unknownExpiryQuantity,
        expiryStatus: product.expiryStatus,
        nextExpiryDate: product.nextExpiryDate,
        nextExpiryBatchId: product.nextExpiryBatchId,
        nextExpiryBatchQuantity: product.nextExpiryBatchQuantity,
        profitIsEstimated: product.profitIsEstimated,
      );
    }
    if (!controller.isClosed) {
      final result = merged.values.toList()
        ..sort((left, right) => left.name.compareTo(right.name));
      controller.add(result);
    }
  }

  controller = StreamController<List<Product>>(
    onListen: () {
      productsSubscription = source.listen((value) {
        products = value;
        unawaited(emit());
      }, onError: controller.addError);
      queueSubscription = queue.changes.listen((_) => unawaited(emit()));
      unawaited(emit());
    },
    onCancel: () async {
      await productsSubscription?.cancel();
      await queueSubscription?.cancel();
    },
  );
  return controller.stream;
});

Map<String, double> pendingPurchaseStockAdditions({
  required Iterable<OfflineMutation> mutations,
  required String businessId,
  required String? branchId,
}) {
  final additions = <String, double>{};
  for (final mutation in mutations.where(
    (item) =>
        item.businessId == businessId &&
        item.type == OfflineMutationType.purchaseComplete &&
        (branchId == null ||
            (item.payload['summary'] as Map?)?['branchId'] == branchId),
  )) {
    final request = mutation.payload['request'] as Map?;
    for (final raw
        in (request?['items'] as List? ?? const <Object?>[]).whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final productId = item['productId'] as String?;
      if (productId == null || item['trackStock'] != true) continue;
      additions.update(
        productId,
        (value) => value + ((item['quantity'] as num?)?.toDouble() ?? 0),
        ifAbsent: () => (item['quantity'] as num?)?.toDouble() ?? 0,
      );
    }
  }
  return additions;
}

final productDetailProvider = FutureProvider.family<Product?, (String, String)>(
  (ref, request) async {
    final branchId = ref.watch(currentBranchReadScopeProvider);
    final product = await ref
        .watch(productsRepositoryProvider)
        .getProduct(request.$1, request.$2, branchId: branchId);
    if (product != null) return product;
    final pending = await ref
        .watch(offlineMutationQueueProvider)
        .pending(businessId: request.$1);
    for (final item in pending) {
      if (item.type == OfflineMutationType.productCreate &&
          item.payload['productId'] == request.$2 &&
          (branchId == null || item.payload['branchId'] == branchId)) {
        return Product.fromMap(request.$2, <String, dynamic>{
          ...item.payload,
          'businessId': request.$1,
        });
      }
    }
    return null;
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
