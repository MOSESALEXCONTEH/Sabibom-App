import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firestore/query_pagination.dart';
import '../../branches/domain/business_branch.dart';
import '../../customers/domain/customer.dart';
import '../../expenses/domain/expense.dart';
import '../../inventory/domain/inventory_batch.dart';
import '../../products/domain/product.dart';
import '../../sales/domain/sale.dart';
import '../../suppliers/domain/supplier.dart';
import '../domain/balance_report_models.dart';
import '../domain/product_intelligence_report_models.dart';
import '../domain/profit_calculator.dart';
import '../domain/profit_models.dart';

class ReportPeriodData {
  const ReportPeriodData({
    required this.summary,
    required this.sales,
    required this.expenses,
    required this.suppliers,
  });

  final ProfitPeriodSummary summary;
  final List<Sale> sales;
  final List<Expense> expenses;
  final List<Supplier> suppliers;
}

class ReportsRepository {
  ReportsRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<ReportPeriodData> loadProfitLoss(
    String businessId, {
    required DateTime start,
    required DateTime end,
    String? branchId,
  }) async {
    if (businessId.trim().isEmpty) {
      return ReportPeriodData(
        summary: ProfitPeriodSummary.unavailable('Select a business first.'),
        sales: const [],
        expenses: const [],
        suppliers: const [],
      );
    }

    final business = _firestore.collection('businesses').doc(businessId);
    try {
      final results = await Future.wait([
        business
            .collection('sales')
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(start),
            )
            .where('createdAt', isLessThan: Timestamp.fromDate(end))
            .get(),
        business
            .collection('expenses')
            .where(
              'expenseDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(start),
            )
            .where('expenseDate', isLessThan: Timestamp.fromDate(end))
            .get(),
        business.collection('products').get(),
        business.collection('suppliers').get(),
        business.collection('customers').get(),
      ]);
      final sales = results[0].docs
          .where((doc) => matchesBranchScope(doc.data(), branchId))
          .map(Sale.fromFirestore)
          .toList();
      final expenses = results[1].docs
          .where((doc) => matchesBranchScope(doc.data(), branchId))
          .map(Expense.fromFirestore)
          .toList();
      final products = results[2].docs
          .where((doc) => matchesBranchScope(doc.data(), branchId))
          .map(Product.fromFirestore)
          .toList();
      final suppliers = results[3].docs
          .where((doc) => matchesBranchScope(doc.data(), branchId))
          .map(Supplier.fromFirestore)
          .toList();
      final customers = results[4].docs
          .where((doc) => matchesBranchScope(doc.data(), branchId))
          .map(Customer.fromFirestore)
          .toList();

      return ReportPeriodData(
        summary: ProfitCalculator.calculate(
          sales: sales,
          expenses: expenses,
          products: products,
          suppliers: suppliers,
          customers: customers,
        ),
        sales: sales,
        expenses: expenses,
        suppliers: suppliers,
      );
    } on FirebaseException catch (error) {
      return ReportPeriodData(
        summary: ProfitPeriodSummary.unavailable(
          error.code == 'permission-denied'
              ? 'You do not have permission to view reports.'
              : 'Report data is currently unavailable. Please try again.',
        ),
        sales: const [],
        expenses: const [],
        suppliers: const [],
      );
    }
  }

  Future<InventoryValuationReport> loadInventoryValuation(
    String businessId, {
    String? branchId,
  }) async {
    if (businessId.trim().isEmpty) {
      return const InventoryValuationReport(
        rows: [],
        totalValueMinor: 0,
        trackedProductCount: 0,
        lowStockCount: 0,
        outOfStockCount: 0,
        lowStockValueMinor: 0,
      );
    }
    final docs = await readAllQueryPages(
      _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('products'),
    );
    final products = docs
        .where((doc) => matchesBranchScope(doc.data(), branchId))
        .map(Product.fromFirestore)
        .toList();
    return InventoryValuationReport.fromProducts(products);
  }

  Future<CustomerBalanceReport> loadCustomerBalances(
    String businessId, {
    String? branchId,
  }) async {
    if (businessId.trim().isEmpty) {
      return const CustomerBalanceReport(
        customers: [],
        totalDebtMinor: 0,
        owingCount: 0,
      );
    }
    final docs = await readAllQueryPages(
      _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('customers'),
    );
    final customers = docs
        .where((doc) => matchesBranchScope(doc.data(), branchId))
        .map(Customer.fromFirestore)
        .toList();
    return CustomerBalanceReport.fromCustomers(customers);
  }

  Future<SupplierBalanceReport> loadSupplierBalances(
    String businessId, {
    String? branchId,
  }) async {
    if (businessId.trim().isEmpty) {
      return const SupplierBalanceReport(
        suppliers: [],
        totalDebtMinor: 0,
        owingCount: 0,
      );
    }
    final docs = await readAllQueryPages(
      _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('suppliers'),
    );
    final suppliers = docs
        .where((doc) => matchesBranchScope(doc.data(), branchId))
        .map(Supplier.fromFirestore)
        .toList();
    return SupplierBalanceReport.fromSuppliers(suppliers);
  }

  Future<ProductProfitReport> loadProductProfit(
    String businessId, {
    required DateTime start,
    required DateTime end,
    String? branchId,
    String? categoryId,
    bool inStockOnly = false,
    ProductProfitSort sort = ProductProfitSort.realizedProfitDesc,
  }) async {
    if (businessId.trim().isEmpty) {
      return const ProductProfitReport(
        rows: [],
        totalRealizedGrossProfitMinor: 0,
        totalPotentialProfitRemainingMinor: 0,
        totalProjectedGrossProfitMinor: 0,
        totalQuantitySold: 0,
        anyEstimated: false,
      );
    }
    final business = _firestore.collection('businesses').doc(businessId);
    final results = await Future.wait([
      readAllQueryPages(business.collection('products')),
      readAllQueryPages(
        business
            .collection('sales')
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(start),
            )
            .where('createdAt', isLessThan: Timestamp.fromDate(end)),
      ),
    ]);
    final products = results[0]
        .where((doc) => matchesBranchScope(doc.data(), branchId))
        .map(Product.fromFirestore)
        .toList();
    final sales = results[1]
        .where((doc) => matchesBranchScope(doc.data(), branchId))
        .map(Sale.fromFirestore)
        .toList();
    return ProductProfitReport.fromProductsAndSales(
      products: products,
      sales: sales,
      categoryId: categoryId,
      inStockOnly: inStockOnly,
      sort: sort,
    );
  }

  Future<ProductExpiryReport> loadProductExpiry(
    String businessId, {
    required DateTime now,
    required String businessTimezone,
    String? branchId,
    String? categoryId,
    ProductExpiryStatus? statusFilter,
    ExpiryReportSort sort = ExpiryReportSort.expiryDateAsc,
    int reminderThresholdDays = 30,
  }) async {
    if (businessId.trim().isEmpty) {
      return const ProductExpiryReport(
        sections: [],
        totalExpiredCostMinor: 0,
        totalExpiringQuantity: 0,
        totalExpiredQuantity: 0,
        totalUnknownQuantity: 0,
      );
    }
    final business = _firestore.collection('businesses').doc(businessId);
    final results = await Future.wait([
      readAllQueryPages(business.collection('products')),
      readAllQueryPages(
        business
            .collection('inventory_batches')
            .where('status', whereIn: const <String>['active', 'expired'])
            .orderBy('expiryDate'),
      ),
    ]);
    final products = results[0]
        .where((doc) => matchesBranchScope(doc.data(), branchId))
        .map(Product.fromFirestore)
        .toList();
    final batches = results[1]
        .where((doc) => matchesBranchScope(doc.data(), branchId))
        .map(InventoryBatch.fromFirestore)
        .toList();
    return ProductExpiryReport.fromProductsAndBatches(
      products: products,
      batches: batches,
      now: now,
      businessTimezone: businessTimezone,
      categoryId: categoryId,
      statusFilter: statusFilter,
      sort: sort,
      reminderThresholdDays: reminderThresholdDays,
    );
  }
}
