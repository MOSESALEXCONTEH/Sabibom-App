import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationStatus {
  unread,
  read,
  archived;

  String get storedValue => name;

  static NotificationStatus fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    if (raw == 'true' || raw == '1') return NotificationStatus.read;
    if (raw == 'false' || raw == '0') return NotificationStatus.unread;
    return NotificationStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => NotificationStatus.unread,
    );
  }
}

enum NotificationPriority {
  low,
  normal,
  high,
  urgent;

  String get storedValue => name;
  String get label => switch (this) {
    NotificationPriority.low => 'Low',
    NotificationPriority.normal => 'Normal',
    NotificationPriority.high => 'High',
    NotificationPriority.urgent => 'Urgent',
  };

  static NotificationPriority fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return NotificationPriority.values.firstWhere(
      (p) => p.name == raw,
      orElse: () => NotificationPriority.normal,
    );
  }
}

enum NotificationCategory {
  inventory,
  expiry,
  expiredStock('expired_stock'),
  sales,
  customers,
  suppliers,
  expenses,
  approvals,
  endOfDay('end_of_day'),
  staff,
  reports,
  security,
  system;

  const NotificationCategory([this._stored]);
  final String? _stored;
  String get storedValue => _stored ?? name;

  String get title => switch (this) {
    NotificationCategory.inventory => 'Inventory',
    NotificationCategory.expiry => 'Expiry',
    NotificationCategory.expiredStock => 'Expired Stock',
    NotificationCategory.sales => 'Sales',
    NotificationCategory.customers => 'Customers',
    NotificationCategory.suppliers => 'Suppliers',
    NotificationCategory.expenses => 'Expenses',
    NotificationCategory.approvals => 'Approvals',
    NotificationCategory.endOfDay => 'End of Day',
    NotificationCategory.staff => 'Staff',
    NotificationCategory.reports => 'Reports',
    NotificationCategory.security => 'Security',
    NotificationCategory.system => 'System',
  };

  static NotificationCategory fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return NotificationCategory.values.firstWhere(
      (c) => c.storedValue == raw || c.name.toLowerCase() == raw,
      orElse: () => NotificationCategory.system,
    );
  }
}

enum AppNotificationType {
  lowStock(
    'low_stock',
    NotificationCategory.inventory,
    NotificationPriority.normal,
  ),
  outOfStock(
    'out_of_stock',
    NotificationCategory.inventory,
    NotificationPriority.high,
  ),
  stockReplenished(
    'stock_replenished',
    NotificationCategory.inventory,
    NotificationPriority.low,
  ),
  productExpiryApproaching(
    'product_expiry_approaching',
    NotificationCategory.expiry,
    NotificationPriority.normal,
  ),
  productExpiresToday(
    'product_expires_today',
    NotificationCategory.expiry,
    NotificationPriority.high,
  ),
  productExpired(
    'product_expired',
    NotificationCategory.expiry,
    NotificationPriority.urgent,
  ),
  productExpiryUnknown(
    'product_expiry_unknown',
    NotificationCategory.expiry,
    NotificationPriority.low,
  ),
  expiredStockDisposed(
    'expired_stock_disposed',
    NotificationCategory.expiredStock,
    NotificationPriority.normal,
  ),
  customerCreditCreated(
    'customer_credit_created',
    NotificationCategory.customers,
    NotificationPriority.normal,
  ),
  customerDebtOverdue(
    'customer_debt_overdue',
    NotificationCategory.customers,
    NotificationPriority.high,
  ),
  customerLargeBalance(
    'customer_large_balance',
    NotificationCategory.customers,
    NotificationPriority.normal,
  ),
  supplierCreditCreated(
    'supplier_credit_created',
    NotificationCategory.suppliers,
    NotificationPriority.normal,
  ),
  supplierPaymentDue(
    'supplier_payment_due',
    NotificationCategory.suppliers,
    NotificationPriority.high,
  ),
  supplierBalanceOverdue(
    'supplier_balance_overdue',
    NotificationCategory.suppliers,
    NotificationPriority.high,
  ),
  approvalRequested(
    'approval_requested',
    NotificationCategory.approvals,
    NotificationPriority.high,
  ),
  approvalApproved(
    'approval_approved',
    NotificationCategory.approvals,
    NotificationPriority.normal,
  ),
  approvalRejected(
    'approval_rejected',
    NotificationCategory.approvals,
    NotificationPriority.normal,
  ),
  approvalExpired(
    'approval_expired',
    NotificationCategory.approvals,
    NotificationPriority.normal,
  ),
  endOfDayIncomplete(
    'end_of_day_incomplete',
    NotificationCategory.endOfDay,
    NotificationPriority.high,
  ),
  endOfDayShortage(
    'end_of_day_shortage',
    NotificationCategory.endOfDay,
    NotificationPriority.urgent,
  ),
  endOfDaySurplus(
    'end_of_day_surplus',
    NotificationCategory.endOfDay,
    NotificationPriority.normal,
  ),
  largeExpense(
    'large_expense',
    NotificationCategory.expenses,
    NotificationPriority.normal,
  ),
  dailySummaryReady(
    'daily_summary_ready',
    NotificationCategory.reports,
    NotificationPriority.normal,
  ),
  weeklyReportReady(
    'weekly_report_ready',
    NotificationCategory.reports,
    NotificationPriority.low,
  ),
  invitationReceived(
    'invitation_received',
    NotificationCategory.staff,
    NotificationPriority.high,
  ),
  invitationAccepted(
    'invitation_accepted',
    NotificationCategory.staff,
    NotificationPriority.normal,
  ),
  roleChanged(
    'role_changed',
    NotificationCategory.staff,
    NotificationPriority.normal,
  ),
  permissionChanged(
    'permissions_changed',
    NotificationCategory.staff,
    NotificationPriority.normal,
  ),
  membershipDisabled(
    'membership_disabled',
    NotificationCategory.staff,
    NotificationPriority.urgent,
  ),
  membershipRestored(
    'membership_restored',
    NotificationCategory.staff,
    NotificationPriority.normal,
  ),
  staffDisabled(
    'staff_disabled',
    NotificationCategory.staff,
    NotificationPriority.normal,
  ),
  systemMessage(
    'system_message',
    NotificationCategory.system,
    NotificationPriority.low,
  ),
  general('general', NotificationCategory.system, NotificationPriority.low);

  const AppNotificationType(
    this.storedValue,
    this.category,
    this.defaultPriority,
  );
  final String storedValue;
  final NotificationCategory category;
  final NotificationPriority defaultPriority;

  static AppNotificationType fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return AppNotificationType.values.firstWhere(
      (t) => t.storedValue == raw || t.name.toLowerCase() == raw,
      orElse: () => AppNotificationType.general,
    );
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.status,
    required this.priority,
    required this.category,
    this.userId,
    this.businessId,
    this.businessName,
    this.branchId,
    this.entityType,
    this.entityId,
    this.routeName,
    this.routeParameters = const {},
    this.actionLabel,
    this.imageUrl,
    this.imageCid,
    this.linkUrl,
    this.deduplicationKey,
    this.sourceType,
    this.sourceId,
    this.createdAt,
    this.readAt,
    this.archivedAt,
    this.expiresAt,
    this.generatedBy,
    this.metadata = const {},
  });

  final String id;
  final String? userId;
  final String? businessId;
  final String? businessName;
  final String? branchId;
  final AppNotificationType type;
  final NotificationCategory category;
  final String title;
  final String message;
  final NotificationPriority priority;
  final NotificationStatus status;
  final String? entityType;
  final String? entityId;
  final String? routeName;
  final Map<String, String> routeParameters;
  final String? actionLabel;
  final String? imageUrl;
  final String? imageCid;
  final String? linkUrl;
  final String? deduplicationKey;
  final String? sourceType;
  final String? sourceId;
  final DateTime? createdAt;
  final DateTime? readAt;
  final DateTime? archivedAt;
  final DateTime? expiresAt;
  final String? generatedBy;
  final Map<String, Object?> metadata;

  /// Compatibility with older field name.
  String get body => message;
  bool get read =>
      status == NotificationStatus.read ||
      status == NotificationStatus.archived;
  bool get isUnread => status == NotificationStatus.unread;
  bool get isArchived => status == NotificationStatus.archived;

  factory AppNotification.fromMap(String id, Map<String, dynamic> data) {
    final type = AppNotificationType.fromStorage(data['type']);
    final statusRaw = data['status'];
    final NotificationStatus status;
    if (statusRaw != null) {
      status = NotificationStatus.fromStorage(statusRaw);
    } else if (data['read'] == true) {
      status = NotificationStatus.read;
    } else {
      status = NotificationStatus.unread;
    }

    final routeParams = <String, String>{};
    final rawParams = data['routeParameters'];
    if (rawParams is Map) {
      rawParams.forEach((k, v) {
        if (v != null) routeParams['$k'] = '$v';
      });
    }

    final meta = <String, Object?>{};
    final rawMeta = data['metadata'] ?? data['data'];
    if (rawMeta is Map) {
      rawMeta.forEach((k, v) => meta['$k'] = v as Object?);
    }

    return AppNotification(
      id: id,
      userId: data['userId'] as String?,
      businessId: data['businessId'] as String?,
      businessName: data['businessName'] as String?,
      branchId:
          data['branchId'] as String? ??
          (meta['branchId'] is String ? meta['branchId'] as String : null),
      type: type,
      category: data['category'] != null
          ? NotificationCategory.fromStorage(data['category'])
          : type.category,
      title: (data['title'] as String?) ?? 'Notification',
      message: (data['message'] as String?) ?? (data['body'] as String?) ?? '',
      priority: data['priority'] != null
          ? NotificationPriority.fromStorage(data['priority'])
          : type.defaultPriority,
      status: status,
      entityType: data['entityType'] as String?,
      entityId: data['entityId'] as String?,
      routeName: data['routeName'] as String?,
      routeParameters: routeParams,
      actionLabel: data['actionLabel'] as String?,
      imageUrl:
          data['imageUrl'] as String? ??
          (meta['imageUrl'] is String ? meta['imageUrl'] as String : null),
      imageCid:
          data['imageCid'] as String? ??
          (meta['imageCid'] is String ? meta['imageCid'] as String : null),
      linkUrl:
          data['linkUrl'] as String? ??
          (meta['linkUrl'] is String ? meta['linkUrl'] as String : null),
      deduplicationKey: data['deduplicationKey'] as String?,
      sourceType: data['sourceType'] as String?,
      sourceId: data['sourceId'] as String?,
      createdAt: _asDate(data['createdAt']),
      readAt: _asDate(data['readAt']),
      archivedAt: _asDate(data['archivedAt']),
      expiresAt: _asDate(data['expiresAt']),
      generatedBy: data['generatedBy'] as String?,
      metadata: meta,
    );
  }

  Map<String, Object?> toCreateMap({required String userId}) {
    return <String, Object?>{
      'id': id,
      'userId': userId,
      'businessId': businessId,
      'businessName': businessName,
      'branchId': branchId,
      'type': type.storedValue,
      'category': category.storedValue,
      'title': title,
      'message': message,
      'body': message, // legacy compatibility
      'priority': priority.storedValue,
      'status': status.storedValue,
      'read': status != NotificationStatus.unread,
      'entityType': entityType,
      'entityId': entityId,
      'routeName': routeName,
      'routeParameters': routeParameters,
      'actionLabel': actionLabel,
      'imageUrl': imageUrl,
      'imageCid': imageCid,
      'linkUrl': linkUrl,
      'deduplicationKey': deduplicationKey,
      'sourceType': sourceType,
      'sourceId': sourceId,
      'generatedBy': generatedBy,
      'metadata': metadata,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

bool notificationMatchesBranch(
  AppNotification notification, {
  required String? selectedBranchId,
  required String? mainBranchId,
  required bool isAllBranches,
}) {
  final isPlatformMessage =
      notification.sourceType == 'platform_notification' ||
      notification.sourceType == 'platform_announcement' ||
      notification.metadata['platformGlobal'] == true;
  if (isPlatformMessage &&
      (notification.branchId == null ||
          notification.branchId!.trim().isEmpty)) {
    return true;
  }
  if (isAllBranches) return true;
  String? normalize(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  final selected = normalize(selectedBranchId);
  final stored = normalize(notification.branchId);
  if (selected == null) return stored == null;
  if (stored == selected) return true;
  return stored == null && selected == normalize(mainBranchId);
}

/// Allowlisted GoRouter route names for notification deep links.
abstract final class NotificationRouteAllowlist {
  static const Set<String> names = {
    'products',
    'productDetails',
    'customerDetails',
    'supplierDetails',
    'expenseDetails',
    'saleDetails',
    'purchaseDetails',
    'approvalDetails',
    'approvals',
    'invite',
    'myRole',
    'team',
    'reports',
    'reportProfitLoss',
    'reportProductProfit',
    'reportProductExpiry',
    'dailySummary',
    'weeklyReport',
    'endOfDay',
    'backup',
    'notifications',
    'home',
  };

  static bool isAllowed(String? routeName) {
    if (routeName == null || routeName.isEmpty) return false;
    return names.contains(routeName);
  }
}
