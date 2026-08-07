import 'package:intl/intl.dart';

enum RecordDatePeriod {
  all('All'),
  today('Today'),
  yesterday('Yesterday'),
  last7Days('Last 7 days'),
  last30Days('Last 30 days'),
  thisYear('This year'),
  lastYear('Last year');

  const RecordDatePeriod(this.label);
  final String label;
}

({DateTime start, DateTime end})? recordDateRange(
  RecordDatePeriod period, {
  DateTime? now,
}) {
  final local = (now ?? DateTime.now()).toLocal();
  final today = DateTime(local.year, local.month, local.day);
  return switch (period) {
    RecordDatePeriod.all => null,
    RecordDatePeriod.today => (
      start: today,
      end: today.add(const Duration(days: 1)),
    ),
    RecordDatePeriod.yesterday => (
      start: today.subtract(const Duration(days: 1)),
      end: today,
    ),
    RecordDatePeriod.last7Days => (
      start: today.subtract(const Duration(days: 6)),
      end: today.add(const Duration(days: 1)),
    ),
    RecordDatePeriod.last30Days => (
      start: today.subtract(const Duration(days: 29)),
      end: today.add(const Duration(days: 1)),
    ),
    RecordDatePeriod.thisYear => (
      start: DateTime(local.year),
      end: DateTime(local.year + 1),
    ),
    RecordDatePeriod.lastYear => (
      start: DateTime(local.year - 1),
      end: DateTime(local.year),
    ),
  };
}

bool recordFallsInPeriod(
  DateTime? value,
  RecordDatePeriod period, {
  DateTime? now,
}) {
  if (period == RecordDatePeriod.all) return true;
  if (value == null) return false;
  final range = recordDateRange(period, now: now)!;
  final local = value.toLocal();
  return !local.isBefore(range.start) && local.isBefore(range.end);
}

String formatRecordDateTime(DateTime? value, {DateTime? now}) {
  if (value == null) return 'Date unavailable';
  final local = value.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  final currentDay = DateTime(current.year, current.month, current.day);
  final recordDay = DateTime(local.year, local.month, local.day);
  final days = currentDay.difference(recordDay).inDays;
  final relative = switch (days) {
    <= 0 => 'Today',
    1 => 'Yesterday',
    < 7 => '$days days ago',
    < 28 => '${days ~/ 7} ${days ~/ 7 == 1 ? 'week' : 'weeks'} ago',
    < 365 => '${days ~/ 30} ${days ~/ 30 == 1 ? 'month' : 'months'} ago',
    _ => '${days ~/ 365} ${days ~/ 365 == 1 ? 'year' : 'years'} ago',
  };
  return '$relative · ${DateFormat.yMMMd().format(local)} · ${DateFormat.jm().format(local)}';
}
