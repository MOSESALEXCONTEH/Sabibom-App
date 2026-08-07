import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sabibom/app/router.dart';
import 'package:sabibom/features/business_setup/domain/business.dart';
import 'package:sabibom/features/business_setup/domain/business_setup_data.dart';
import 'package:sabibom/features/dashboard/application/dashboard_providers.dart';
import 'package:sabibom/features/sales/application/sales_providers.dart'
    as sales;
import 'package:sabibom/features/sales/data/sales_repository.dart';
import 'package:sabibom/features/sales/domain/sale.dart';
import 'package:sabibom/features/sales/domain/sale_models.dart';
import 'package:sabibom/features/sales/presentation/sale_details_screen.dart';
import 'package:sabibom/features/sales/presentation/sales_navigation.dart';

Business _fakeBusiness() {
  return const Business(
    businessId: 'biz-1',
    name: 'SabiBom Test Business',
    normalizedName: 'sabibom test business',
    ownerId: 'owner-1',
    businessType: 'Retail Shop',
    customBusinessType: null,
    logoUrl: null,
    phoneNumber: '000000000',
    email: null,
    address: 'Freetown',
    district: 'Western Area Urban',
    country: 'Sierra Leone',
    currency: CurrencyConfig.sle,
    taxEnabled: false,
    taxPercentage: 0,
    financialYearStartMonth: 'January',
    status: 'active',
  );
}

Sale _fakeSale({required String id}) {
  return Sale(
    id: id,
    businessId: 'biz-1',
    receiptNumber: 'SB-20260718-0001',
    customerName: 'Walk-in Customer',
    items: const <SaleLineItem>[
      SaleLineItem(
        name: 'Rice',
        quantity: 2,
        unitPriceMinor: 5000,
        lineTotalMinor: 10000,
      ),
    ],
    subtotalMinor: 10000,
    discountMinor: 0,
    taxMinor: 0,
    totalMinor: 10000,
    amountPaidMinor: 10000,
    balanceDueMinor: 0,
    changeMinor: 0,
    currencyCode: 'SLE',
    currencySymbol: 'Le',
    paymentMethod: PaymentMethod.cash,
    paymentStatus: PaymentStatus.paid,
    saleStatus: SaleStatus.completed,
    createdAt: DateTime(2026, 7, 18, 10),
  );
}

class _FakeSalesRepository implements SalesRepository {
  _FakeSalesRepository({this.sale});

  final Sale? sale;

  @override
  Future<CompletedSale> completeSale(CompleteSaleRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<void> voidSale(
    String businessId,
    String saleId, {
    required String branchId,
    required String reason,
    String? voidedByUid,
    String? voidedByName,
  }) async {}

  @override
  Future<Map<String, dynamic>?> getSale(
    String businessId,
    String saleId, {
    String? branchId,
  }) async {
    final document = await getSaleDocument(
      businessId,
      saleId,
      branchId: branchId,
    );
    if (document == null) return null;
    return <String, dynamic>{
      'saleId': document.id,
      'receiptNumber': document.receiptNumber,
      'totalMinor': document.totalMinor,
      'items': document.items
          .map(
            (item) => <String, Object?>{
              'name': item.name,
              'quantity': item.quantity,
              'lineTotalMinor': item.lineTotalMinor,
            },
          )
          .toList(),
    };
  }

  @override
  Future<Sale?> getSaleDocument(
    String businessId,
    String saleId, {
    String? branchId,
  }) async {
    if (sale == null || sale!.id != saleId) return null;
    return sale;
  }

  @override
  Stream<List<SaleHistoryItem>> watchRecentSales(
    String businessId, {
    String? branchId,
    int limit = 25,
  }) {
    return Stream<List<SaleHistoryItem>>.value(const <SaleHistoryItem>[]);
  }
}

void main() {
  testWidgets('sale details opens using document id', (tester) async {
    final router = GoRouter(
      initialLocation: '/sales/sale-123',
      routes: <RouteBase>[
        GoRoute(
          path: '/sales',
          name: AppRouteNames.sales,
          builder: (_, _) => const Scaffold(body: Text('sales')),
          routes: <RouteBase>[
            GoRoute(
              path: ':saleId',
              name: AppRouteNames.saleDetails,
              builder: (_, state) =>
                  SaleDetailsScreen(saleId: state.pathParameters['saleId']!),
              routes: <RouteBase>[
                GoRoute(
                  path: 'receipt',
                  name: AppRouteNames.saleReceipt,
                  builder: (_, state) => Scaffold(
                    body: Text('receipt:${state.pathParameters['saleId']}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(
            (_) => Stream<ActiveBusinessState>.value(
              ActiveBusinessData(_fakeBusiness()),
            ),
          ),
          sales.salesRepositoryProvider.overrideWithValue(
            _FakeSalesRepository(sale: _fakeSale(id: 'sale-123')),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sale Details'), findsOneWidget);
    expect(find.text('SB-20260718-0001'), findsOneWidget);
    expect(find.text('Rice'), findsOneWidget);
  });

  testWidgets('invalid sale id shows record error not page not found', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SaleDetailsScreen(saleId: '   ')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invalid sale'), findsOneWidget);
    expect(find.text('Page not found'), findsNothing);
  });

  testWidgets('missing sale document shows sale not found state', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/sales/missing-id',
      routes: <RouteBase>[
        GoRoute(
          path: '/sales/:saleId',
          builder: (_, state) =>
              SaleDetailsScreen(saleId: state.pathParameters['saleId']!),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(
            (_) => Stream<ActiveBusinessState>.value(
              ActiveBusinessData(_fakeBusiness()),
            ),
          ),
          sales.salesRepositoryProvider.overrideWithValue(
            _FakeSalesRepository(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sale not found'), findsOneWidget);
    expect(find.text('Page not found'), findsNothing);
  });

  testWidgets('sales navigation helper pushes named sale details route', (
    tester,
  ) async {
    late BuildContext captured;
    final router = GoRouter(
      initialLocation: '/sales',
      routes: <RouteBase>[
        GoRoute(
          path: '/sales',
          name: AppRouteNames.sales,
          builder: (context, _) {
            captured = context;
            return const Scaffold(body: Text('sales root'));
          },
          routes: <RouteBase>[
            GoRoute(
              path: ':saleId',
              name: AppRouteNames.saleDetails,
              builder: (_, state) => Scaffold(
                body: Text('details:${state.pathParameters['saleId']}'),
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    SalesNavigation.openSaleDetails(captured, 'doc-abc');
    await tester.pumpAndSettle();

    expect(find.text('details:doc-abc'), findsOneWidget);
  });
}
