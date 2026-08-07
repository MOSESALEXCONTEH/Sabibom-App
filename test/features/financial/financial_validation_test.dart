import 'package:flutter_test/flutter_test.dart';

import 'package:sabibom/core/formatting/currency_formatter.dart';
import 'package:sabibom/features/notifications/application/business_summary_service.dart';
import 'package:sabibom/features/sales/domain/sale_calculator.dart';
import 'package:sabibom/features/sales/domain/sale_models.dart';

void main() {
  group('Financial validation suite (deterministic)', () {
    test('single-item cash sale totals', () {
      final totals = SaleCalculator.calculate(
        items: [
          SaleItem(
            saleItemId: '1',
            name: 'Soap',
            quantity: 2,
            unitPriceMinor: 500,
            trackStock: true,
            isCustomItem: false,
            productId: 'p1',
          ),
        ],
        taxEnabled: false,
        taxPercentage: 0,
        orderDiscountType: null,
        orderDiscountValue: 0,
        amountPaidMinor: 1000,
      );
      expect(totals.subtotalMinor, 1000);
      expect(totals.totalMinor, 1000);
      expect(totals.balanceDueMinor, 0);
    });

    test('percentage discount reduces total', () {
      final totals = SaleCalculator.calculate(
        items: [
          SaleItem(
            saleItemId: '1',
            name: 'Gel',
            quantity: 1,
            unitPriceMinor: 10000,
            trackStock: true,
            isCustomItem: false,
            productId: 'p2',
            discountType: DiscountType.percentage,
            discountValue: 10,
          ),
        ],
        taxEnabled: false,
        taxPercentage: 0,
        orderDiscountType: null,
        orderDiscountValue: 0,
        amountPaidMinor: 9000,
      );
      expect(totals.totalMinor, 9000);
    });

    test('partial payment creates balance due', () {
      final totals = SaleCalculator.calculate(
        items: [
          SaleItem(
            saleItemId: '1',
            name: 'Cream',
            quantity: 1,
            unitPriceMinor: 5000,
            trackStock: true,
            isCustomItem: false,
            productId: 'p3',
          ),
        ],
        taxEnabled: false,
        taxPercentage: 0,
        orderDiscountType: null,
        orderDiscountValue: 0,
        amountPaidMinor: 2000,
      );
      expect(totals.totalMinor, 5000);
      expect(totals.amountPaidMinor, 2000);
      expect(totals.balanceDueMinor, 3000);
    });

    test('zero and large values format safely', () {
      expect(formatCurrency(0), contains('0.00'));
      expect(formatCurrency(1234567.89), isNot(contains('NaN')));
    });

    test('percentChange never returns NaN or Infinity', () {
      expect(BusinessSummaryService.percentChange(0, 0).isFinite, isTrue);
      expect(BusinessSummaryService.percentChange(10, 0).isFinite, isTrue);
      expect(BusinessSummaryService.percentChange(150, 100), 50);
    });

    test('non-finite money formats as zero', () {
      expect(formatCurrency(double.nan), contains('0.00'));
      expect(formatCurrency(double.infinity), contains('0.00'));
    });
  });
}
