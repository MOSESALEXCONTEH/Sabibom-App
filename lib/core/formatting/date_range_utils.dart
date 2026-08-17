class DateRange {
  const DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

enum DashboardPeriod { today, week, month, year }

extension DashboardPeriodLabel on DashboardPeriod {
  String get label => switch (this) {
    DashboardPeriod.today => 'Today',
    DashboardPeriod.week => 'Week',
    DashboardPeriod.month => 'Month',
    DashboardPeriod.year => 'Year',
  };

  String get salesLabel => switch (this) {
    DashboardPeriod.today => "Today's Sales",
    DashboardPeriod.week => "This Week's Sales",
    DashboardPeriod.month => "This Month's Sales",
    DashboardPeriod.year => "This Year's Sales",
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
    DashboardPeriod.year => DateRange(
      start: DateTime(local.year),
      end: DateTime(local.year + 1),
    ),
  };
}

DateRange previousDashboardDateRange(DashboardPeriod period, {DateTime? now}) {
  final current = dashboardDateRange(period, now: now);
  return switch (period) {
    DashboardPeriod.today => DateRange(
      start: current.start.subtract(const Duration(days: 1)),
      end: current.start,
    ),
    DashboardPeriod.week => DateRange(
      start: current.start.subtract(const Duration(days: 7)),
      end: current.start,
    ),
    DashboardPeriod.month => DateRange(
      start: DateTime(current.start.year, current.start.month - 1),
      end: current.start,
    ),
    DashboardPeriod.year => DateRange(
      start: DateTime(current.start.year - 1),
      end: current.start,
    ),
  };
}

DateRange _weekRange(DateTime today) {
  final monday = today.subtract(
    Duration(days: today.weekday - DateTime.monday),
  );
  return DateRange(start: monday, end: monday.add(const Duration(days: 7)));
}
