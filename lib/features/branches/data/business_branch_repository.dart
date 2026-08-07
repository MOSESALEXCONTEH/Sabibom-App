import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/business_branch.dart';

class BranchException implements Exception {
  const BranchException(this.code, {this.message});

  final String code;
  final String? message;
}

abstract class BusinessBranchRepository {
  Stream<List<BusinessBranch>> watchBranches(String businessId);
  Stream<BusinessBranch?> watchBranch(String businessId, String branchId);
  Future<List<BusinessBranch>> listBranches(String businessId);
  Future<BusinessBranch> ensureMainBranch(
    String businessId, {
    String? createdBy,
  });
  Future<BusinessBranch?> getBranch(String businessId, String branchId);
  Future<BusinessBranch?> getBranchByCode(String businessId, String code);
  Future<BusinessBranch> createBranch({
    required String businessId,
    required String name,
    required String code,
    String? address,
    String? city,
    String? country,
    String? phone,
    String? email,
    String? managerUid,
    required String createdBy,
  });
  Future<BusinessBranch> updateBranch({
    required String businessId,
    required String branchId,
    required String name,
    required String code,
    String? address,
    String? city,
    String? country,
    String? phone,
    String? email,
    String? managerUid,
    BranchStatus? status,
    required String updatedBy,
  });
  Future<void> setBranchStatus({
    required String businessId,
    required String branchId,
    required BranchStatus status,
    required String updatedBy,
  });
}

class FirestoreBusinessBranchRepository implements BusinessBranchRepository {
  FirestoreBusinessBranchRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _business(String businessId) =>
      _firestore.collection('businesses').doc(businessId);

  CollectionReference<Map<String, dynamic>> _branches(String businessId) =>
      _business(businessId).collection('branches');

  DocumentReference<Map<String, dynamic>> _audit(String businessId) =>
      _business(businessId).collection('staff_activity').doc();

  Map<String, Object?> _auditData({
    required String businessId,
    required String userId,
    required String action,
    required BusinessBranch branch,
  }) {
    return {
      'businessId': businessId,
      'userId': userId,
      'userName': 'Team member',
      'userRole': '',
      'actionType': action,
      'entityType': 'branch',
      'entityId': branch.branchId,
      'entityLabel': branch.name,
      'description': action.replaceAll('.', ' '),
      'metadata': {'branchStatus': branch.status.storedValue},
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Future<List<BusinessBranch>> _listBranchesRaw(String businessId) async {
    final snap = await _branches(businessId).get();
    return snap.docs
        .map((doc) => BusinessBranch.fromMap(doc.data(), doc.id, businessId))
        .toList(growable: false);
  }

  Future<void> _assertMainBranchInvariants(String businessId) async {
    final branches = await _listBranchesRaw(businessId);
    final mains = branches.where((branch) => branch.isMainBranch).toList();
    if (mains.length > 1) {
      throw const BranchException(
        'failed-precondition',
        message: 'A business cannot have more than one main branch.',
      );
    }
  }

  Future<String?> _validateManagerUid(
    String businessId,
    String? managerUid,
  ) async {
    final normalized = managerUid?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    final member = await _business(
      businessId,
    ).collection('members').doc(normalized).get();
    if (!member.exists || member.data() == null) {
      throw const BranchException(
        'failed-precondition',
        message: 'Assigned manager must belong to this business.',
      );
    }
    final status = (member.data()!['status'] as String?)?.trim().toLowerCase();
    if (status != null && status.isNotEmpty && status != 'active') {
      throw const BranchException(
        'failed-precondition',
        message: 'Assigned manager must be active.',
      );
    }
    return normalized;
  }

  Future<void> _assertCanDeactivateBranch({
    required String businessId,
    required String branchId,
  }) async {
    final branches = await _listBranchesRaw(businessId);
    final matches = branches
        .where((branch) => branch.branchId == branchId)
        .toList(growable: false);
    if (matches.isEmpty) {
      throw const BranchException('not-found');
    }
    final target = matches.first;
    if (target.isMainBranch) {
      throw const BranchException(
        'failed-precondition',
        message: 'Main branch must remain active.',
      );
    }
    if (!target.isActive) {
      return;
    }
    final activeCount = branches.where((branch) => branch.isActive).length;
    if (activeCount <= 1) {
      throw const BranchException(
        'failed-precondition',
        message: 'At least one active branch is required.',
      );
    }
  }

  @override
  Stream<List<BusinessBranch>> watchBranches(String businessId) {
    if (businessId.trim().isEmpty) {
      return Stream.value(const <BusinessBranch>[]);
    }
    return _branches(businessId).snapshots().map((snapshot) {
      final branches = snapshot.docs
          .map((doc) => BusinessBranch.fromMap(doc.data(), doc.id, businessId))
          .toList();
      branches.sort((a, b) {
        if (a.isMainBranch != b.isMainBranch) {
          return a.isMainBranch ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return branches;
    });
  }

  @override
  Stream<BusinessBranch?> watchBranch(String businessId, String branchId) {
    if (businessId.trim().isEmpty || branchId.trim().isEmpty) {
      return Stream.value(null);
    }
    return _branches(businessId).doc(branchId).snapshots().map((snapshot) {
      final data = snapshot.data();
      return snapshot.exists && data != null
          ? BusinessBranch.fromMap(data, snapshot.id, businessId)
          : null;
    });
  }

  @override
  Future<List<BusinessBranch>> listBranches(String businessId) async {
    if (businessId.trim().isEmpty) return const <BusinessBranch>[];
    final branches = await _listBranchesRaw(businessId);
    await _assertMainBranchInvariants(businessId);
    branches.sort((a, b) {
      if (a.isMainBranch != b.isMainBranch) {
        return a.isMainBranch ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return branches;
  }

  @override
  Future<BusinessBranch> ensureMainBranch(
    String businessId, {
    String? createdBy,
  }) async {
    if (businessId.trim().isEmpty) {
      throw const BranchException('failed-precondition');
    }
    final ref = _branches(businessId).doc('main');
    final snap = await ref.get();
    if (snap.exists && snap.data() != null) {
      final current = BusinessBranch.fromMap(snap.data()!, 'main', businessId);
      await ref.set({
        'isMainBranch': true,
        'status': BranchStatus.active.storedValue,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _assertMainBranchInvariants(businessId);
      return current.copyWith(isMainBranch: true, status: BranchStatus.active);
    }
    final branch = BusinessBranch.main(
      businessId: businessId,
      createdBy: createdBy,
    );
    await ref.set(branch.toMap(forCreate: true), SetOptions(merge: true));
    await _assertMainBranchInvariants(businessId);
    return branch;
  }

  @override
  Future<BusinessBranch?> getBranch(String businessId, String branchId) async {
    if (businessId.trim().isEmpty || branchId.trim().isEmpty) return null;
    final snap = await _branches(businessId).doc(branchId).get();
    if (!snap.exists || snap.data() == null) return null;
    return BusinessBranch.fromMap(snap.data()!, snap.id, businessId);
  }

  @override
  Future<BusinessBranch?> getBranchByCode(
    String businessId,
    String code,
  ) async {
    final normalized = normalizeBranchCode(code);
    if (businessId.trim().isEmpty || normalized.isEmpty) return null;
    final snap = await _branches(
      businessId,
    ).where('code', isEqualTo: normalized).limit(1).get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return BusinessBranch.fromMap(doc.data(), doc.id, businessId);
  }

  @override
  Future<BusinessBranch> createBranch({
    required String businessId,
    required String name,
    required String code,
    String? address,
    String? city,
    String? country,
    String? phone,
    String? email,
    String? managerUid,
    required String createdBy,
  }) async {
    if (businessId.trim().isEmpty) {
      throw const BranchException('failed-precondition');
    }
    final normalizedCode = normalizeBranchCode(code);
    if (!isValidBranchCode(normalizedCode)) {
      throw const BranchException(
        'invalid-argument',
        message: 'Invalid branch code.',
      );
    }
    if (normalizedCode == 'MAIN') {
      throw const BranchException(
        'already-exists',
        message: 'Main branch already exists.',
      );
    }
    final duplicate = await getBranchByCode(businessId, normalizedCode);
    if (duplicate != null) {
      throw const BranchException(
        'already-exists',
        message: 'Branch code already exists.',
      );
    }
    await _assertMainBranchInvariants(businessId);
    final normalizedManagerUid = await _validateManagerUid(
      businessId,
      managerUid,
    );
    final ref = _branches(businessId).doc();
    final branch = BusinessBranch(
      branchId: ref.id,
      businessId: businessId,
      name: name.trim(),
      code: normalizedCode,
      address: address?.trim().isNotEmpty == true ? address!.trim() : null,
      city: city?.trim().isNotEmpty == true ? city!.trim() : null,
      country: country?.trim().isNotEmpty == true ? country!.trim() : null,
      phone: phone?.trim().isNotEmpty == true ? phone!.trim() : null,
      email: email?.trim().isNotEmpty == true ? email!.trim() : null,
      managerUid: normalizedManagerUid,
      isMainBranch: false,
      status: BranchStatus.active,
      createdBy: createdBy,
    );
    final audit = _audit(businessId);
    final batch = _firestore.batch()
      ..set(ref, branch.toMap(forCreate: true))
      ..set(
        audit,
        _auditData(
          businessId: businessId,
          userId: createdBy,
          action: 'branch.created',
          branch: branch,
        ),
      );
    await batch.commit();
    return branch;
  }

  @override
  Future<BusinessBranch> updateBranch({
    required String businessId,
    required String branchId,
    required String name,
    required String code,
    String? address,
    String? city,
    String? country,
    String? phone,
    String? email,
    String? managerUid,
    BranchStatus? status,
    required String updatedBy,
  }) async {
    final current = await getBranch(businessId, branchId);
    if (current == null) {
      throw const BranchException('not-found');
    }
    final normalizedCode = normalizeBranchCode(code);
    if (!isValidBranchCode(normalizedCode)) {
      throw const BranchException(
        'invalid-argument',
        message: 'Invalid branch code.',
      );
    }
    if (current.isMainBranch && normalizedCode != 'MAIN') {
      throw const BranchException(
        'failed-precondition',
        message: 'Main branch code cannot change.',
      );
    }
    final duplicate = await getBranchByCode(businessId, normalizedCode);
    if (duplicate != null && duplicate.branchId != branchId) {
      throw const BranchException(
        'already-exists',
        message: 'Branch code already exists.',
      );
    }
    final nextStatus = status ?? current.status;
    if (current.isMainBranch && nextStatus != BranchStatus.active) {
      throw const BranchException(
        'failed-precondition',
        message: 'Main branch must remain active.',
      );
    }
    if (nextStatus != BranchStatus.active) {
      await _assertCanDeactivateBranch(
        businessId: businessId,
        branchId: current.branchId,
      );
    }
    final normalizedManagerUid = await _validateManagerUid(
      businessId,
      managerUid,
    );
    final updated = current.copyWith(
      name: name.trim(),
      code: normalizedCode,
      address: address?.trim().isNotEmpty == true ? address!.trim() : null,
      city: city?.trim().isNotEmpty == true ? city!.trim() : null,
      country: country?.trim().isNotEmpty == true ? country!.trim() : null,
      phone: phone?.trim().isNotEmpty == true ? phone!.trim() : null,
      email: email?.trim().isNotEmpty == true ? email!.trim() : null,
      managerUid: normalizedManagerUid,
      status: nextStatus,
    );
    final audit = _audit(businessId);
    final batch = _firestore.batch()
      ..set(_branches(businessId).doc(branchId), {
        ...updated.toMap(),
        'updatedBy': updatedBy,
      }, SetOptions(merge: true))
      ..set(
        audit,
        _auditData(
          businessId: businessId,
          userId: updatedBy,
          action: 'branch.updated',
          branch: updated,
        ),
      );
    await batch.commit();
    await _assertMainBranchInvariants(businessId);
    return updated;
  }

  @override
  Future<void> setBranchStatus({
    required String businessId,
    required String branchId,
    required BranchStatus status,
    required String updatedBy,
  }) async {
    final branch = await getBranch(businessId, branchId);
    if (branch == null) {
      throw const BranchException('not-found');
    }
    if (branch.isMainBranch && status != BranchStatus.active) {
      throw const BranchException(
        'failed-precondition',
        message: 'Main branch must remain active.',
      );
    }
    if (status != BranchStatus.active) {
      await _assertCanDeactivateBranch(
        businessId: businessId,
        branchId: branch.branchId,
      );
    }
    final updated = branch.copyWith(status: status);
    final action = switch (status) {
      BranchStatus.active => 'branch.reactivated',
      BranchStatus.inactive => 'branch.deactivated',
      BranchStatus.archived => 'branch.archived',
    };
    final audit = _audit(businessId);
    final batch = _firestore.batch()
      ..set(_branches(businessId).doc(branchId), {
        'status': status.storedValue,
        'updatedBy': updatedBy,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true))
      ..set(
        audit,
        _auditData(
          businessId: businessId,
          userId: updatedBy,
          action: action,
          branch: updated,
        ),
      );
    await batch.commit();
    await _assertMainBranchInvariants(businessId);
  }
}
