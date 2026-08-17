import '../../../core/formatting/date_range_utils.dart';
import 'dashboard_models.dart';

class DashboardSaleRecord {
  const DashboardSaleRecord({
    required this.createdAt,
    required this.total,
    required this.items,
  });

  final DateTime createdAt;
  final double total;
  final List<DashboardSaleLine> items;
}

class DashboardSaleLine {
  const DashboardSaleLine({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.total,
  });

  final String productId;
  final String name;
  final double quantity;
  final double total;
}

class DashboardProductImage {
  const DashboardProductImage({this.url, this.cid});

  final String? url;
  final String? cid;
}

List<DashboardSalesPoint> buildSalesTrend(
  List<DashboardSaleRecord> sales,
  DashboardPeriod period,
  DateRange range,
) {
  final bucketCount = switch (period) {
    DashboardPeriod.today => 6,
    DashboardPeriod.week => 7,
    DashboardPeriod.month => 6,
    DashboardPeriod.year => 12,
  };
  final totals = List<double>.filled(bucketCount, 0);
  for (final sale in sales) {
    final index = switch (period) {
      DashboardPeriod.today => (sale.createdAt.hour ~/ 4).clamp(0, 5),
      DashboardPeriod.week =>
        sale.createdAt.difference(range.start).inDays.clamp(0, 6),
      DashboardPeriod.month =>
        (((sale.createdAt.day - 1) * bucketCount) ~/
                range.end.difference(range.start).inDays)
            .clamp(0, bucketCount - 1),
      DashboardPeriod.year => sale.createdAt.month - 1,
    };
    totals[index] += sale.total;
  }
  return List<DashboardSalesPoint>.generate(bucketCount, (index) {
    final label = switch (period) {
      DashboardPeriod.today => '${index * 4}:00',
      DashboardPeriod.week => const <String>[
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ][index],
      DashboardPeriod.month => '${1 + ((index * 30) ~/ bucketCount)}',
      DashboardPeriod.year => const <String>[
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ][index],
    };
    return DashboardSalesPoint(label: label, total: totals[index]);
  });
}

List<DashboardTopProduct> buildTopProducts({
  required List<DashboardSaleRecord> currentSales,
  required List<DashboardSaleRecord> previousSales,
  Map<String, DashboardProductImage> images = const {},
  int limit = 5,
}) {
  final current = _aggregateProducts(currentSales);
  final previous = _aggregateProducts(previousSales);
  final totalProductSales = current.values.fold<double>(
    0,
    (total, product) => total + product.total,
  );
  final ranked = current.entries.toList()
    ..sort((a, b) => b.value.total.compareTo(a.value.total));
  return ranked
      .take(limit)
      .map((entry) {
        final previousTotal = previous[entry.key]?.total ?? 0;
        final change = previousTotal == 0
            ? null
            : ((entry.value.total - previousTotal) / previousTotal) * 100;
        final share = totalProductSales == 0
            ? 0.0
            : (entry.value.total / totalProductSales) * 100;
        final image = images[entry.key];
        return DashboardTopProduct(
          productId: entry.key,
          name: entry.value.name,
          salesTotal: entry.value.total,
          quantity: entry.value.quantity,
          scorePercent: change ?? share,
          changePercent: change,
          imageUrl: image?.url,
          imageCid: image?.cid,
        );
      })
      .toList(growable: false);
}

Map<String, _ProductTotal> _aggregateProducts(List<DashboardSaleRecord> sales) {
  final totals = <String, _ProductTotal>{};
  for (final sale in sales) {
    for (final item in sale.items) {
      final key = item.productId.trim().isEmpty
          ? 'custom:${item.name.trim().toLowerCase()}'
          : item.productId.trim();
      final existing = totals[key];
      totals[key] = _ProductTotal(
        name: item.name,
        total: (existing?.total ?? 0) + item.total,
        quantity: (existing?.quantity ?? 0) + item.quantity,
      );
    }
  }
  return totals;
}

class _ProductTotal {
  const _ProductTotal({
    required this.name,
    required this.total,
    required this.quantity,
  });

  final String name;
  final double total;
  final double quantity;
}

class BusinessHealthScore {
  const BusinessHealthScore({
    required this.overall,
    required this.salesPerformance,
    required this.inventoryManagement,
    required this.cashFlow,
    required this.customerEngagement,
    required this.expenseControl,
    required this.growthPotential,
    required this.insight,
    required this.recommendations,
  });

  factory BusinessHealthScore.fromSummary(DashboardSummary summary) {
    double clamp(double value) => value.clamp(0, 100).toDouble();
    final change = summary.salesChangePercent;
    final sales = clamp(change == null ? 75 : 60 + change);
    final inventory = summary.trackedProductCount == 0
        ? 70.0
        : clamp(
            100 - ((summary.lowStockCount / summary.trackedProductCount) * 100),
          );
    final expenseRatio = summary.totalSales == 0
        ? (summary.totalExpenses == 0 ? 0.0 : 1.0)
        : summary.totalExpenses / summary.totalSales;
    final expenses = clamp(100 - (expenseRatio * 100));
    final cash = clamp(
      90 -
          (expenseRatio * 45) -
          (summary.totalSales == 0
              ? 20
              : (summary.outstandingBalance / summary.totalSales) * 25),
    );
    final customers = clamp(
      45 + summary.customerCount * 3 + summary.orderCount * 1.5,
    );
    final growth = clamp((sales * 0.55) + (customers * 0.45));
    final overall =
        ((sales + inventory + cash + customers + expenses + growth) / 6)
            .round();
    final recommendations = <String>[];
    if (summary.lowStockCount > 0) {
      recommendations.add(
        'Restock ${summary.lowStockCount} low-stock ${summary.lowStockCount == 1 ? 'item' : 'items'}.',
      );
    }
    if (expenseRatio > 0.65) {
      recommendations.add('Review expenses that are reducing operating cash.');
    }
    if (summary.outstandingBalance > 0) {
      recommendations.add('Follow up on outstanding customer balances.');
    }
    if ((change ?? 0) < 0) {
      recommendations.add(
        'Review declining sales and re-engage recent customers.',
      );
    }
    if (recommendations.isEmpty) {
      recommendations.add(
        'Keep monitoring sales and stock as the business grows.',
      );
    }
    final insight = change == null
        ? 'This is your first comparable sales period. Keep recording activity to strengthen the score.'
        : change >= 0
        ? 'Sales are up ${change.abs().toStringAsFixed(1)}% from the previous period.'
        : 'Sales are down ${change.abs().toStringAsFixed(1)}% from the previous period.';
    return BusinessHealthScore(
      overall: overall,
      salesPerformance: sales.round(),
      inventoryManagement: inventory.round(),
      cashFlow: cash.round(),
      customerEngagement: customers.round(),
      expenseControl: expenses.round(),
      growthPotential: growth.round(),
      insight: insight,
      recommendations: recommendations.take(3).toList(growable: false),
    );
  }

  final int overall;
  final int salesPerformance;
  final int inventoryManagement;
  final int cashFlow;
  final int customerEngagement;
  final int expenseControl;
  final int growthPotential;
  final String insight;
  final List<String> recommendations;

  String get rating => switch (overall) {
    >= 85 => 'Excellent',
    >= 70 => 'Healthy',
    >= 50 => 'Needs attention',
    _ => 'At risk',
  };
}
