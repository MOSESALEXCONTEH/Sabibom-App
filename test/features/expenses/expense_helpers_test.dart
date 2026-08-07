import 'package:flutter_test/flutter_test.dart';

import 'package:sabibom/features/expenses/domain/expense.dart';

void main() {
  group('formatExpenseNumber', () {
    test('pads sequence to 4 digits', () {
      expect(formatExpenseNumber('20260722', 1), 'EXP-20260722-0001');
      expect(formatExpenseNumber('20260722', 25), 'EXP-20260722-0025');
    });
  });

  group('expensePeriodRange', () {
    final now = DateTime(2026, 7, 22, 15, 0);

    test('today range', () {
      final range = expensePeriodRange(ExpensePeriod.today, now: now);
      expect(range.start, DateTime(2026, 7, 22));
      expect(range.end, DateTime(2026, 7, 23));
    });

    test('yesterday and rolling ranges', () {
      final yesterday = expensePeriodRange(ExpensePeriod.yesterday, now: now);
      expect(yesterday.start, DateTime(2026, 7, 21));
      expect(yesterday.end, DateTime(2026, 7, 22));

      final last7 = expensePeriodRange(ExpensePeriod.last7Days, now: now);
      expect(last7.start, DateTime(2026, 7, 16));
      expect(last7.end, DateTime(2026, 7, 23));
    });

    test('this month range', () {
      final range = expensePeriodRange(ExpensePeriod.thisMonth, now: now);
      expect(range.start, DateTime(2026, 7));
      expect(range.end, DateTime(2026, 8));
    });

    test('this year range', () {
      final range = expensePeriodRange(ExpensePeriod.thisYear, now: now);
      expect(range.start, DateTime(2026));
      expect(range.end, DateTime(2027));
    });

    test('last year range', () {
      final range = expensePeriodRange(ExpensePeriod.lastYear, now: now);
      expect(range.start, DateTime(2025));
      expect(range.end, DateTime(2026));
    });
  });

  group('ExpensePaymentMethod', () {
    test('round-trips storage values', () {
      for (final method in ExpensePaymentMethod.values) {
        expect(ExpensePaymentMethod.fromStorage(method.storedValue), method);
      }
    });
  });

  group('ExpenseStatus', () {
    test('parses voided and defaults unknown to active', () {
      expect(ExpenseStatus.fromStorage('voided'), ExpenseStatus.voided);
      expect(ExpenseStatus.fromStorage('active'), ExpenseStatus.active);
      expect(ExpenseStatus.fromStorage('weird'), ExpenseStatus.active);
    });
  });
}
