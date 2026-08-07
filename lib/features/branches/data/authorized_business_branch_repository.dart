import 'dart:async';

import '../../team/domain/app_permission.dart';
import '../../team/domain/business_membership.dart';
import '../domain/business_branch.dart';
import 'business_branch_repository.dart';

class AuthorizedBusinessBranchRepository implements BusinessBranchRepository {
  AuthorizedBusinessBranchRepository({
    required BusinessBranchRepository delegate,
    required BusinessMembership? membership,
  }) : this._(delegate, membership);

  AuthorizedBusinessBranchRepository._(this._delegate, this._membership);

  final BusinessBranchRepository _delegate;
  final BusinessMembership? _membership;

  void _requireManagementAccess(String businessId) {
    final member = _membership;
    if (member == null ||
        member.businessId != businessId ||
        (!member.isOwner &&
            !member.hasPermission(AppPermission.manageBranches))) {
      throw const BranchException(
        'permission-denied',
        message: 'You do not have permission to manage branches.',
      );
    }
  }

  @override
  Stream<List<BusinessBranch>> watchBranches(String businessId) {
    final member = _membership;
    if (member == null || member.businessId != businessId) {
      return Stream.value(const <BusinessBranch>[]);
    }
    if (member.isOwner || member.hasPermission(AppPermission.viewAllBranches)) {
      return _delegate.watchBranches(businessId);
    }
    final ids = member.assignedBranchIds.toList(growable: false);
    if (ids.isEmpty || !ids.any(member.hasBranchAccess)) {
      return Stream.value(const <BusinessBranch>[]);
    }
    final accessibleIds = ids.where(member.hasBranchAccess).toList();
    late StreamController<List<BusinessBranch>> controller;
    final values = <String, BusinessBranch?>{};
    final subscriptions = <StreamSubscription<BusinessBranch?>>[];
    controller = StreamController<List<BusinessBranch>>(
      onListen: () {
        for (final id in accessibleIds) {
          subscriptions.add(
            _delegate.watchBranch(businessId, id).listen((branch) {
              values[id] = branch;
              if (values.length != accessibleIds.length) return;
              final branches = values.values.whereType<BusinessBranch>().toList(
                growable: false,
              );
              controller.add(branches);
            }, onError: controller.addError),
          );
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  @override
  Stream<BusinessBranch?> watchBranch(String businessId, String branchId) {
    if (_membership?.hasBranchAccess(branchId) != true &&
        _membership?.isOwner != true) {
      return Stream.value(null);
    }
    return _delegate.watchBranch(businessId, branchId);
  }

  @override
  Future<List<BusinessBranch>> listBranches(String businessId) async {
    final member = _membership;
    if (member == null || member.businessId != businessId) return const [];
    if (member.isOwner || member.hasPermission(AppPermission.viewAllBranches)) {
      return _delegate.listBranches(businessId);
    }
    final accessibleIds = member.assignedBranchIds.where(
      member.hasBranchAccess,
    );
    final branches = await Future.wait(
      accessibleIds.map(
        (branchId) => _delegate.getBranch(businessId, branchId),
      ),
    );
    return branches.whereType<BusinessBranch>().toList(growable: false);
  }

  @override
  Future<BusinessBranch?> getBranch(String businessId, String branchId) {
    final member = _membership;
    if (member == null ||
        member.businessId != businessId ||
        (!member.isOwner &&
            !member.hasPermission(AppPermission.viewAllBranches) &&
            !member.hasBranchAccess(branchId))) {
      return Future.value(null);
    }
    return _delegate.getBranch(businessId, branchId);
  }

  @override
  Future<BusinessBranch?> getBranchByCode(
    String businessId,
    String code,
  ) async {
    final member = _membership;
    if (member == null || member.businessId != businessId) return null;
    if (member.isOwner || member.hasPermission(AppPermission.viewAllBranches)) {
      return _delegate.getBranchByCode(businessId, code);
    }
    final normalizedCode = normalizeBranchCode(code);
    final branches = await listBranches(businessId);
    for (final branch in branches) {
      if (branch.code == normalizedCode) return branch;
    }
    return null;
  }

  @override
  Future<BusinessBranch> ensureMainBranch(
    String businessId, {
    String? createdBy,
  }) {
    _requireManagementAccess(businessId);
    return _delegate.ensureMainBranch(businessId, createdBy: createdBy);
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
  }) {
    _requireManagementAccess(businessId);
    return _delegate.createBranch(
      businessId: businessId,
      name: name,
      code: code,
      address: address,
      city: city,
      country: country,
      phone: phone,
      email: email,
      managerUid: managerUid,
      createdBy: createdBy,
    );
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
  }) {
    _requireManagementAccess(businessId);
    return _delegate.updateBranch(
      businessId: businessId,
      branchId: branchId,
      name: name,
      code: code,
      address: address,
      city: city,
      country: country,
      phone: phone,
      email: email,
      managerUid: managerUid,
      status: status,
      updatedBy: updatedBy,
    );
  }

  @override
  Future<void> setBranchStatus({
    required String businessId,
    required String branchId,
    required BranchStatus status,
    required String updatedBy,
  }) {
    _requireManagementAccess(businessId);
    return _delegate.setBranchStatus(
      businessId: businessId,
      branchId: branchId,
      status: status,
      updatedBy: updatedBy,
    );
  }
}
