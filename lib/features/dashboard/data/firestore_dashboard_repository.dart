import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/formatting/date_range_utils.dart';
import '../domain/dashboard_models.dart';
import 'dashboard_repository.dart';

class FirestoreDashboardRepository implements DashboardRepository {
  FirestoreDashboardRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<DashboardSummary> getSummary({
    required String businessId,
    required DashboardPeriod period,
    required String currencyCode,
    required String currencySymbol,
  }) async {
    final range = dashboardDateRange(period);
    final empty = DashboardSummary.empty(
      range,
      code: currencyCode,
      symbol: currencySymbol,
    );
    if (businessId.trim().isEmpty) return empty;
    try {
      final business = _firestore.collection('businesses').doc(businessId);
      final results = await Future.wait<QuerySnapshot<Map<String, dynamic>>>(
        <Future<QuerySnapshot<Map<String, dynamic>>>>[
          business
              .collection('sales')
              .where(
                'createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
              )
              .where('createdAt', isLessThan: Timestamp.fromDate(range.end))
              .limit(200)
              .get(),
          business
              .collection('expenses')
              .where(
                'createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
              )
              .where('createdAt', isLessThan: Timestamp.fromDate(range.end))
              .limit(200)
              .get(),
          business.collection('customers').limit(200).get(),
          business.collection('products').limit(200).get(),
        ],
      );
      final sales = results[0].docs
          .where(
            (doc) =>
                (doc.data()['status'] as String? ?? 'completed') == 'completed',
          )
          .toList();
      final expenses = results[1].docs.where((doc) {
        final status = doc.data()['status'] as String? ?? 'active';
        return status != 'voided' && status != 'cancelled';
      }).toList();
      final customers = results[2].docs;
      final products = results[3].docs;
      return DashboardSummary(
        totalSales: sales.fold<double>(
          0,
          (total, doc) =>
              total + ((doc.data()['total'] as num?)?.toDouble() ?? 0),
        ),
        totalExpenses: expenses.fold<double>(
          0,
          (total, doc) =>
              total + ((doc.data()['amount'] as num?)?.toDouble() ?? 0),
        ),
        orderCount: sales.length,
        customerCount: customers.length,
        lowStockCount: products.where((doc) {
          final data = doc.data();
          return ((data['quantity'] as num?)?.toDouble() ?? 0) <=
              ((data['lowStockThreshold'] as num?)?.toDouble() ?? 0);
        }).length,
        outstandingBalance: customers.fold<double>(
          0,
          (total, doc) =>
              total + ((doc.data()['balance'] as num?)?.toDouble() ?? 0),
        ),
        periodStart: range.start,
        periodEnd: range.end,
        currencyCode: currencyCode,
        currencySymbol: currencySymbol,
      );
    } on FirebaseException catch (error, stackTrace) {
      _log('getSummary', error, stackTrace);
      rethrow;
    }
  }

  @override
  Stream<List<DashboardActivity>> watchRecentActivity({
    required String businessId,
    int limit = 5,
  }) {
    if (businessId.trim().isEmpty) {
      return Stream<List<DashboardActivity>>.value(const <DashboardActivity>[]);
    }
    return _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('activity')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            return DashboardActivity(
              id: doc.id,
              businessId: businessId,
              type:
                  DashboardActivityType.values
                      .where((type) => type.name == data['type'])
                      .firstOrNull ??
                  DashboardActivityType.other,
              title: data['title'] as String? ?? 'Business update',
              subtitle: data['subtitle'] as String? ?? '',
              amount: (data['amount'] as num?)?.toDouble(),
              currencyCode: data['currencyCode'] as String? ?? 'SLE',
              timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
              referenceId: data['referenceId'] as String?,
            );
          }).toList(),
        );
  }

  @override
  Stream<List<ProductStockPreview>> watchLowStock({
    required String businessId,
    int limit = 5,
  }) {
    if (businessId.trim().isEmpty) {
      return Stream<List<ProductStockPreview>>.value(
        const <ProductStockPreview>[],
      );
    }
    return _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('products')
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) {
                final data = doc.data();
                return ProductStockPreview(
                  id: doc.id,
                  name: data['name'] as String? ?? 'Unnamed product',
                  quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
                  threshold:
                      (data['lowStockThreshold'] as num?)?.toDouble() ?? 0,
                  unit: data['unit'] as String? ?? 'units',
                );
              })
              .where((product) => product.isLowStock)
              .take(limit)
              .toList(),
        );
  }

  @override
  Stream<List<CustomerBalancePreview>> watchCustomerBalances({
    required String businessId,
    int limit = 5,
  }) {
    if (businessId.trim().isEmpty) {
      return Stream<List<CustomerBalancePreview>>.value(
        const <CustomerBalancePreview>[],
      );
    }
    return _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('customers')
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) {
                final data = doc.data();
                return CustomerBalancePreview(
                  id: doc.id,
                  name: data['name'] as String? ?? 'Unnamed customer',
                  balance: (data['balance'] as num?)?.toDouble() ?? 0,
                  currencyCode: data['currencyCode'] as String? ?? 'SLE',
                );
              })
              .where((customer) => customer.balance > 0)
              .take(limit)
              .toList(),
        );
  }

  void _log(String operation, FirebaseException error, StackTrace stackTrace) {
    if (!kDebugMode) return;
    debugPrint('Dashboard $operation failed: ${error.code} ${error.message}');
    debugPrint('$stackTrace');
  }
}
