import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/business_setup/domain/business.dart';
import 'package:sabibom/features/business_setup/domain/business_setup_data.dart';
import 'package:sabibom/features/dashboard/application/dashboard_providers.dart';
import 'package:sabibom/features/sales/application/sale_cart_controller.dart';
import 'package:sabibom/features/sales/application/sales_providers.dart'
    as sales;
import 'package:sabibom/features/sales/domain/sale_models.dart';
import 'package:sabibom/features/sales/presentation/sales_screens.dart';

class _TestShell extends StatefulWidget {
  const _TestShell();

  @override
  State<_TestShell> createState() => _TestShellState();
}

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

class _TestShellState extends State<_TestShell> {
  var _showNewSale = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _showNewSale
          ? Column(
              children: <Widget>[
                const Expanded(child: NewSaleScreen()),
                TextButton(
                  onPressed: () => setState(() => _showNewSale = false),
                  child: const Text('back'),
                ),
              ],
            )
          : Column(
              children: <Widget>[
                const Expanded(
                  child: SafeArea(child: Center(child: Text('sales root'))),
                ),
                TextButton(
                  onPressed: () => setState(() => _showNewSale = true),
                  child: const Text('new sale'),
                ),
              ],
            ),
    );
  }
}

void main() {
  testWidgets('new sale mount cycles do not throw framework lifecycle errors', (
    tester,
  ) async {
    final recorded = <FlutterErrorDetails>[];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      recorded.add(details);
      oldOnError?.call(details);
    };

    addTearDown(() {
      FlutterError.onError = oldOnError;
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBusinessProvider.overrideWith(
            (_) => Stream<ActiveBusinessState>.value(
              ActiveBusinessData(_fakeBusiness()),
            ),
          ),
          sales.saleProductsProvider.overrideWith(
            (ref, businessId) =>
                Stream<List<SaleProduct>>.value(const <SaleProduct>[]),
          ),
          saleCartProvider.overrideWith(() => SaleCartController()),
        ],
        child: const MaterialApp(home: _TestShell()),
      ),
    );

    for (var i = 0; i < 10; i++) {
      await tester.tap(find.text('new sale'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add custom item'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(4));
      await tester.tap(fields.last);
      await tester.pumpAndSettle();
      await tester.enterText(fields.last, 'Test Item');
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.text('back'));
      await tester.pumpAndSettle();
    }

    expect(
      recorded.where((error) {
        final text = error.exceptionAsString();
        return text.contains('_dependents.isEmpty') ||
            text.contains('used after being disposed') ||
            text.contains('Duplicate GlobalKeys');
      }),
      isEmpty,
    );
  });
}
