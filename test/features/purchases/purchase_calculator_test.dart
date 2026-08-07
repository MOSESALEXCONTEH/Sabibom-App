import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/purchases/domain/purchase.dart';
import 'package:sabibom/features/purchases/domain/purchase_calculator.dart';
import 'package:sabibom/features/sales/domain/sale_models.dart';

PurchaseItem _item({
  double quantity = 2,
  int cost = 1000,
  DiscountType? discountType,
  double discount = 0,
}) => PurchaseItem(
  purchaseItemId: 'item-1',
  productId: 'product-1',
  name: 'Rice',
  quantity: quantity,
  unitCostMinor: cost,
  trackStock: true,
  discountType: discountType,
  discountValue: discount,
);

void main() {
  group('PurchaseCalculator', () {
    test('calculates line and order totals in minor units', () {
      final totals = PurchaseCalculator.calculate(
        items: <PurchaseItem>[_item()],
        deliveryMinor: 250,
        amountPaidMinor: 2250,
      );

      expect(totals.subtotalMinor, 2000);
      expect(totals.totalMinor, 2250);
      expect(totals.amountPaidMinor, 2250);
      expect(totals.balanceDueMinor, 0);
    });

    test('applies percentage discounts before tax', () {
      final totals = PurchaseCalculator.calculate(
        items: <PurchaseItem>[
          _item(discountType: DiscountType.percentage, discount: 10),
        ],
        taxPercentage: 5,
      );

      expect(totals.itemDiscountMinor, 200);
      expect(totals.taxMinor, 90);
      expect(totals.totalMinor, 1890);
    });

    test('reports a balance for partial payment', () {
      final totals = PurchaseCalculator.calculate(
        items: <PurchaseItem>[_item()],
        amountPaidMinor: 750,
      );

      expect(totals.amountPaidMinor, 750);
      expect(totals.balanceDueMinor, 1250);
    });

    test('rejects invalid quantities and percentage discounts', () {
      expect(
        () => PurchaseCalculator.calculate(
          items: <PurchaseItem>[_item(quantity: 0)],
        ),
        throwsA(isA<PurchaseException>()),
      );
      expect(
        () => PurchaseCalculator.calculate(
          items: <PurchaseItem>[
            _item(discountType: DiscountType.percentage, discount: 101),
          ],
        ),
        throwsA(isA<PurchaseException>()),
      );
    });
  });
}
