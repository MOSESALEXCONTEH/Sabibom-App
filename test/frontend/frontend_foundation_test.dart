import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/app/theme.dart';
import 'package:sabibom/app/widgets/modern_bottom_navigation.dart';
import 'package:sabibom/features/products/domain/product.dart';
import 'package:sabibom/features/products/presentation/widgets/stock_status_badge.dart';

void main() {
  testWidgets('bottom navigation fits a compact phone with visible labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: SabiBomTheme.light,
        home: Scaffold(
          bottomNavigationBar: ModernBottomNavigation(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    for (final label in <String>[
      'Home',
      'Sales',
      'Products',
      'Customers',
      'More',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('stock status remains readable in dark mode', (tester) async {
    const product = Product(
      id: 'product-1',
      businessId: 'business-1',
      name: 'Rice',
      sellingPriceMinor: 1000,
      costPriceMinor: 500,
      quantity: 2,
      lowStockThreshold: 5,
      trackStock: true,
      unit: 'Piece',
      status: ProductStatus.active,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: SabiBomTheme.dark,
        home: const Scaffold(
          body: Center(child: StockStatusBadge(product: product)),
        ),
      ),
    );

    expect(find.text('Low stock'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom navigation respects reduced motion', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SabiBomTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            bottomNavigationBar: ModernBottomNavigation(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    final animatedContainers = tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(animatedContainers, isNotEmpty);
    expect(
      animatedContainers.every((widget) => widget.duration == Duration.zero),
      isTrue,
    );
  });

  test('all supported platforms use the shared page transition', () {
    expect(SabiBomTheme.light.pageTransitionsTheme.builders, hasLength(6));
    expect(SabiBomTheme.dark.pageTransitionsTheme.builders, hasLength(6));
  });
}
