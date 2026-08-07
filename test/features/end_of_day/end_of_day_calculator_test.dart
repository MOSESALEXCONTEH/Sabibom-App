import 'package:flutter_test/flutter_test.dart';

import 'package:sabibom/features/end_of_day/domain/end_of_day_summary.dart';

void main() {
  group('EndOfDayCalculator', () {
    test('expected cash = opening + cash in - cash out', () {
      final expected = EndOfDayCalculator.expectedCashMinor(
        openingCashMinor: 10000,
        cashSalesMinor: 5000,
        cashCustomerPaymentsMinor: 2000,
        cashExpensesMinor: 1500,
        cashSupplierPaymentsMinor: 500,
      );
      expect(expected, 15000);
    });

    test('difference and kind: shortage / surplus / balanced', () {
      expect(
        EndOfDayCalculator.differenceMinor(
          countedCashMinor: 9000,
          expectedCashMinor: 10000,
        ),
        -1000,
      );
      expect(CashDifferenceKind.fromDifference(-1000), CashDifferenceKind.shortage);
      expect(CashDifferenceKind.fromDifference(250), CashDifferenceKind.surplus);
      expect(CashDifferenceKind.fromDifference(0), CashDifferenceKind.balanced);
    });
  });
}
