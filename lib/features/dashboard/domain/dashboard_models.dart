import '../../../core/formatting/date_range_utils.dart';

class DashboardSummary {
  const DashboardSummary({
    required this.totalSales,
    required this.previousTotalSales,
    required this.totalExpenses,
    required this.orderCount,
    required this.customerCount,
    required this.lowStockCount,
    required this.outstandingBalance,
    required this.periodStart,
    required this.periodEnd,
    required this.currencyCode,
    required this.currencySymbol,
    this.salesTrend = const <DashboardSalesPoint>[],
    this.topProducts = const <DashboardTopProduct>[],
    this.trackedProductCount = 0,
  });

  factory DashboardSummary.empty(
    DateRange range, {
    String code = 'SLE',
    String symbol = 'Le',
  }) => DashboardSummary(
    totalSales: 0,
    previousTotalSales: 0,
    totalExpenses: 0,
    orderCount: 0,
    customerCount: 0,
    lowStockCount: 0,
    outstandingBalance: 0,
    periodStart: range.start,
    periodEnd: range.end,
    currencyCode: code,
    currencySymbol: symbol,
  );

  final double totalSales;
  final double previousTotalSales;
  final double totalExpenses;
  final int orderCount;
  final int customerCount;
  final int lowStockCount;
  final double outstandingBalance;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String currencyCode;
  final String currencySymbol;
  final List<DashboardSalesPoint> salesTrend;
  final List<DashboardTopProduct> topProducts;
  final int trackedProductCount;

  double? get salesChangePercent {
    if (previousTotalSales == 0) return totalSales == 0 ? 0 : null;
    return ((totalSales - previousTotalSales) / previousTotalSales) * 100;
  }
}

class DashboardSalesPoint {
  const DashboardSalesPoint({required this.label, required this.total});

  final String label;
  final double total;
}

class DashboardTopProduct {
  const DashboardTopProduct({
    required this.productId,
    required this.name,
    required this.salesTotal,
    required this.quantity,
    required this.scorePercent,
    this.changePercent,
    this.imageUrl,
    this.imageCid,
  });

  final String productId;
  final String name;
  final double salesTotal;
  final double quantity;
  final double scorePercent;
  final double? changePercent;
  final String? imageUrl;
  final String? imageCid;
}

enum DashboardActivityType {
  sale,
  expense,
  customerPayment,
  productAdded,
  stockAdjustment,
  other,
}

class DashboardActivity {
  const DashboardActivity({
    required this.id,
    required this.businessId,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.currencyCode,
    required this.timestamp,
    this.referenceId,
  });

  final String id;
  final String businessId;
  final DashboardActivityType type;
  final String title;
  final String subtitle;
  final double? amount;
  final String currencyCode;
  final DateTime? timestamp;
  final String? referenceId;
}

class ProductStockPreview {
  const ProductStockPreview({
    required this.id,
    required this.name,
    required this.quantity,
    required this.threshold,
    required this.unit,
  });

  final String id;
  final String name;
  final double quantity;
  final double threshold;
  final String unit;

  bool get isLowStock => quantity <= threshold;
}

class CustomerBalancePreview {
  const CustomerBalancePreview({
    required this.id,
    required this.name,
    required this.balance,
    required this.currencyCode,
  });

  final String id;
  final String name;
  final double balance;
  final String currencyCode;
}
