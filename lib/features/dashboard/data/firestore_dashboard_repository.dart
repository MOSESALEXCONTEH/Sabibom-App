import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/firestore/query_pagination.dart';
import '../../../core/formatting/date_range_utils.dart';
import '../../branches/domain/business_branch.dart';
import '../domain/dashboard_analytics.dart';
import '../domain/dashboard_models.dart';
import 'dashboard_repository.dart';

class FirestoreDashboardRepository implements DashboardRepository {
  FirestoreDashboardRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  bool _isCompletedSale(Map<String, dynamic> data) {
    final status =
        (data['saleStatus'] as String?) ??
        (data['status'] as String?) ??
        'completed';
    return status == 'completed';
  }

  bool _isActiveExpense(Map<String, dynamic> data) {
    final status = data['status'] as String? ?? 'active';
    return status != 'voided' && status != 'cancelled';
  }

  bool _inRange(DateTime? value, DateRange range) {
    if (value == null) return false;
    return !value.isBefore(range.start) && value.isBefore(range.end);
  }

  DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  @override
  Future<DashboardSummary> getSummary({
    required String businessId,
    required DashboardPeriod period,
    required String currencyCode,
    required String currencySymbol,
    String? branchId,
  }) async {
    final range = dashboardDateRange(period);
    final previousRange = previousDashboardDateRange(period);
    final empty = DashboardSummary.empty(
      range,
      code: currencyCode,
      symbol: currencySymbol,
    );
    if (businessId.trim().isEmpty) return empty;
    try {
      final business = _firestore.collection('businesses').doc(businessId);
      // Fetch recent docs and filter in memory so we can match sales by
      // createdAt and expenses by expenseDate (business date) without
      // requiring extra composite indexes.
      final results = await Future.wait([
        readAllQueryPages(
          business
              .collection('sales')
              .where(
                'createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(previousRange.start),
              )
              .where('createdAt', isLessThan: Timestamp.fromDate(range.end)),
        ),
        readAllQueryPages(
          business
              .collection('expenses')
              .where(
                'expenseDate',
                isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
              )
              .where('expenseDate', isLessThan: Timestamp.fromDate(range.end)),
        ),
        readAllQueryPages(business.collection('customers')),
        readAllQueryPages(business.collection('products')),
      ]);
      return _buildSummary(
        salesDocuments: results[0],
        expenseDocuments: results[1],
        customerDocuments: results[2],
        productDocuments: results[3],
        period: period,
        range: range,
        previousRange: previousRange,
        currencyCode: currencyCode,
        currencySymbol: currencySymbol,
        branchId: branchId,
      );
    } on FirebaseException catch (error, stackTrace) {
      _log('getSummary', error, stackTrace);
      // expenseDate index may be missing on older projects — fall back.
      if (error.code == 'failed-precondition') {
        return _getSummaryFallback(
          businessId: businessId,
          period: period,
          range: range,
          previousRange: previousRange,
          currencyCode: currencyCode,
          currencySymbol: currencySymbol,
          branchId: branchId,
        );
      }
      rethrow;
    }
  }

  Future<DashboardSummary> _getSummaryFallback({
    required String businessId,
    required DashboardPeriod period,
    required DateRange range,
    required DateRange previousRange,
    required String currencyCode,
    required String currencySymbol,
    String? branchId,
  }) async {
    final business = _firestore.collection('businesses').doc(businessId);
    final results = await Future.wait([
      readAllQueryPages(business.collection('sales')),
      readAllQueryPages(business.collection('expenses')),
      readAllQueryPages(business.collection('customers')),
      readAllQueryPages(business.collection('products')),
    ]);
    return _buildSummary(
      salesDocuments: results[0],
      expenseDocuments: results[1],
      customerDocuments: results[2],
      productDocuments: results[3],
      period: period,
      range: range,
      previousRange: previousRange,
      currencyCode: currencyCode,
      currencySymbol: currencySymbol,
      branchId: branchId,
    );
  }

  DashboardSummary _buildSummary({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> salesDocuments,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> expenseDocuments,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>>
    customerDocuments,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> productDocuments,
    required DashboardPeriod period,
    required DateRange range,
    required DateRange previousRange,
    required String currencyCode,
    required String currencySymbol,
    String? branchId,
  }) {
    final eligibleSales = salesDocuments.where((doc) {
      final data = doc.data();
      return _isCompletedSale(data) && matchesBranchScope(data, branchId);
    });
    final currentSales = eligibleSales
        .map((doc) => _saleRecord(doc.data()))
        .whereType<DashboardSaleRecord>()
        .where((sale) => _inRange(sale.createdAt, range))
        .toList(growable: false);
    final previousSales = eligibleSales
        .map((doc) => _saleRecord(doc.data()))
        .whereType<DashboardSaleRecord>()
        .where((sale) => _inRange(sale.createdAt, previousRange))
        .toList(growable: false);
    final expenses = expenseDocuments
        .where((doc) {
          final data = doc.data();
          if (!_isActiveExpense(data) || !matchesBranchScope(data, branchId)) {
            return false;
          }
          return _inRange(
            _asDate(data['expenseDate']) ?? _asDate(data['createdAt']),
            range,
          );
        })
        .toList(growable: false);
    final customers = customerDocuments
        .where((doc) {
          final data = doc.data();
          return matchesBranchScope(data, branchId) &&
              (data['status'] as String? ?? 'active') == 'active';
        })
        .toList(growable: false);
    final products = productDocuments
        .where((doc) {
          final data = doc.data();
          return matchesBranchScope(data, branchId) &&
              (data['status'] as String? ?? 'active') == 'active';
        })
        .toList(growable: false);
    final trackedProducts = products.where(
      (doc) => doc.data()['trackStock'] as bool? ?? true,
    );
    final images = <String, DashboardProductImage>{};
    for (final doc in productDocuments) {
      final image = DashboardProductImage(
        url: doc.data()['imageUrl'] as String?,
        cid: doc.data()['imageCid'] as String?,
      );
      images[doc.id] = image;
      final storedProductId = (doc.data()['productId'] as String?)?.trim();
      if (storedProductId != null && storedProductId.isNotEmpty) {
        images[storedProductId] = image;
      }
    }
    final totalSales = currentSales.fold<double>(
      0,
      (total, sale) => total + sale.total,
    );
    return DashboardSummary(
      totalSales: totalSales,
      previousTotalSales: previousSales.fold<double>(
        0,
        (total, sale) => total + sale.total,
      ),
      totalExpenses: expenses.fold<double>(0, (total, doc) {
        final data = doc.data();
        final minor = (data['amountMinor'] as num?)?.toInt();
        return total +
            (minor == null
                ? ((data['amount'] as num?)?.toDouble() ?? 0)
                : minor / 100);
      }),
      orderCount: currentSales.length,
      customerCount: customers.length,
      lowStockCount: trackedProducts.where((doc) {
        final data = doc.data();
        final quantity = (data['quantity'] as num?)?.toDouble() ?? 0;
        final threshold = (data['lowStockThreshold'] as num?)?.toDouble() ?? 0;
        return quantity <= threshold;
      }).length,
      trackedProductCount: trackedProducts.length,
      outstandingBalance: customers.fold<double>(0, (total, doc) {
        final data = doc.data();
        final minor = (data['balanceMinor'] as num?)?.toInt();
        return total +
            (minor == null
                ? ((data['balance'] as num?)?.toDouble() ?? 0)
                : minor / 100);
      }),
      periodStart: range.start,
      periodEnd: range.end,
      currencyCode: currencyCode,
      currencySymbol: currencySymbol,
      salesTrend: buildSalesTrend(currentSales, period, range),
      topProducts: buildTopProducts(
        currentSales: currentSales,
        previousSales: previousSales,
        images: images,
      ),
    );
  }

  DashboardSaleRecord? _saleRecord(Map<String, dynamic> data) {
    final createdAt = _asDate(data['createdAt']);
    if (createdAt == null) return null;
    final total =
        (data['total'] as num?)?.toDouble() ??
        (((data['totalMinor'] as num?)?.toInt() ?? 0) / 100);
    final rawItems = data['items'] as List<dynamic>? ?? const <dynamic>[];
    return DashboardSaleRecord(
      createdAt: createdAt,
      total: total,
      items: rawItems
          .whereType<Map>()
          .map((raw) {
            final item = Map<String, dynamic>.from(raw);
            return DashboardSaleLine(
              productId: item['productId'] as String? ?? '',
              name: item['name'] as String? ?? 'Item',
              quantity: (item['quantity'] as num?)?.toDouble() ?? 0,
              total:
                  (item['lineTotal'] as num?)?.toDouble() ??
                  (((item['lineTotalMinor'] as num?)?.toInt() ?? 0) / 100),
            );
          })
          .toList(growable: false),
    );
  }

  @override
  Stream<List<DashboardActivity>> watchRecentActivity({
    required String businessId,
    String? branchId,
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
          (snapshot) => snapshot.docs
              .where((doc) => matchesBranchScope(doc.data(), branchId))
              .map((doc) {
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
              })
              .toList(),
        );
  }

  @override
  Stream<List<ProductStockPreview>> watchLowStock({
    required String businessId,
    String? branchId,
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
              .where((doc) => matchesBranchScope(doc.data(), branchId))
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
    String? branchId,
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
              .where((doc) => matchesBranchScope(doc.data(), branchId))
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
