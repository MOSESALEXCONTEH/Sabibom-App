import '../../../core/formatting/date_range_utils.dart';
import '../domain/dashboard_models.dart';

abstract class DashboardRepository {
  Future<DashboardSummary> getSummary({
    required String businessId,
    required DashboardPeriod period,
    required String currencyCode,
    required String currencySymbol,
    String? branchId,
  });

  Stream<List<DashboardActivity>> watchRecentActivity({
    required String businessId,
    String? branchId,
    int limit = 5,
  });

  Stream<List<ProductStockPreview>> watchLowStock({
    required String businessId,
    String? branchId,
    int limit = 5,
  });

  Stream<List<CustomerBalancePreview>> watchCustomerBalances({
    required String businessId,
    String? branchId,
    int limit = 5,
  });
}
