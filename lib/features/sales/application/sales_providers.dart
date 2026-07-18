import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/firestore_sales_repository.dart';
import '../data/sales_repository.dart';
import '../domain/sale_models.dart';

final salesRepositoryProvider = Provider<SalesRepository>((ref) => FirestoreSalesRepository());

final salesHistoryProvider = StreamProvider.family<List<SaleHistoryItem>, String>((ref, businessId) {
  return ref.read(salesRepositoryProvider).watchRecentSales(businessId);
});

final saleDetailProvider = FutureProvider.family<Map<String, dynamic>?, (String, String)>((ref, request) {
  return ref.read(salesRepositoryProvider).getSale(request.$1, request.$2);
});

final saleProductsProvider = StreamProvider.family<List<SaleProduct>, String>((ref, businessId) {
  if (businessId.trim().isEmpty) return Stream<List<SaleProduct>>.value(const <SaleProduct>[]);
  return FirebaseFirestore.instance
      .collection('businesses')
      .doc(businessId)
      .collection('products')
      .where('status', isEqualTo: 'active')
      .limit(50)
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => SaleProduct.fromFirestore(doc.id, doc.data())).toList());
});

final saleCustomersProvider = StreamProvider.family<List<SaleCustomer>, String>((ref, businessId) {
  if (businessId.trim().isEmpty) return Stream<List<SaleCustomer>>.value(const <SaleCustomer>[]);
  return FirebaseFirestore.instance
      .collection('businesses')
      .doc(businessId)
      .collection('customers')
      .orderBy('name')
      .limit(50)
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => SaleCustomer.fromFirestore(doc.id, doc.data())).toList());
});