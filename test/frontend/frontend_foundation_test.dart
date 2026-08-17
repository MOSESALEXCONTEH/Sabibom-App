import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/app/theme.dart';
import 'package:sabibom/app/widgets/modern_bottom_navigation.dart';
import 'package:sabibom/features/products/domain/product.dart';
import 'package:sabibom/features/products/presentation/products_screen.dart';
import 'package:sabibom/features/products/presentation/widgets/product_list_tile.dart';
import 'package:sabibom/features/business_setup/application/business_experience_providers.dart';
import 'package:sabibom/features/business_setup/domain/business_operating_model.dart';
import 'package:sabibom/features/dashboard/presentation/dashboard_screen.dart';
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

  testWidgets('service business navigation uses service terminology', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SabiBomTheme.light,
        home: Scaffold(
          bottomNavigationBar: ModernBottomNavigation(
            selectedIndex: 0,
            terminology: BusinessTerminology.forModel(
              BusinessOperatingModel.service,
            ),
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    for (final label in <String>['Income', 'Services', 'Clients']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Products'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('service capabilities disable stock and purchase modules', () {
    const capabilities = BusinessCapabilities(BusinessOperatingModel.service);
    expect(capabilities.managesInventory, isFalse);
    expect(capabilities.managesPurchases, isFalse);
    expect(capabilities.offersServices, isTrue);
  });

  testWidgets('service catalog row hides inventory-only status', (
    tester,
  ) async {
    const service = Product(
      id: 'service-1',
      businessId: 'business-1',
      name: 'Haircut',
      sellingPriceMinor: 5000,
      costPriceMinor: 0,
      quantity: 0,
      lowStockThreshold: 0,
      trackStock: false,
      unit: 'Service',
      status: ProductStatus.active,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: SabiBomTheme.light,
        home: Scaffold(
          body: ProductListTile(
            product: service,
            currencySymbol: 'Le',
            inventoryEnabled: false,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Untracked'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product inventory row fits a compact phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const product = Product(
      id: 'product-compact',
      businessId: 'business-1',
      name: 'Extra long imported premium biscuit package',
      categoryName: 'Food and beverages',
      sku: 'SKU-2026-VERY-LONG',
      sellingPriceMinor: 987654321,
      costPriceMinor: 500,
      quantity: 123456,
      lowStockThreshold: 5,
      trackStock: true,
      unit: 'Cartons',
      status: ProductStatus.active,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: SabiBomTheme.dark,
        home: Scaffold(
          body: ProductListTile(
            product: product,
            currencySymbol: 'Le',
            showProfit: true,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('Extra long imported'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'products screen remains constructible after adaptive catalog changes',
    () {
      expect(const ProductsScreen(), isA<ProductsScreen>());
      expect(const DashboardScreen(), isA<DashboardScreen>());
    },
  );

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
