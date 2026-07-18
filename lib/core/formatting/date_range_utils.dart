class DateRange {
  const DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

enum DashboardPeriod { today, week, month }

extension DashboardPeriodLabel on DashboardPeriod {
  String get label => switch (this) {
    DashboardPeriod.today => 'Today',
    DashboardPeriod.week => 'This Week',
    DashboardPeriod.month => 'This Month',
  };

  String get salesLabel => switch (this) {
    DashboardPeriod.today => "Today's Sales",
    DashboardPeriod.week => "This Week's Sales",
    DashboardPeriod.month => "This Month's Sales",
  };
}

/// Local-device reporting periods. Firestore converts these instants to UTC.
DateRange dashboardDateRange(DashboardPeriod period, {DateTime? now}) {
  final local = (now ?? DateTime.now()).toLocal();
  final today = DateTime(local.year, local.month, local.day);
  return switch (period) {
    DashboardPeriod.today => DateRange(
      start: today,
      end: today.add(const Duration(days: 1)),
    ),
    DashboardPeriod.week => _weekRange(today),
    DashboardPeriod.month => DateRange(
      start: DateTime(local.year, local.month),
      end: DateTime(local.year, local.month + 1),
    ),
  };
}

DateRange _weekRange(DateTime today) {
  final monday = today.subtract(
    Duration(days: today.weekday - DateTime.monday),
  );
  return DateRange(start: monday, end: monday.add(const Duration(days: 7)));
}
