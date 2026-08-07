import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationPreferences {
  const NotificationPreferences({
    this.userId,
    this.businessId,
    this.inAppEnabled = true,
    this.pushEnabled = true,
    this.lowStockEnabled = true,
    this.outOfStockEnabled = true,
    this.customerDebtEnabled = true,
    this.supplierPaymentEnabled = true,
    this.approvalEnabled = true,
    this.endOfDayEnabled = true,
    this.largeExpenseEnabled = true,
    this.staffActivityEnabled = true,
    this.dailySummaryEnabled = true,
    this.weeklyReportEnabled = true,
    this.dailySummaryTime = '18:30',
    this.weeklyReportDay = 1, // Monday
    this.weeklyReportTime = '09:00',
    this.endOfDayReminderTime = '20:00',
    this.quietHoursEnabled = false,
    this.quietHoursStart = '22:00',
    this.quietHoursEnd = '07:00',
    this.customerDebtMinimumMinor = 50000, // Le 500
    this.supplierDebtMinimumMinor = 100000, // Le 1000
    this.largeExpenseThresholdMinor = 200000, // Le 2000
    this.timezone = 'Africa/Freetown',
    this.updatedAt,
  });

  final String? userId;
  final String? businessId;
  final bool inAppEnabled;
  final bool pushEnabled;
  final bool lowStockEnabled;
  final bool outOfStockEnabled;
  final bool customerDebtEnabled;
  final bool supplierPaymentEnabled;
  final bool approvalEnabled;
  final bool endOfDayEnabled;
  final bool largeExpenseEnabled;
  final bool staffActivityEnabled;
  final bool dailySummaryEnabled;
  final bool weeklyReportEnabled;
  final String dailySummaryTime;
  final int weeklyReportDay;
  final String weeklyReportTime;
  final String endOfDayReminderTime;
  final bool quietHoursEnabled;
  final String quietHoursStart;
  final String quietHoursEnd;
  final int customerDebtMinimumMinor;
  final int supplierDebtMinimumMinor;
  final int largeExpenseThresholdMinor;
  final String timezone;
  final DateTime? updatedAt;

  factory NotificationPreferences.fromMap(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return const NotificationPreferences();
    // Support legacy notificationPrefs shape.
    final legacy = data['sales'] != null || data['lowStock'] != null;
    if (legacy && data['inAppEnabled'] == null) {
      return NotificationPreferences(
        lowStockEnabled: data['lowStock'] as bool? ?? true,
        outOfStockEnabled: data['lowStock'] as bool? ?? true,
        customerDebtEnabled: data['customerCredit'] as bool? ?? true,
        supplierPaymentEnabled: data['customerCredit'] as bool? ?? true,
        staffActivityEnabled: data['team'] as bool? ?? false,
        dailySummaryEnabled: data['sales'] as bool? ?? true,
        weeklyReportEnabled: data['sales'] as bool? ?? true,
        endOfDayEnabled: data['sales'] as bool? ?? true,
      );
    }
    return NotificationPreferences(
      userId: data['userId'] as String?,
      businessId: data['businessId'] as String?,
      inAppEnabled: data['inAppEnabled'] != false,
      pushEnabled: data['pushEnabled'] != false,
      lowStockEnabled: data['lowStockEnabled'] != false,
      outOfStockEnabled: data['outOfStockEnabled'] != false,
      customerDebtEnabled: data['customerDebtEnabled'] != false,
      supplierPaymentEnabled: data['supplierPaymentEnabled'] != false,
      approvalEnabled: data['approvalEnabled'] != false,
      endOfDayEnabled: data['endOfDayEnabled'] != false,
      largeExpenseEnabled: data['largeExpenseEnabled'] != false,
      staffActivityEnabled: data['staffActivityEnabled'] != false,
      dailySummaryEnabled: data['dailySummaryEnabled'] != false,
      weeklyReportEnabled: data['weeklyReportEnabled'] != false,
      dailySummaryTime: (data['dailySummaryTime'] as String?) ?? '18:30',
      weeklyReportDay: (data['weeklyReportDay'] as num?)?.toInt() ?? 1,
      weeklyReportTime: (data['weeklyReportTime'] as String?) ?? '09:00',
      endOfDayReminderTime: (data['endOfDayReminderTime'] as String?) ?? '20:00',
      quietHoursEnabled: data['quietHoursEnabled'] == true,
      quietHoursStart: (data['quietHoursStart'] as String?) ?? '22:00',
      quietHoursEnd: (data['quietHoursEnd'] as String?) ?? '07:00',
      customerDebtMinimumMinor:
          (data['customerDebtMinimumMinor'] as num?)?.toInt() ?? 50000,
      supplierDebtMinimumMinor:
          (data['supplierDebtMinimumMinor'] as num?)?.toInt() ?? 100000,
      largeExpenseThresholdMinor:
          (data['largeExpenseThresholdMinor'] as num?)?.toInt() ?? 200000,
      timezone: (data['timezone'] as String?) ?? 'Africa/Freetown',
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'userId': userId,
      'businessId': businessId,
      'inAppEnabled': inAppEnabled,
      'pushEnabled': pushEnabled,
      'lowStockEnabled': lowStockEnabled,
      'outOfStockEnabled': outOfStockEnabled,
      'customerDebtEnabled': customerDebtEnabled,
      'supplierPaymentEnabled': supplierPaymentEnabled,
      'approvalEnabled': approvalEnabled,
      'endOfDayEnabled': endOfDayEnabled,
      'largeExpenseEnabled': largeExpenseEnabled,
      'staffActivityEnabled': staffActivityEnabled,
      'dailySummaryEnabled': dailySummaryEnabled,
      'weeklyReportEnabled': weeklyReportEnabled,
      'dailySummaryTime': dailySummaryTime,
      'weeklyReportDay': weeklyReportDay,
      'weeklyReportTime': weeklyReportTime,
      'endOfDayReminderTime': endOfDayReminderTime,
      'quietHoursEnabled': quietHoursEnabled,
      'quietHoursStart': quietHoursStart,
      'quietHoursEnd': quietHoursEnd,
      'customerDebtMinimumMinor': customerDebtMinimumMinor,
      'supplierDebtMinimumMinor': supplierDebtMinimumMinor,
      'largeExpenseThresholdMinor': largeExpenseThresholdMinor,
      'timezone': timezone,
      'updatedAt': FieldValue.serverTimestamp(),
      // Legacy mirror for older readers.
      'sales': dailySummaryEnabled || endOfDayEnabled,
      'lowStock': lowStockEnabled,
      'customerCredit': customerDebtEnabled,
      'team': staffActivityEnabled,
    };
  }

  NotificationPreferences copyWith({
    bool? inAppEnabled,
    bool? pushEnabled,
    bool? lowStockEnabled,
    bool? outOfStockEnabled,
    bool? customerDebtEnabled,
    bool? supplierPaymentEnabled,
    bool? approvalEnabled,
    bool? endOfDayEnabled,
    bool? largeExpenseEnabled,
    bool? staffActivityEnabled,
    bool? dailySummaryEnabled,
    bool? weeklyReportEnabled,
    String? dailySummaryTime,
    int? weeklyReportDay,
    String? weeklyReportTime,
    String? endOfDayReminderTime,
    bool? quietHoursEnabled,
    String? quietHoursStart,
    String? quietHoursEnd,
    int? customerDebtMinimumMinor,
    int? supplierDebtMinimumMinor,
    int? largeExpenseThresholdMinor,
    String? timezone,
  }) {
    return NotificationPreferences(
      userId: userId,
      businessId: businessId,
      inAppEnabled: inAppEnabled ?? this.inAppEnabled,
      pushEnabled: pushEnabled ?? this.pushEnabled,
      lowStockEnabled: lowStockEnabled ?? this.lowStockEnabled,
      outOfStockEnabled: outOfStockEnabled ?? this.outOfStockEnabled,
      customerDebtEnabled: customerDebtEnabled ?? this.customerDebtEnabled,
      supplierPaymentEnabled:
          supplierPaymentEnabled ?? this.supplierPaymentEnabled,
      approvalEnabled: approvalEnabled ?? this.approvalEnabled,
      endOfDayEnabled: endOfDayEnabled ?? this.endOfDayEnabled,
      largeExpenseEnabled: largeExpenseEnabled ?? this.largeExpenseEnabled,
      staffActivityEnabled: staffActivityEnabled ?? this.staffActivityEnabled,
      dailySummaryEnabled: dailySummaryEnabled ?? this.dailySummaryEnabled,
      weeklyReportEnabled: weeklyReportEnabled ?? this.weeklyReportEnabled,
      dailySummaryTime: dailySummaryTime ?? this.dailySummaryTime,
      weeklyReportDay: weeklyReportDay ?? this.weeklyReportDay,
      weeklyReportTime: weeklyReportTime ?? this.weeklyReportTime,
      endOfDayReminderTime: endOfDayReminderTime ?? this.endOfDayReminderTime,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietHoursStart: quietHoursStart ?? this.quietHoursStart,
      quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
      customerDebtMinimumMinor:
          customerDebtMinimumMinor ?? this.customerDebtMinimumMinor,
      supplierDebtMinimumMinor:
          supplierDebtMinimumMinor ?? this.supplierDebtMinimumMinor,
      largeExpenseThresholdMinor:
          largeExpenseThresholdMinor ?? this.largeExpenseThresholdMinor,
      timezone: timezone ?? this.timezone,
      updatedAt: updatedAt,
    );
  }
}
