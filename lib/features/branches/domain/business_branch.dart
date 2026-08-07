import 'package:cloud_firestore/cloud_firestore.dart';

enum BranchStatus {
  active,
  inactive,
  archived;

  String get storedValue => name;

  static BranchStatus fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return BranchStatus.values.firstWhere(
      (status) => status.name == raw,
      orElse: () => BranchStatus.active,
    );
  }
}

enum BranchViewMode {
  singleBranch,
  allBranches,
}

bool isValidBranchCode(String value) {
  final code = value.trim();
  if (code.length < 2 || code.length > 12) return false;
  return RegExp(r'^[A-Z0-9_-]+$').hasMatch(code);
}

String normalizeBranchCode(String value) => value.trim().toUpperCase();

String? normalizeBranchId(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

bool matchesBranchScope(Map<String, dynamic> data, String? branchId) {
  return matchesBranchScopeWithMode(
    data,
    branchId: branchId,
    viewMode: BranchViewMode.singleBranch,
  );
}

bool matchesBranchScopeWithMode(
  Map<String, dynamic> data, {
  required BranchViewMode viewMode,
  String? branchId,
  String mainBranchId = 'main',
}) {
  if (viewMode == BranchViewMode.allBranches) {
    return true;
  }
  final normalized = normalizeBranchId(branchId);
  if (normalized == null) return true;
  final stored = normalizeBranchId(data['branchId'] as String?);
  if (stored == normalized) return true;
  // Legacy branchless data is compatible with main branch only.
  if (stored == null && normalized == normalizeBranchId(mainBranchId)) {
    return true;
  }
  return false;
}

bool hasMainBranch(Iterable<BusinessBranch> branches) {
  return branches.any((branch) => branch.isMainBranch);
}

bool canHaveMultipleMainBranches(List<BusinessBranch> branches) {
  return branches.where((branch) => branch.isMainBranch).length > 1;
}

bool hasDuplicateBranchCode(
  Iterable<BusinessBranch> branches,
  String code, {
  String? excludingBranchId,
}) {
  final normalized = normalizeBranchCode(code);
  if (normalized.isEmpty) return false;
  for (final branch in branches) {
    if (excludingBranchId != null && branch.branchId == excludingBranchId) {
      continue;
    }
    if (branch.code == normalized) {
      return true;
    }
  }
  return false;
}

class BusinessBranch {
  const BusinessBranch({
    required this.branchId,
    required this.businessId,
    required this.name,
    required this.code,
    required this.status,
    required this.isMainBranch,
    this.address,
    this.city,
    this.country,
    this.phone,
    this.email,
    this.managerUid,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  });

  final String branchId;
  final String businessId;
  final String name;
  final String code;
  final String? address;
  final String? city;
  final String? country;
  final String? phone;
  final String? email;
  final String? managerUid;
  final bool isMainBranch;
  final BranchStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;

  bool get isActive => status == BranchStatus.active;

  bool get isSelectable => status == BranchStatus.active;

  factory BusinessBranch.main({
    required String businessId,
    String? createdBy,
  }) {
    return BusinessBranch(
      branchId: 'main',
      businessId: businessId,
      name: 'Main Branch',
      code: 'MAIN',
      status: BranchStatus.active,
      isMainBranch: true,
      createdBy: createdBy,
    );
  }

  factory BusinessBranch.fromMap(
    Map<String, dynamic> data,
    String branchId, [
    String? businessId,
  ]) {
    return BusinessBranch(
      branchId: branchId,
      businessId: businessId ?? (data['businessId'] as String? ?? ''),
      name: (data['name'] as String?)?.trim() ?? 'Branch',
      code: normalizeBranchCode(data['code'] as String? ?? branchId),
      address: _string(data['address']),
      city: _string(data['city']),
      country: _string(data['country']),
      phone: _string(data['phone']),
      email: _string(data['email']),
      managerUid: _string(data['managerUid']),
      isMainBranch: data['isMainBranch'] == true,
      status: BranchStatus.fromStorage(data['status']),
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
      createdBy: _string(data['createdBy']),
    );
  }

  Map<String, Object?> toMap({bool forCreate = false}) {
    return <String, Object?>{
      'branchId': branchId,
      'businessId': businessId,
      'name': name,
      'code': code,
      'address': address,
      'city': city,
      'country': country,
      'phone': phone,
      'email': email,
      'managerUid': managerUid,
      'isMainBranch': isMainBranch,
      'status': status.storedValue,
      if (forCreate) 'createdAt': FieldValue.serverTimestamp(),
      if (forCreate) 'createdBy': createdBy,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  BusinessBranch copyWith({
    String? name,
    String? code,
    String? address,
    String? city,
    String? country,
    String? phone,
    String? email,
    String? managerUid,
    BranchStatus? status,
    bool? isMainBranch,
    String? createdBy,
  }) {
    return BusinessBranch(
      branchId: branchId,
      businessId: businessId,
      name: name ?? this.name,
      code: code ?? this.code,
      address: address ?? this.address,
      city: city ?? this.city,
      country: country ?? this.country,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      managerUid: managerUid ?? this.managerUid,
      isMainBranch: isMainBranch ?? this.isMainBranch,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  static String? _string(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
