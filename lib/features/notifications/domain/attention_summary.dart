class AttentionItem {
  const AttentionItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.priority,
    this.routeName,
    this.routeParameters = const {},
    this.iconName = 'warning',
  });

  final String id;
  final String title;
  final String subtitle;
  final String priority; // urgent | high | normal | low
  final String? routeName;
  final Map<String, String> routeParameters;
  final String iconName;
}

class AttentionSummary {
  const AttentionSummary({
    required this.businessId,
    required this.businessName,
    required this.generatedAt,
    this.urgentNotificationCount = 0,
    this.unreadNotificationCount = 0,
    this.lowStockCount = 0,
    this.outOfStockCount = 0,
    this.overdueCustomerCount = 0,
    this.customerOutstandingMinor = 0,
    this.overdueSupplierCount = 0,
    this.supplierOutstandingMinor = 0,
    this.pendingApprovalCount = 0,
    this.endOfDayStatus = 'unknown',
    this.cashDifferenceMinor = 0,
    this.largeExpenseCount = 0,
    this.dailySummaryReady = false,
    this.weeklyReportReady = false,
    this.attentionItems = const [],
    this.topAttentionItems = const [],
  });

  final String businessId;
  final String businessName;
  final DateTime generatedAt;
  final int urgentNotificationCount;
  final int unreadNotificationCount;
  final int lowStockCount;
  final int outOfStockCount;
  final int overdueCustomerCount;
  final int customerOutstandingMinor;
  final int overdueSupplierCount;
  final int supplierOutstandingMinor;
  final int pendingApprovalCount;
  final String endOfDayStatus;
  final int cashDifferenceMinor;
  final int largeExpenseCount;
  final bool dailySummaryReady;
  final bool weeklyReportReady;
  final List<AttentionItem> attentionItems;
  final List<AttentionItem> topAttentionItems;

  bool get hasAttention => attentionItems.isNotEmpty;
}
