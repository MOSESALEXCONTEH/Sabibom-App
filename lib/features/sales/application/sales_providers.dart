import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../branches/application/current_branch_providers.dart';
import '../../products/application/products_providers.dart';
import '../data/firestore_sales_repository.dart';
import '../data/sales_repository.dart';
import '../domain/sale.dart';
import '../domain/sale_models.dart';

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => FirestoreSalesRepository(),
);

final salesHistoryProvider =
    StreamProvider.family<List<SaleHistoryItem>, String>((ref, businessId) {
      final branchId = ref.watch(currentBranchReadScopeProvider);
      return ref
          .watch(salesRepositoryProvider)
          .watchRecentSales(businessId, branchId: branchId, limit: 500);
    });

final saleDetailProvider =
    FutureProvider.family<Map<String, dynamic>?, (String, String)>((
      ref,
      request,
    ) {
      return ref.watch(salesRepositoryProvider).getSale(request.$1, request.$2);
    });

final saleDocumentProvider = FutureProvider.family<Sale?, (String, String)>((
  ref,
  request,
) {
  return ref
      .watch(salesRepositoryProvider)
      .getSaleDocument(request.$1, request.$2);
});

final saleProductsProvider = StreamProvider.family<List<SaleProduct>, String>((
  ref,
  businessId,
) {
  if (businessId.trim().isEmpty) {
    return Stream<List<SaleProduct>>.value(const <SaleProduct>[]);
  }
  final branchId = ref.watch(currentBranchReadScopeProvider);
  return ref
      .watch(productsRepositoryProvider)
      .watchProducts(businessId, branchId: branchId)
      .map(
        (products) => products
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
                quantity: product.quantity,
                lowStockThreshold: product.lowStockThreshold,
                trackStock: product.trackStock,
                status: product.status.name,
                categoryName: product.categoryName,
                imageUrl: product.imageUrl,
              ),
            )
            .toList(growable: false),
      );
});

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
