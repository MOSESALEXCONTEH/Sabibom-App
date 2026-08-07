import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/core/formatting/record_date_filter.dart';

void main() {
  final now = DateTime(2026, 8, 3, 12);

  test('filters today, yesterday and previous year boundaries', () {
    expect(
      recordFallsInPeriod(
        DateTime(2026, 8, 3, 8),
        RecordDatePeriod.today,
        now: now,
      ),
      isTrue,
    );
    expect(
      recordFallsInPeriod(
        DateTime(2026, 8, 2, 23),
        RecordDatePeriod.yesterday,
        now: now,
      ),
      isTrue,
    );
    expect(
      recordFallsInPeriod(
        DateTime(2025, 6),
        RecordDatePeriod.lastYear,
        now: now,
      ),
      isTrue,
    );
  });

  test('formats relative and exact date and time together', () {
    expect(
      formatRecordDateTime(DateTime(2026, 8, 1, 9, 30), now: now),
      contains('2 days ago'),
    );
    expect(
      formatRecordDateTime(DateTime(2026, 8, 1, 9, 30), now: now),
      contains('Aug 1, 2026'),
    );
  });
}
