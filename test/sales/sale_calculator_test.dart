import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/sales/domain/sale_calculator.dart';
import 'package:sabibom/features/sales/domain/sale_models.dart';

SaleItem saleItem({
  required String id,
  required int unitPriceMinor,
  double quantity = 1,
  DiscountType? discountType,
  double discountValue = 0,
}) {
  return SaleItem(
    saleItemId: id,
    name: id,
    quantity: quantity,
    unitPriceMinor: unitPriceMinor,
    trackStock: true,
    isCustomItem: false,
    discountType: discountType,
    discountValue: discountValue,
  );
}

void main() {
  group('SaleCalculator', () {
    test('calculates item discount, order discount, tax, and balance in minor units', () {
      final totals = SaleCalculator.calculate(
        items: <SaleItem>[
          saleItem(
            id: 'rice',
            quantity: 2,
            unitPriceMinor: 1500,
            discountType: DiscountType.percentage,
            discountValue: 10,
          ),
          saleItem(id: 'oil', unitPriceMinor: 1000),
        ],
        taxEnabled: true,
        taxPercentage: 5,
        orderDiscountType: DiscountType.fixed,
        orderDiscountValue: 5,
        amountPaidMinor: 3000,
      );

      expect(totals.subtotalMinor, 4000);
      expect(totals.itemDiscountMinor, 300);
      expect(totals.orderDiscountMinor, 500);
      expect(totals.taxMinor, 160);
      expect(totals.totalMinor, 3360);
      expect(totals.amountPaidMinor, 3000);
      expect(totals.balanceDueMinor, 360);
      expect(totals.changeMinor, 0);
    });

    test('caps recorded payment at total and reports excess as change', () {
      final totals = SaleCalculator.calculate(
        items: <SaleItem>[saleItem(id: 'bread', unitPriceMinor: 1250)],
        taxEnabled: false,
        taxPercentage: 0,
        orderDiscountType: null,
        orderDiscountValue: 0,
        amountPaidMinor: 2000,
      );

      expect(totals.totalMinor, 1250);
      expect(totals.amountPaidMinor, 1250);
      expect(totals.balanceDueMinor, 0);
      expect(totals.changeMinor, 750);
    });
  });
}
