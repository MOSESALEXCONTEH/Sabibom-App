import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../branches/application/current_branch_providers.dart';
import '../../../core/sync/offline_mutation_queue.dart';
import '../../notifications/application/transaction_notification_service.dart';
import '../../products/application/products_providers.dart';
import '../../products/domain/product.dart';
import '../data/firestore_sales_repository.dart';
import '../data/notifying_sales_repository.dart';
import '../data/sales_repository.dart';
import '../domain/sale.dart';
import '../domain/sale_models.dart';

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => NotifyingSalesRepository(
    FirestoreSalesRepository(
      offlineQueue: ref.watch(offlineMutationQueueProvider),
    ),
    ref.watch(transactionNotificationServiceProvider),
  ),
);

final salesHistoryProvider =
    StreamProvider.family<List<SaleHistoryItem>, String>((ref, businessId) {
      final branchId = ref.watch(currentBranchReadScopeProvider);
      final source = ref
          .watch(salesRepositoryProvider)
          .watchRecentSales(businessId, branchId: branchId, limit: 500);
      final queue = ref.watch(offlineMutationQueueProvider);
      late StreamController<List<SaleHistoryItem>> controller;
      StreamSubscription<List<SaleHistoryItem>>? salesSubscription;
      StreamSubscription<void>? queueSubscription;
      var sales = const <SaleHistoryItem>[];

      Future<void> emit() async {
        final pending = await queue.pending(businessId: businessId);
        final additions = pending
            .where((item) => item.type == OfflineMutationType.saleComplete)
            .map((item) => item.payload['summary'])
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .where(
              (summary) => branchId == null || summary['branchId'] == branchId,
            )
            .map(
              (summary) => SaleHistoryItem.fromFirestore(
                summary['saleId'] as String,
                <String, dynamic>{
                  ...summary,
                  'paymentStatus': (summary['balanceDueMinor'] as num? ?? 0) > 0
                      ? PaymentStatus.partiallyPaid.name
                      : PaymentStatus.paid.name,
                  'saleStatus': SaleStatus.completed.name,
                  'createdAt': DateTime.tryParse(
                    summary['createdAt'] as String? ?? '',
                  ),
                },
              ),
            );
        final merged = <String, SaleHistoryItem>{
          for (final sale in sales) sale.saleId: sale,
        };
        for (final sale in additions) {
          merged[sale.saleId] = sale;
        }
        if (!controller.isClosed) {
          final result = merged.values.toList()
            ..sort(
              (left, right) => (right.createdAt ?? DateTime(1970)).compareTo(
                left.createdAt ?? DateTime(1970),
              ),
            );
          controller.add(result);
        }
      }

      controller = StreamController<List<SaleHistoryItem>>(
        onListen: () {
          salesSubscription = source.listen((value) {
            sales = value;
            unawaited(emit());
          }, onError: controller.addError);
          queueSubscription = queue.changes.listen((_) => unawaited(emit()));
          unawaited(emit());
        },
        onCancel: () async {
          await salesSubscription?.cancel();
          await queueSubscription?.cancel();
        },
      );
      return controller.stream;
    });

final saleDetailProvider =
    FutureProvider.family<Map<String, dynamic>?, (String, String)>((
      ref,
      request,
    ) async {
      final local = await _pendingSaleMap(ref, request.$1, request.$2);
      if (local != null) return local;
      return ref.watch(salesRepositoryProvider).getSale(request.$1, request.$2);
    });

final saleDocumentProvider = FutureProvider.family<Sale?, (String, String)>((
  ref,
  request,
) async {
  final local = await _pendingSaleMap(ref, request.$1, request.$2);
  if (local != null) return Sale.fromMap(request.$2, local);
  return ref
      .watch(salesRepositoryProvider)
      .getSaleDocument(request.$1, request.$2);
});

Future<Map<String, dynamic>?> _pendingSaleMap(
  Ref ref,
  String businessId,
  String saleId,
) async {
  final branchId = ref.watch(currentBranchReadScopeProvider);
  final pending = await ref
      .watch(offlineMutationQueueProvider)
      .pending(businessId: businessId);
  return pendingSaleMapFromMutations(
    mutations: pending,
    businessId: businessId,
    saleId: saleId,
    branchId: branchId,
  );
}

Map<String, dynamic>? pendingSaleMapFromMutations({
  required Iterable<OfflineMutation> mutations,
  required String businessId,
  required String saleId,
  required String? branchId,
}) {
  for (final item in mutations) {
    if (item.type != OfflineMutationType.saleComplete) continue;
    final summary = item.payload['summary'];
    if (summary is! Map || summary['saleId'] != saleId) continue;
    final data = Map<String, dynamic>.from(summary);
    if (branchId != null && data['branchId'] != branchId) return null;
    final request = item.payload['request'];
    if (request is Map) {
      final requestMap = Map<String, dynamic>.from(request);
      final rawItems = (requestMap['items'] as List? ?? const <Object?>[])
          .whereType<Map>()
          .map((raw) {
            final line = Map<String, dynamic>.from(raw);
            final quantity = (line['quantity'] as num?)?.toDouble() ?? 0;
            final unitPrice = (line['unitPriceMinor'] as num?)?.round() ?? 0;
            final subtotal = (quantity * unitPrice).round();
            final discountValue =
                (line['discountValue'] as num?)?.toDouble() ?? 0;
            final discount = switch (line['discountType']) {
              'fixed' => moneyToMinor(discountValue),
              'percentage' => (subtotal * (discountValue / 100)).round(),
              _ => 0,
            }.clamp(0, subtotal);
            return <String, dynamic>{
              ...line,
              'lineSubtotalMinor': subtotal,
              'lineDiscountMinor': discount,
              'lineTotalMinor': subtotal - discount,
            };
          })
          .toList(growable: false);
      data
        ..putIfAbsent('businessId', () => businessId)
        ..['items'] = rawItems
        ..putIfAbsent(
          'branchNameSnapshot',
          () => requestMap['branchNameSnapshot'],
        )
        ..putIfAbsent(
          'branchCodeSnapshot',
          () => requestMap['branchCodeSnapshot'],
        )
        ..putIfAbsent('customerId', () => requestMap['customerId'])
        ..putIfAbsent('customerPhone', () => requestMap['customerPhone'])
        ..putIfAbsent('note', () => requestMap['note'])
        ..putIfAbsent('createdByName', () => requestMap['cashierName']);
    }
    data
      ..putIfAbsent(
        'paymentStatus',
        () => (data['balanceDueMinor'] as num? ?? 0) > 0
            ? PaymentStatus.partiallyPaid.name
            : PaymentStatus.paid.name,
      )
      ..putIfAbsent('saleStatus', () => SaleStatus.completed.name);
    return data;
  }
  return null;
}

final saleProductsProvider = StreamProvider.family<List<SaleProduct>, String>((
  ref,
  businessId,
) {
  if (businessId.trim().isEmpty) {
    return Stream<List<SaleProduct>>.value(const <SaleProduct>[]);
  }
  final branchId = ref.watch(currentBranchReadScopeProvider);
  final pending =
      ref.watch(pendingOfflineMutationsProvider).asData?.value ??
      const <OfflineMutation>[];
  final reserved = pendingSaleStockReservations(
    mutations: pending,
    businessId: businessId,
    branchId: branchId,
  );
  final incoming = pendingPurchaseStockAdditions(
    mutations: pending,
    businessId: businessId,
    branchId: branchId,
  );
  return ref
      .watch(productsRepositoryProvider)
      .watchProducts(businessId, branchId: branchId)
      .map((sourceProducts) {
        final products = <String, Product>{
          for (final product in sourceProducts) product.id: product,
        };
        for (final mutation in pending.where(
          (item) =>
              item.businessId == businessId &&
              item.type == OfflineMutationType.productCreate &&
              (branchId == null || item.payload['branchId'] == branchId),
        )) {
          final productId = mutation.payload['productId'] as String;
          products[productId] = Product.fromMap(productId, <String, dynamic>{
            ...mutation.payload,
            'businessId': businessId,
          });
        }
        return products.values
            .where((product) => product.isActive)
            .take(200)
            .map(
              (product) => SaleProduct(
                productId: product.id,
                name: product.name,
                sku: product.sku,
                barcode: product.barcode,
                unit: product.unit,
                sellingPriceMinor: product.sellingPriceMinor,
                costPriceMinor: product.costPriceMinor,
                quantity:
                    (product.quantity +
                            (incoming[product.id] ?? 0) -
                            (reserved[product.id] ?? 0))
                        .clamp(0, double.infinity),
                lowStockThreshold: product.lowStockThreshold,
                trackStock: product.trackStock,
                status: product.status.name,
                categoryName: product.categoryName,
                imageUrl: product.imageUrl,
              ),
            )
            .toList(growable: false);
      });
});

Map<String, double> pendingSaleStockReservations({
  required Iterable<OfflineMutation> mutations,
  required String businessId,
  required String? branchId,
}) {
  final reserved = <String, double>{};
  for (final mutation in mutations.where(
    (item) =>
        item.businessId == businessId &&
        item.type == OfflineMutationType.saleComplete &&
        (branchId == null ||
            (item.payload['summary'] as Map?)?['branchId'] == branchId),
  )) {
    final request = mutation.payload['request'] as Map?;
    final items = request?['items'] as List? ?? const <Object?>[];
    for (final raw in items.whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final productId = item['productId'] as String?;
      if (productId == null || item['trackStock'] != true) continue;
      reserved.update(
        productId,
        (value) => value + ((item['quantity'] as num?)?.toDouble() ?? 0),
        ifAbsent: () => (item['quantity'] as num?)?.toDouble() ?? 0,
      );
    }
  }
  return reserved;
}

final saleCustomersProvider = StreamProvider.family<List<SaleCustomer>, String>(
  (ref, businessId) {
    if (businessId.trim().isEmpty) {
      return Stream<List<SaleCustomer>>.value(const <SaleCustomer>[]);
    }
    return FirebaseFirestore.instance
        .collection('businesses')
        .doc(businessId)
        .collection('customers')
        .orderBy('name')
        .limit(200)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where(
                (doc) =>
                    (doc.data()['status'] as String? ?? 'active') == 'active',
              )
              .map((doc) => SaleCustomer.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  },
);
