import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../branches/application/current_branch_providers.dart';
import '../../products/domain/product.dart';
import '../data/reports_repository.dart';
import '../domain/balance_report_models.dart';
import '../domain/product_intelligence_report_models.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(),
);

class ProfitReportRequest {
  const ProfitReportRequest({
    required this.businessId,
    required this.start,
    required this.end,
    this.branchId,
  });

  final String businessId;
  final DateTime start;
  final DateTime end;
  final String? branchId;

  @override
  bool operator ==(Object other) =>
      other is ProfitReportRequest &&
      other.businessId == businessId &&
      other.start == start &&
      other.end == end &&
      other.branchId == branchId;

  @override
  int get hashCode => Object.hash(businessId, start, end, branchId);
}

final profitReportProvider =
    FutureProvider.family<ReportPeriodData, ProfitReportRequest>((
      ref,
      request,
    ) {
      final branchId = ref.watch(currentBranchReadScopeProvider);
      return ref
          .watch(reportsRepositoryProvider)
          .loadProfitLoss(
            request.businessId,
            start: request.start,
            end: request.end,
            branchId: branchId,
          );
    });

final inventoryValuationProvider =
    FutureProvider.family<InventoryValuationReport, String>(
      (ref, businessId) => ref
          .watch(currentBranchProvider)
          .when(
            data: (_) => ref
                .watch(reportsRepositoryProvider)
                .loadInventoryValuation(
                  businessId,
                  branchId: ref.watch(currentBranchReadScopeProvider),
                ),
            loading: () => const InventoryValuationReport(
              rows: [],
              totalValueMinor: 0,
              trackedProductCount: 0,
              lowStockCount: 0,
              outOfStockCount: 0,
              lowStockValueMinor: 0,
            ),
            error: (_, _) => const InventoryValuationReport(
              rows: [],
              totalValueMinor: 0,
              trackedProductCount: 0,
              lowStockCount: 0,
              outOfStockCount: 0,
              lowStockValueMinor: 0,
            ),
          ),
    );

final customerBalancesReportProvider =
    FutureProvider.family<CustomerBalanceReport, String>(
      (ref, businessId) => ref
          .watch(currentBranchProvider)
          .when(
            data: (_) => ref
                .watch(reportsRepositoryProvider)
                .loadCustomerBalances(
                  businessId,
                  branchId: ref.watch(currentBranchReadScopeProvider),
                ),
            loading: () => const CustomerBalanceReport(
              customers: [],
              totalDebtMinor: 0,
              owingCount: 0,
            ),
            error: (_, _) => const CustomerBalanceReport(
              customers: [],
              totalDebtMinor: 0,
              owingCount: 0,
            ),
          ),
    );

final supplierBalancesReportProvider =
    FutureProvider.family<SupplierBalanceReport, String>(
      (ref, businessId) => ref
          .watch(currentBranchProvider)
          .when(
            data: (_) => ref
                .watch(reportsRepositoryProvider)
                .loadSupplierBalances(
                  businessId,
                  branchId: ref.watch(currentBranchReadScopeProvider),
                ),
            loading: () => const SupplierBalanceReport(
              suppliers: [],
              totalDebtMinor: 0,
              owingCount: 0,
            ),
            error: (_, _) => const SupplierBalanceReport(
              suppliers: [],
              totalDebtMinor: 0,
              owingCount: 0,
            ),
          ),
    );

class ProductProfitReportRequest {
  const ProductProfitReportRequest({
    required this.businessId,
    required this.start,
    required this.end,
    this.branchId,
    this.categoryId,
    this.inStockOnly = false,
    this.sort = ProductProfitSort.realizedProfitDesc,
  });

  final String businessId;
  final DateTime start;
  final DateTime end;
  final String? branchId;
  final String? categoryId;
  final bool inStockOnly;
  final ProductProfitSort sort;

  @override
  bool operator ==(Object other) =>
      other is ProductProfitReportRequest &&
      other.businessId == businessId &&
      other.start == start &&
      other.end == end &&
      other.branchId == branchId &&
      other.categoryId == categoryId &&
      other.inStockOnly == inStockOnly &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
    businessId,
    start,
    end,
    branchId,
    categoryId,
    inStockOnly,
    sort,
  );
}

final productProfitReportProvider =
    FutureProvider.family<ProductProfitReport, ProductProfitReportRequest>((
      ref,
      request,
    ) {
      final branchId = ref.watch(currentBranchReadScopeProvider);
      return ref
          .watch(reportsRepositoryProvider)
          .loadProductProfit(
            request.businessId,
            start: request.start,
            end: request.end,
            branchId: branchId,
            categoryId: request.categoryId,
            inStockOnly: request.inStockOnly,
            sort: request.sort,
          );
    });

class ProductExpiryReportRequest {
  const ProductExpiryReportRequest({
    required this.businessId,
    required this.businessTimezone,
    this.branchId,
    this.categoryId,
    this.statusFilter,
    this.sort = ExpiryReportSort.expiryDateAsc,
    this.reminderThresholdDays = 30,
  });

  final String businessId;
  final String businessTimezone;
  final String? branchId;
  final String? categoryId;
  final ProductExpiryStatus? statusFilter;
  final ExpiryReportSort sort;
  final int reminderThresholdDays;

  @override
  bool operator ==(Object other) =>
      other is ProductExpiryReportRequest &&
      other.businessId == businessId &&
      other.businessTimezone == businessTimezone &&
      other.branchId == branchId &&
      other.categoryId == categoryId &&
      other.statusFilter == statusFilter &&
      other.sort == sort &&
      other.reminderThresholdDays == reminderThresholdDays;

  @override
  int get hashCode => Object.hash(
    businessId,
    businessTimezone,
    branchId,
    categoryId,
    statusFilter,
    sort,
    reminderThresholdDays,
  );
}

final productExpiryReportProvider =
    FutureProvider.family<ProductExpiryReport, ProductExpiryReportRequest>((
      ref,
      request,
    ) {
      final branchId = ref.watch(currentBranchReadScopeProvider);
      return ref
          .watch(reportsRepositoryProvider)
          .loadProductExpiry(
            request.businessId,
            now: DateTime.now().toUtc(),
            businessTimezone: request.businessTimezone,
            branchId: branchId,
            categoryId: request.categoryId,
            statusFilter: request.statusFilter,
            sort: request.sort,
            reminderThresholdDays: request.reminderThresholdDays,
          );
    });
