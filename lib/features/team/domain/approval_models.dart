import 'package:cloud_firestore/cloud_firestore.dart';

enum ApprovalStatus {
  pending,
  approved,
  rejected,
  cancelled,
  expired;

  String get storedValue => name;

  static ApprovalStatus fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return ApprovalStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => ApprovalStatus.pending,
    );
  }

  String get label => switch (this) {
    ApprovalStatus.pending => 'Pending',
    ApprovalStatus.approved => 'Approved',
    ApprovalStatus.rejected => 'Rejected',
    ApprovalStatus.cancelled => 'Cancelled',
    ApprovalStatus.expired => 'Expired',
  };
}

enum ApprovalRequestType {
  voidSale('void_sale'),
  voidExpense('void_expense'),
  priceOverride('price_override'),
  largeDiscount('large_discount'),
  stockCorrection('stock_correction'),
  customerBalanceAdjustment('customer_balance_adjustment'),
  supplierOverpayment('supplier_overpayment'),
  purchaseReturn('purchase_return');

  const ApprovalRequestType(this.storedValue);
  final String storedValue;

  static ApprovalRequestType fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return ApprovalRequestType.values.firstWhere(
      (t) => t.storedValue == raw || t.name.toLowerCase() == raw,
      orElse: () => ApprovalRequestType.voidSale,
    );
  }

  String get label => switch (this) {
    ApprovalRequestType.voidSale => 'Void sale',
    ApprovalRequestType.voidExpense => 'Void expense',
    ApprovalRequestType.priceOverride => 'Price override',
    ApprovalRequestType.largeDiscount => 'Large discount',
    ApprovalRequestType.stockCorrection => 'Stock correction',
    ApprovalRequestType.customerBalanceAdjustment =>
      'Customer balance adjustment',
    ApprovalRequestType.supplierOverpayment => 'Supplier overpayment',
    ApprovalRequestType.purchaseReturn => 'Purchase return',
  };
}

class ApprovalRequest {
  const ApprovalRequest({
    required this.id,
    required this.businessId,
    required this.type,
    required this.status,
    required this.requestedBy,
    required this.requestedByName,
    required this.entityType,
    required this.entityId,
    required this.requestedAt,
    this.requestedByRole,
    this.assignedApproverIds = const [],
    this.entitySnapshot = const {},
    this.reason,
    this.expiresAt,
    this.approvedBy,
    this.approvedByName,
    this.approvedAt,
    this.rejectedBy,
    this.rejectedByName,
    this.rejectedAt,
    this.rejectionReason,
    this.cancelledAt,
    this.updatedAt,
  });

  final String id;
  final String businessId;
  final ApprovalRequestType type;
  final ApprovalStatus status;
  final String requestedBy;
  final String requestedByName;
  final String? requestedByRole;
  final List<String> assignedApproverIds;
  final String entityType;
  final String entityId;
  final Map<String, Object?> entitySnapshot;
  final String? reason;
  final DateTime requestedAt;
  final DateTime? expiresAt;
  final String? approvedBy;
  final String? approvedByName;
  final DateTime? approvedAt;
  final String? rejectedBy;
  final String? rejectedByName;
  final DateTime? rejectedAt;
  final String? rejectionReason;
  final DateTime? cancelledAt;
  final DateTime? updatedAt;

  bool get isPending =>
      status == ApprovalStatus.pending &&
      (expiresAt == null || DateTime.now().isBefore(expiresAt!));

  factory ApprovalRequest.fromMap(String id, Map<String, dynamic> data) {
    return ApprovalRequest(
      id: id,
      businessId: (data['businessId'] as String?) ?? '',
      type: ApprovalRequestType.fromStorage(data['type']),
      status: ApprovalStatus.fromStorage(data['status']),
      requestedBy: (data['requestedBy'] as String?) ?? '',
      requestedByName: (data['requestedByName'] as String?) ?? 'Staff',
      requestedByRole: data['requestedByRole'] as String?,
      assignedApproverIds: (data['assignedApproverIds'] as List?)
              ?.map((e) => '$e')
              .toList() ??
          const [],
      entityType: (data['entityType'] as String?) ?? '',
      entityId: (data['entityId'] as String?) ?? '',
      entitySnapshot: Map<String, Object?>.from(
        (data['entitySnapshot'] as Map?)?.map(
              (k, v) => MapEntry('$k', v as Object?),
            ) ??
            const {},
      ),
      reason: data['reason'] as String?,
      requestedAt: data['requestedAt'] is Timestamp
          ? (data['requestedAt'] as Timestamp).toDate()
          : DateTime.now(),
      expiresAt: data['expiresAt'] is Timestamp
          ? (data['expiresAt'] as Timestamp).toDate()
          : null,
      approvedBy: data['approvedBy'] as String?,
      approvedByName: data['approvedByName'] as String?,
      approvedAt: data['approvedAt'] is Timestamp
          ? (data['approvedAt'] as Timestamp).toDate()
          : null,
      rejectedBy: data['rejectedBy'] as String?,
      rejectedByName: data['rejectedByName'] as String?,
      rejectedAt: data['rejectedAt'] is Timestamp
          ? (data['rejectedAt'] as Timestamp).toDate()
          : null,
      rejectionReason: data['rejectionReason'] as String?,
      cancelledAt: data['cancelledAt'] is Timestamp
          ? (data['cancelledAt'] as Timestamp).toDate()
          : null,
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, Object?> toCreateMap() {
    return <String, Object?>{
      'id': id,
      'businessId': businessId,
      'type': type.storedValue,
      'status': status.storedValue,
      'requestedBy': requestedBy,
      'requestedByName': requestedByName,
      'requestedByRole': requestedByRole,
      'assignedApproverIds': assignedApproverIds,
      'entityType': entityType,
      'entityId': entityId,
      'entitySnapshot': entitySnapshot,
      'reason': reason,
      'requestedAt': FieldValue.serverTimestamp(),
      'expiresAt':
          expiresAt == null ? null : Timestamp.fromDate(expiresAt!),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class ApprovalPolicies {
  const ApprovalPolicies({
    this.requireSaleVoidApproval = false,
    this.requireExpenseVoidApproval = false,
    this.requirePriceOverrideApproval = false,
    this.requireStockCorrectionApproval = false,
    this.discountApprovalThresholdPercentage = 20,
    this.discountApprovalThresholdMinor = 0,
    this.purchaseReturnApprovalThresholdMinor = 0,
    this.customerBalanceAdjustmentApproval = false,
    this.supplierOverpaymentApproval = false,
    this.updatedAt,
    this.updatedBy,
  });

  final bool requireSaleVoidApproval;
  final bool requireExpenseVoidApproval;
  final bool requirePriceOverrideApproval;
  final bool requireStockCorrectionApproval;
  final double discountApprovalThresholdPercentage;
  final int discountApprovalThresholdMinor;
  final int purchaseReturnApprovalThresholdMinor;
  final bool customerBalanceAdjustmentApproval;
  final bool supplierOverpaymentApproval;
  final DateTime? updatedAt;
  final String? updatedBy;

  factory ApprovalPolicies.fromMap(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return const ApprovalPolicies();
    return ApprovalPolicies(
      requireSaleVoidApproval: data['requireSaleVoidApproval'] == true,
      requireExpenseVoidApproval: data['requireExpenseVoidApproval'] == true,
      requirePriceOverrideApproval:
          data['requirePriceOverrideApproval'] == true,
      requireStockCorrectionApproval:
          data['requireStockCorrectionApproval'] == true,
      discountApprovalThresholdPercentage:
          (data['discountApprovalThresholdPercentage'] as num?)?.toDouble() ??
              20,
      discountApprovalThresholdMinor:
          (data['discountApprovalThresholdMinor'] as num?)?.toInt() ?? 0,
      purchaseReturnApprovalThresholdMinor:
          (data['purchaseReturnApprovalThresholdMinor'] as num?)?.toInt() ?? 0,
      customerBalanceAdjustmentApproval:
          data['customerBalanceAdjustmentApproval'] == true,
      supplierOverpaymentApproval: data['supplierOverpaymentApproval'] == true,
      updatedBy: data['updatedBy'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'requireSaleVoidApproval': requireSaleVoidApproval,
      'requireExpenseVoidApproval': requireExpenseVoidApproval,
      'requirePriceOverrideApproval': requirePriceOverrideApproval,
      'requireStockCorrectionApproval': requireStockCorrectionApproval,
      'discountApprovalThresholdPercentage':
          discountApprovalThresholdPercentage,
      'discountApprovalThresholdMinor': discountApprovalThresholdMinor,
      'purchaseReturnApprovalThresholdMinor':
          purchaseReturnApprovalThresholdMinor,
      'customerBalanceAdjustmentApproval': customerBalanceAdjustmentApproval,
      'supplierOverpaymentApproval': supplierOverpaymentApproval,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    };
  }

  ApprovalPolicies copyWith({
    bool? requireSaleVoidApproval,
    bool? requireExpenseVoidApproval,
    bool? requirePriceOverrideApproval,
    bool? requireStockCorrectionApproval,
    double? discountApprovalThresholdPercentage,
    int? discountApprovalThresholdMinor,
    int? purchaseReturnApprovalThresholdMinor,
    bool? customerBalanceAdjustmentApproval,
    bool? supplierOverpaymentApproval,
    String? updatedBy,
  }) {
    return ApprovalPolicies(
      requireSaleVoidApproval:
          requireSaleVoidApproval ?? this.requireSaleVoidApproval,
      requireExpenseVoidApproval:
          requireExpenseVoidApproval ?? this.requireExpenseVoidApproval,
      requirePriceOverrideApproval:
          requirePriceOverrideApproval ?? this.requirePriceOverrideApproval,
      requireStockCorrectionApproval:
          requireStockCorrectionApproval ?? this.requireStockCorrectionApproval,
      discountApprovalThresholdPercentage:
          discountApprovalThresholdPercentage ??
              this.discountApprovalThresholdPercentage,
      discountApprovalThresholdMinor:
          discountApprovalThresholdMinor ?? this.discountApprovalThresholdMinor,
      purchaseReturnApprovalThresholdMinor:
          purchaseReturnApprovalThresholdMinor ??
              this.purchaseReturnApprovalThresholdMinor,
      customerBalanceAdjustmentApproval:
          customerBalanceAdjustmentApproval ??
              this.customerBalanceAdjustmentApproval,
      supplierOverpaymentApproval:
          supplierOverpaymentApproval ?? this.supplierOverpaymentApproval,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}
