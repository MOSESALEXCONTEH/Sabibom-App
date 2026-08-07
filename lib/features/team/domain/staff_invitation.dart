import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_permission.dart';

enum InvitationStatus {
  pending,
  accepted,
  expired,
  cancelled;

  String get storedValue => name;

  static InvitationStatus fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return InvitationStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => InvitationStatus.pending,
    );
  }

  String get label => switch (this) {
    InvitationStatus.pending => 'Pending',
    InvitationStatus.accepted => 'Accepted',
    InvitationStatus.expired => 'Expired',
    InvitationStatus.cancelled => 'Cancelled',
  };
}

class StaffInvitation {
  const StaffInvitation({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.roleId,
    required this.roleName,
    required this.permissionsSnapshot,
    required this.status,
    required this.invitedBy,
    required this.inviteCode,
    required this.expiresAt,
    this.email,
    this.normalizedEmail,
    this.phone,
    this.normalizedPhone,
    this.displayName,
    this.invitedByName,
    this.message,
    this.acceptedBy,
    this.acceptedAt,
    this.createdAt,
    this.updatedAt,
    this.cancelledAt,
    this.cancelledBy,
  });

  final String id;
  final String businessId;
  final String businessName;
  final String? email;
  final String? normalizedEmail;
  final String? phone;
  final String? normalizedPhone;
  final String? displayName;
  final String roleId;
  final String roleName;
  final Set<AppPermission> permissionsSnapshot;
  final InvitationStatus status;
  final String invitedBy;
  final String? invitedByName;
  final String inviteCode;
  final DateTime expiresAt;
  final String? message;
  final String? acceptedBy;
  final DateTime? acceptedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? cancelledAt;
  final String? cancelledBy;

  bool get isExpired {
    if (status == InvitationStatus.expired) return true;
    return DateTime.now().isAfter(expiresAt);
  }

  bool get isAcceptable =>
      status == InvitationStatus.pending && !isExpired;

  factory StaffInvitation.fromMap(String id, Map<String, dynamic> data) {
    return StaffInvitation(
      id: id,
      businessId: (data['businessId'] as String?)?.trim() ?? '',
      businessName: (data['businessName'] as String?)?.trim() ?? 'Business',
      email: data['email'] as String?,
      normalizedEmail: data['normalizedEmail'] as String?,
      phone: data['phone'] as String?,
      normalizedPhone: data['normalizedPhone'] as String?,
      displayName: data['displayName'] as String?,
      roleId: (data['roleId'] as String?)?.trim() ?? 'cashier',
      roleName: (data['roleName'] as String?)?.trim() ?? 'Cashier',
      permissionsSnapshot: AppPermission.parseMany(
        data['permissionsSnapshot'] as List? ?? const [],
      ),
      status: InvitationStatus.fromStorage(data['status']),
      invitedBy: (data['invitedBy'] as String?)?.trim() ?? '',
      invitedByName: data['invitedByName'] as String?,
      inviteCode: (data['inviteCode'] as String?)?.trim() ?? '',
      expiresAt: _asDate(data['expiresAt']) ??
          DateTime.now().add(const Duration(days: 7)),
      message: data['message'] as String?,
      acceptedBy: data['acceptedBy'] as String?,
      acceptedAt: _asDate(data['acceptedAt']),
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
      cancelledAt: _asDate(data['cancelledAt']),
      cancelledBy: data['cancelledBy'] as String?,
    );
  }

  Map<String, Object?> toCreateMap() {
    return <String, Object?>{
      'id': id,
      'businessId': businessId,
      'businessName': businessName,
      'email': email,
      'normalizedEmail': normalizedEmail,
      'phone': phone,
      'normalizedPhone': normalizedPhone,
      'displayName': displayName,
      'roleId': roleId,
      'roleName': roleName,
      'permissionsSnapshot':
          permissionsSnapshot.map((p) => p.code).toList(),
      'status': status.storedValue,
      'invitedBy': invitedBy,
      'invitedByName': invitedByName,
      'inviteCode': inviteCode,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'message': message,
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
