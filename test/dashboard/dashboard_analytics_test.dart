import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/core/formatting/date_range_utils.dart';
import 'package:sabibom/features/dashboard/domain/dashboard_analytics.dart';
import 'package:sabibom/features/dashboard/domain/dashboard_models.dart';

void main() {
  test('previous month uses calendar boundaries', () {
    final range = previousDashboardDateRange(
      DashboardPeriod.month,
      now: DateTime(2026, 3, 18),
    );
    expect(range.start, DateTime(2026, 2));
    expect(range.end, DateTime(2026, 3));
  });

  test('sales trend groups branch-filtered records into period buckets', () {
    final range = DateRange(
      start: DateTime(2026, 8, 10),
      end: DateTime(2026, 8, 17),
    );
    final points = buildSalesTrend(
      <DashboardSaleRecord>[
        _sale(DateTime(2026, 8, 10), 100),
        _sale(DateTime(2026, 8, 10, 15), 50),
        _sale(DateTime(2026, 8, 12), 75),
      ],
      DashboardPeriod.week,
      range,
    );
    expect(points, hasLength(7));
    expect(points[0].total, 150);
    expect(points[2].total, 75);
  });

  test('top products rank actual line totals and compare previous period', () {
    final products = buildTopProducts(
      currentSales: <DashboardSaleRecord>[
        _sale(
          DateTime(2026, 8, 16),
          300,
          items: const <DashboardSaleLine>[
            DashboardSaleLine(
              productId: 'rice',
              name: 'Rice',
              quantity: 2,
              total: 200,
            ),
            DashboardSaleLine(
              productId: 'soap',
              name: 'Soap',
              quantity: 1,
              total: 100,
            ),
          ],
        ),
      ],
      previousSales: <DashboardSaleRecord>[
        _sale(
          DateTime(2026, 8, 9),
          100,
          items: const <DashboardSaleLine>[
            DashboardSaleLine(
              productId: 'rice',
              name: 'Rice',
              quantity: 1,
              total: 100,
            ),
          ],
        ),
      ],
    );
    expect(products.first.name, 'Rice');
    expect(products.first.salesTotal, 200);
    expect(products.first.changePercent, 100);
    expect(products.first.scorePercent, 100);
  });

  test('business health score reacts to real risk signals', () {
    final healthy = BusinessHealthScore.fromSummary(_summary());
    final atRisk = BusinessHealthScore.fromSummary(
      _summary(
        totalSales: 100,
        previousSales: 500,
        expenses: 90,
        lowStock: 8,
        trackedProducts: 10,
        outstanding: 100,
      ),
    );
    expect(healthy.overall, greaterThan(atRisk.overall));
    expect(
      atRisk.recommendations,
      contains('Review expenses that are reducing operating cash.'),
    );
  });
}

DashboardSaleRecord _sale(
  DateTime createdAt,
  double total, {
  List<DashboardSaleLine> items = const <DashboardSaleLine>[],
}) => DashboardSaleRecord(createdAt: createdAt, total: total, items: items);

DashboardSummary _summary({
  double totalSales = 1000,
  double previousSales = 800,
  double expenses = 200,
  int lowStock = 1,
  int trackedProducts = 10,
  double outstanding = 0,
}) => DashboardSummary(
  totalSales: totalSales,
  previousTotalSales: previousSales,
  totalExpenses: expenses,
  orderCount: 12,
  customerCount: 8,
  lowStockCount: lowStock,
  outstandingBalance: outstanding,
  trackedProductCount: trackedProducts,
  periodStart: DateTime(2026, 8),
  periodEnd: DateTime(2026, 9),
  currencyCode: 'SLE',
  currencySymbol: 'Le',
);
