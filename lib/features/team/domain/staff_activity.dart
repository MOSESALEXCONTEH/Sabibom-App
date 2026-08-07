import 'package:cloud_firestore/cloud_firestore.dart';

enum StaffActionType {
  memberInvited('member_invited'),
  invitationAccepted('invitation_accepted'),
  memberDisabled('member_disabled'),
  memberRestored('member_restored'),
  memberRemoved('member_removed'),
  roleChanged('role_changed'),
  permissionsChanged('permissions_changed'),
  saleCreated('sale_created'),
  saleVoided('sale_voided'),
  expenseCreated('expense_created'),
  expenseVoided('expense_voided'),
  productCreated('product_created'),
  stockAdjusted('stock_adjusted'),
  purchaseCreated('purchase_created'),
  supplierPaymentRecorded('supplier_payment_recorded'),
  customerPaymentRecorded('customer_payment_recorded'),
  receiptTemplateChanged('receipt_template_changed'),
  businessSettingsChanged('business_settings_changed'),
  approvalRequested('approval_requested'),
  approvalApproved('approval_approved'),
  approvalRejected('approval_rejected'),
  customRoleCreated('custom_role_created'),
  customRoleUpdated('custom_role_updated'),
  staffBranchAssigned('staff.branch_assigned'),
  staffBranchRemoved('staff.branch_removed');

  const StaffActionType(this.storedValue);
  final String storedValue;

  static StaffActionType fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    final alias = switch (raw) {
      'sale' => StaffActionType.saleCreated,
      'sale_void' => StaffActionType.saleVoided,
      'expense' => StaffActionType.expenseCreated,
      'expense_void' => StaffActionType.expenseVoided,
      'productadded' || 'product_added' => StaffActionType.productCreated,
      'stockadjustment' ||
      'stock_adjustment' ||
      'expired_stock_disposal' => StaffActionType.stockAdjusted,
      'purchase' => StaffActionType.purchaseCreated,
      'supplierpayment' ||
      'supplier_payment' => StaffActionType.supplierPaymentRecorded,
      'customerpayment' ||
      'customer_payment' => StaffActionType.customerPaymentRecorded,
      _ => null,
    };
    if (alias != null) return alias;
    return StaffActionType.values.firstWhere(
      (a) => a.storedValue == raw || a.name.toLowerCase() == raw,
      orElse: () => StaffActionType.businessSettingsChanged,
    );
  }

  String get label => switch (this) {
    StaffActionType.memberInvited => 'Member invited',
    StaffActionType.invitationAccepted => 'Invitation accepted',
    StaffActionType.memberDisabled => 'Member disabled',
    StaffActionType.memberRestored => 'Member restored',
    StaffActionType.memberRemoved => 'Member removed',
    StaffActionType.roleChanged => 'Role changed',
    StaffActionType.permissionsChanged => 'Permissions changed',
    StaffActionType.saleCreated => 'Sale created',
    StaffActionType.saleVoided => 'Sale voided',
    StaffActionType.expenseCreated => 'Expense created',
    StaffActionType.expenseVoided => 'Expense voided',
    StaffActionType.productCreated => 'Product created',
    StaffActionType.stockAdjusted => 'Stock adjusted',
    StaffActionType.purchaseCreated => 'Purchase created',
    StaffActionType.supplierPaymentRecorded => 'Supplier payment recorded',
    StaffActionType.customerPaymentRecorded => 'Customer payment recorded',
    StaffActionType.receiptTemplateChanged => 'Receipt template changed',
    StaffActionType.businessSettingsChanged => 'Business settings changed',
    StaffActionType.approvalRequested => 'Approval requested',
    StaffActionType.approvalApproved => 'Approval approved',
    StaffActionType.approvalRejected => 'Approval rejected',
    StaffActionType.customRoleCreated => 'Custom role created',
    StaffActionType.customRoleUpdated => 'Custom role updated',
    StaffActionType.staffBranchAssigned => 'Staff assigned to branch',
    StaffActionType.staffBranchRemoved => 'Staff removed from branch',
  };

  bool get isSensitive => switch (this) {
    StaffActionType.memberDisabled ||
    StaffActionType.memberRemoved ||
    StaffActionType.roleChanged ||
    StaffActionType.permissionsChanged ||
    StaffActionType.saleVoided ||
    StaffActionType.expenseVoided ||
    StaffActionType.stockAdjusted ||
    StaffActionType.staffBranchAssigned ||
    StaffActionType.staffBranchRemoved ||
    StaffActionType.approvalApproved ||
    StaffActionType.approvalRejected => true,
    _ => false,
  };
}

class StaffActivity {
  const StaffActivity({
    required this.id,
    required this.businessId,
    required this.userId,
    required this.userName,
    required this.userRole,
    required this.actionType,
    required this.description,
    this.branchId,
    this.entityType,
    this.entityId,
    this.entityLabel,
    this.metadata = const {},
    this.createdAt,
    this.deviceId,
    this.platform,
  });

  final String id;
  final String businessId;
  final String userId;
  final String userName;
  final String userRole;
  final StaffActionType actionType;
  final String? entityType;
  final String? entityId;
  final String? entityLabel;
  final String description;
  final String? branchId;
  final Map<String, Object?> metadata;
  final DateTime? createdAt;
  final String? deviceId;
  final String? platform;

  factory StaffActivity.fromMap(String id, Map<String, dynamic> data) {
    return StaffActivity(
      id: id,
      businessId: (data['businessId'] as String?) ?? '',
      userId: _optionalString(data['userId'] ?? data['createdBy']) ?? '',
      userName:
          _optionalString(data['userName'] ?? data['createdByName']) ?? 'Staff',
      userRole: _optionalString(data['userRole']) ?? '',
      actionType: StaffActionType.fromStorage(
        data['actionType'] ?? data['type'],
      ),
      entityType: _optionalString(data['entityType'] ?? data['type']),
      entityId: _optionalString(data['entityId'] ?? data['referenceId']),
      entityLabel: _optionalString(data['entityLabel'] ?? data['title']),
      description:
          _optionalString(
            data['description'] ?? data['subtitle'] ?? data['title'],
          ) ??
          '',
      branchId: _optionalString(
        data['branchId'] ?? (data['metadata'] as Map?)?['branchId'],
      ),
      metadata: Map<String, Object?>.from(
        (data['metadata'] as Map?)?.map(
              (k, v) => MapEntry('$k', v as Object?),
            ) ??
            const {},
      ),
      createdAt: (data['createdAt'] ?? data['timestamp']) is Timestamp
          ? ((data['createdAt'] ?? data['timestamp']) as Timestamp).toDate()
          : null,
      deviceId: data['deviceId'] as String?,
      platform: data['platform'] as String?,
    );
  }

  Map<String, Object?> toCreateMap() {
    // Strip secrets / tokens from metadata.
    final safeMeta = <String, Object?>{};
    for (final entry in metadata.entries) {
      final key = entry.key.toLowerCase();
      if (key.contains('token') ||
          key.contains('password') ||
          key.contains('secret') ||
          key.contains('api_key')) {
        continue;
      }
      safeMeta[entry.key] = entry.value;
    }
    return <String, Object?>{
      'id': id,
      'businessId': businessId,
      'userId': userId,
      'userName': userName,
      'userRole': userRole,
      'actionType': actionType.storedValue,
      'entityType': entityType,
      'entityId': entityId,
      'entityLabel': entityLabel,
      'description': description,
      'branchId': branchId,
      'metadata': safeMeta,
      'createdAt': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
      'deviceId': deviceId,
      'platform': platform,
    };
  }

  static String? _optionalString(Object? value) {
    final normalized = '$value'.trim();
    return normalized.isEmpty || normalized == 'null' ? null : normalized;
  }
}

List<StaffActivity> filterStaffActivityForBranch({
  required Iterable<StaffActivity> activities,
  required String selectedBranchId,
  required bool isMainBranch,
}) {
  return activities
      .where((activity) {
        final branchId = activity.branchId;
        if (branchId == null || branchId.isEmpty) return isMainBranch;
        return branchId == selectedBranchId;
      })
      .toList(growable: false);
}
