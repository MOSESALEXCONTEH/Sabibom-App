import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sabibom/core/formatting/currency_formatter.dart';
import 'package:sabibom/core/formatting/date_range_utils.dart';
import 'package:sabibom/features/dashboard/application/dashboard_providers.dart';
import 'package:sabibom/features/dashboard/domain/dashboard_models.dart';
import 'package:sabibom/features/dashboard/presentation/dashboard_screen.dart'
    as dashboard;

void main() {
  group('dashboard greeting', () {
    test('uses time-based greeting and first name', () {
      expect(
        dashboard.dashboardGreeting(DateTime(2026, 7, 17, 9), 'Amara Conteh'),
        'Good morning, Amara',
      );
      expect(
        dashboard.dashboardGreeting(DateTime(2026, 7, 17, 14), 'Amara Conteh'),
        'Good afternoon, Amara',
      );
      expect(
        dashboard.dashboardGreeting(DateTime(2026, 7, 17, 18), null),
        'Good evening',
      );
    });
  });

  group('currency formatting', () {
    test('formats SLE with two decimal places', () {
      expect(formatCurrency(0), 'Le 0.00');
      expect(formatCurrency(12.5), 'Le 12.50');
    });

    test('handles null safely', () {
      expect(formatCurrency(null), 'Le 0.00');
    });
  });

  group('dashboard date ranges', () {
    test('today starts at local midnight and ends next midnight', () {
      final range = dashboardDateRange(
        DashboardPeriod.today,
        now: DateTime(2026, 7, 17, 15, 30),
      );
      expect(range.start, DateTime(2026, 7, 17));
      expect(range.end, DateTime(2026, 7, 18));
    });

    test('week begins on Monday', () {
      final range = dashboardDateRange(
        DashboardPeriod.week,
        now: DateTime(2026, 7, 19),
      );
      expect(range.start, DateTime(2026, 7, 13));
      expect(range.end, DateTime(2026, 7, 20));
    });

    test('month uses first day boundaries', () {
      final range = dashboardDateRange(
        DashboardPeriod.month,
        now: DateTime(2026, 7, 17),
      );
      expect(range.start, DateTime(2026, 7));
      expect(range.end, DateTime(2026, 8));
    });

    test('year uses calendar year boundaries', () {
      final range = dashboardDateRange(
        DashboardPeriod.year,
        now: DateTime(2026, 8, 3, 14),
      );
      expect(range.start, DateTime(2026));
      expect(range.end, DateTime(2027));
    });
  });

  test('never treats null or whitespace as an active business ID', () {
    expect(hasUsableBusinessId(null), isFalse);
    expect(hasUsableBusinessId('   '), isFalse);
    expect(hasUsableBusinessId('business-123'), isTrue);
  });

  test('low stock is inclusive of the configured threshold', () {
    const product = ProductStockPreview(
      id: 'rice',
      name: 'Rice',
      quantity: 5,
      threshold: 5,
      unit: 'bags',
    );
    expect(product.isLowStock, isTrue);
  });

  group('active dashboard layout widgets', () {
    Future<void> pumpDashboardWidget(
      WidgetTester tester,
      Widget child, {
      required Size size,
      required double textScale,
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(textScale),
              ),
              child: Scaffold(
                body: Padding(padding: const EdgeInsets.all(16), child: child),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('DashboardHeader fits on small and regular phone widths', (
      tester,
    ) async {
      for (final size in <Size>[const Size(360, 800), const Size(412, 915)]) {
        await pumpDashboardWidget(
          tester,
          const dashboard.DashboardHeader(name: 'Moses Kamara'),
          size: size,
          textScale: 1.0,
        );

        expect(find.byKey(const Key('dashboard-greeting')), findsOneWidget);
        expect(find.byTooltip('Notifications'), findsOneWidget);
        expect(find.byTooltip('Settings'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('DashboardHeader remains safe with large text', (tester) async {
      await pumpDashboardWidget(
        tester,
        const dashboard.DashboardHeader(name: 'Moses Kamara'),
        size: const Size(360, 800),
        textScale: 1.3,
      );

      expect(find.byTooltip('Notifications'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('DashboardMetricGrid fits all cards at normal and large text', (
      tester,
    ) async {
      final summary = DashboardSummary.empty(
        DateRange(start: DateTime(2026, 7, 17), end: DateTime(2026, 7, 18)),
      );

      for (final textScale in <double>[1.0, 1.3]) {
        await pumpDashboardWidget(
          tester,
          dashboard.DashboardMetricGrid(summary: summary),
          size: const Size(360, 800),
          textScale: textScale,
        );

        expect(find.text('Orders'), findsOneWidget);
        expect(find.text('Customers'), findsOneWidget);
        expect(find.text('Low Stock'), findsOneWidget);
        expect(find.text('Expenses'), findsOneWidget);
        expect(find.text('No orders yet'), findsOneWidget);
        expect(find.text('No customers yet'), findsOneWidget);
        expect(find.text('Stock looks good'), findsOneWidget);
        expect(find.text('No expenses yet'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });
}
