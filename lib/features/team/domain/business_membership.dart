import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_permission.dart';
import 'system_roles.dart';

enum MemberStatus {
  invited,
  active,
  disabled,
  removed;

  String get storedValue => name;

  static MemberStatus fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    // Legacy "pending" maps to invited.
    if (raw == 'pending') return MemberStatus.invited;
    return MemberStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => MemberStatus.active,
    );
  }

  String get label => switch (this) {
    MemberStatus.invited => 'Invited',
    MemberStatus.active => 'Active',
    MemberStatus.disabled => 'Disabled',
    MemberStatus.removed => 'Removed',
  };

  bool get canAccessBusiness => this == MemberStatus.active;
}

/// Full membership document at businesses/{businessId}/members/{uid}.
class BusinessMembership {
  const BusinessMembership({
    required this.uid,
    required this.businessId,
    required this.roleId,
    required this.roleName,
    required this.status,
    required this.isOwner,
    required this.permissions,
    this.displayName,
    this.email,
    this.phone,
    this.photoUrl,
    this.assignedBranchIds = const {},
    this.allBranchesAccess = false,
    this.defaultBranchId,
    this.permissionOverrides = const {},
    this.permissionDenials = const {},
    this.invitedBy,
    this.invitationId,
    this.joinedAt,
    this.lastActiveAt,
    this.createdAt,
    this.updatedAt,
    this.disabledAt,
    this.disabledBy,
    this.disableReason,
    this.removedAt,
    this.removedBy,
    this.removeReason,
    this.updatedBy,
  });

  final String uid;
  final String businessId;
  final String? displayName;
  final String? email;
  final String? phone;
  final String? photoUrl;
  final Set<String> assignedBranchIds;
  final bool allBranchesAccess;
  final String? defaultBranchId;
  final String roleId;
  final String roleName;
  final Set<AppPermission> permissions;
  final Set<AppPermission> permissionOverrides;
  final Set<AppPermission> permissionDenials;
  final MemberStatus status;
  final bool isOwner;
  final String? invitedBy;
  final String? invitationId;
  final DateTime? joinedAt;
  final DateTime? lastActiveAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? disabledAt;
  final String? disabledBy;
  final String? disableReason;
  final DateTime? removedAt;
  final String? removedBy;
  final String? removeReason;
  final String? updatedBy;

  String get effectiveDisplayName {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final mail = email?.trim();
    if (mail != null && mail.isNotEmpty) return mail;
    final phoneValue = phone?.trim();
    if (phoneValue != null && phoneValue.isNotEmpty) return phoneValue;
    return 'Team member';
  }

  /// Effective permissions: owners always get everything.
  Set<AppPermission> get effectivePermissions {
    if (isOwner || roleId == SystemRoleIds.owner) {
      return AppPermission.values.toSet();
    }
    final resolved = {...permissions, ...permissionOverrides};
    return resolved.difference(permissionDenials);
  }

  bool hasPermission(AppPermission permission) {
    if (!status.canAccessBusiness) return false;
    if (isOwner || roleId == SystemRoleIds.owner) return true;
    if (permissionDenials.contains(permission)) return false;
    return effectivePermissions.contains(permission);
  }

  bool hasBranchAccess(String branchId) {
    final normalized = branchId.trim();
    if (normalized.isEmpty) return false;
    if (!status.canAccessBusiness) return false;
    if (isOwner || roleId == SystemRoleIds.owner) return true;
    if (permissionDenials.contains(AppPermission.viewBranch)) return false;
    final roleHasDefaultBranchAccess = SystemRoleIds.all.contains(roleId);
    return assignedBranchIds.contains(normalized) &&
        (hasPermission(AppPermission.viewBranch) || roleHasDefaultBranchAccess);
  }

  bool get canUseAllBranchesReports {
    return hasPermission(AppPermission.viewCombinedReports);
  }

  bool hasAnyPermission(Iterable<AppPermission> required) {
    for (final p in required) {
      if (hasPermission(p)) return true;
    }
    return false;
  }

  bool hasAllPermissions(Iterable<AppPermission> required) {
    for (final p in required) {
      if (!hasPermission(p)) return false;
    }
    return true;
  }

  factory BusinessMembership.fromMap(
    String uid,
    String businessId,
    Map<String, dynamic> data,
  ) {
    final roleRaw = (data['roleId'] as String?)?.trim().isNotEmpty == true
        ? (data['roleId'] as String).trim()
        : ((data['role'] as String?)?.trim() ?? SystemRoleIds.cashier);
    final roleName = (data['roleName'] as String?)?.trim().isNotEmpty == true
        ? (data['roleName'] as String).trim()
        : SystemRoles.labelFor(roleRaw);
    final isOwner =
        data['isOwner'] == true ||
        roleRaw == SystemRoleIds.owner ||
        (data['role'] as String?) == 'owner';

    final permissionCodes = <Object?>[
      ...?(data['permissions'] as List?),
      ...?(data['permissionOverrides'] as List?),
    ];
    var permissions = AppPermission.parseMany(permissionCodes);
    if (permissions.isEmpty && !isOwner) {
      permissions = SystemRoles.defaultPermissionsFor(roleRaw);
    }

    return BusinessMembership(
      uid: uid,
      businessId: businessId,
      displayName:
          (data['displayName'] as String?) ?? (data['fullName'] as String?),
      email: data['email'] as String?,
      phone: data['phone'] as String?,
      photoUrl: data['photoUrl'] as String?,
      assignedBranchIds: {
        ...?(data['assignedBranchIds'] as List?)?.map((value) => '$value'),
      },
      allBranchesAccess: data['allBranchesAccess'] == true,
      defaultBranchId: data['defaultBranchId'] as String?,
      roleId: roleRaw,
      roleName: roleName,
      permissions: permissions,
      permissionOverrides: AppPermission.parseMany(
        data['permissionOverrides'] as List? ?? const [],
      ),
      permissionDenials: AppPermission.parseMany(
        data['permissionDenials'] as List? ?? const [],
      ),
      status: MemberStatus.fromStorage(data['status']),
      isOwner: isOwner,
      invitedBy: data['invitedBy'] as String?,
      invitationId: data['invitationId'] as String?,
      joinedAt: _asDate(data['joinedAt']),
      lastActiveAt: _asDate(data['lastActiveAt']),
      createdAt: _asDate(data['createdAt']),
      updatedAt: _asDate(data['updatedAt']),
      disabledAt: _asDate(data['disabledAt']),
      disabledBy: data['disabledBy'] as String?,
      disableReason: data['disableReason'] as String?,
      removedAt: _asDate(data['removedAt']),
      removedBy: data['removedBy'] as String?,
      removeReason: data['removeReason'] as String?,
      updatedBy: data['updatedBy'] as String?,
    );
  }

  Map<String, Object?> toMap({bool forCreate = false}) {
    return <String, Object?>{
      'uid': uid,
      'userId': uid, // legacy compatibility
      'businessId': businessId,
      'displayName': displayName,
      'email': email,
      'phone': phone,
      'photoUrl': photoUrl,
      'assignedBranchIds': assignedBranchIds.toList(),
      'allBranchesAccess': allBranchesAccess,
      'defaultBranchId': defaultBranchId,
      'roleId': roleId,
      'role': roleId, // legacy compatibility
      'roleName': roleName,
      'permissions': permissions.map((p) => p.code).toList(),
      'permissionOverrides': permissionOverrides.map((p) => p.code).toList(),
      'permissionDenials': permissionDenials.map((p) => p.code).toList(),
      'status': status.storedValue,
      'isOwner': isOwner,
      'invitedBy': invitedBy,
      'invitationId': invitationId,
      if (forCreate) 'joinedAt': FieldValue.serverTimestamp(),
      if (forCreate) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'disabledAt': disabledAt == null ? null : Timestamp.fromDate(disabledAt!),
      'disabledBy': disabledBy,
      'disableReason': disableReason,
      'removedAt': removedAt == null ? null : Timestamp.fromDate(removedAt!),
      'removedBy': removedBy,
      'removeReason': removeReason,
      'updatedBy': updatedBy,
    };
  }

  BusinessMembership copyWith({
    String? displayName,
    String? email,
    String? phone,
    String? photoUrl,
    String? roleId,
    String? roleName,
    Set<AppPermission>? permissions,
    Set<AppPermission>? permissionOverrides,
    Set<AppPermission>? permissionDenials,
    Set<String>? assignedBranchIds,
    bool? allBranchesAccess,
    String? defaultBranchId,
    MemberStatus? status,
    bool? isOwner,
    DateTime? disabledAt,
    String? disabledBy,
    String? disableReason,
    DateTime? removedAt,
    String? removedBy,
    String? removeReason,
    String? updatedBy,
  }) {
    return BusinessMembership(
      uid: uid,
      businessId: businessId,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      photoUrl: photoUrl ?? this.photoUrl,
      assignedBranchIds: assignedBranchIds ?? this.assignedBranchIds,
      allBranchesAccess: allBranchesAccess ?? this.allBranchesAccess,
      defaultBranchId: defaultBranchId ?? this.defaultBranchId,
      roleId: roleId ?? this.roleId,
      roleName: roleName ?? this.roleName,
      permissions: permissions ?? this.permissions,
      permissionOverrides: permissionOverrides ?? this.permissionOverrides,
      permissionDenials: permissionDenials ?? this.permissionDenials,
      status: status ?? this.status,
      isOwner: isOwner ?? this.isOwner,
      invitedBy: invitedBy,
      invitationId: invitationId,
      joinedAt: joinedAt,
      lastActiveAt: lastActiveAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      disabledAt: disabledAt ?? this.disabledAt,
      disabledBy: disabledBy ?? this.disabledBy,
      disableReason: disableReason ?? this.disableReason,
      removedAt: removedAt ?? this.removedAt,
      removedBy: removedBy ?? this.removedBy,
      removeReason: removeReason ?? this.removeReason,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
