import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/application/user_profile_provider.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../team/application/team_providers.dart';
import '../../team/domain/app_permission.dart';
import '../../team/domain/business_membership.dart';
import '../data/business_branch_repository.dart';
import '../data/authorized_business_branch_repository.dart';
import '../domain/branch_access_context.dart';
import '../domain/business_branch.dart';

final businessBranchRepositoryProvider = Provider<BusinessBranchRepository>((
  ref,
) {
  final membership = ref.watch(currentBusinessMembershipProvider).asData?.value;
  return AuthorizedBusinessBranchRepository(
    delegate: FirestoreBusinessBranchRepository(),
    membership: membership,
  );
});

final businessBranchesProvider =
    StreamProvider.family<List<BusinessBranch>, String>((ref, businessId) {
      return ref
          .watch(businessBranchRepositoryProvider)
          .watchBranches(businessId);
    });

class BranchSelection {
  const BranchSelection({
    required this.businessId,
    required this.branches,
    required this.mainBranch,
    required this.selectedBranch,
    required this.viewMode,
    required this.canUseAllBranches,
    this.canSwitchBranch = false,
  });

  final String businessId;
  final List<BusinessBranch> branches;
  final BusinessBranch mainBranch;
  final BusinessBranch selectedBranch;
  final BranchViewMode viewMode;
  final bool canUseAllBranches;
  final bool canSwitchBranch;

  bool get isAllBranchesMode => viewMode == BranchViewMode.allBranches;

  String? get branchId =>
      viewMode == BranchViewMode.singleBranch ? selectedBranch.branchId : null;

  bool get canCreateRecords => viewMode == BranchViewMode.singleBranch;

  List<BusinessBranch> get selectableBranches =>
      branches.where((branch) => branch.isSelectable).toList(growable: false);
}

final currentBranchProvider =
    AsyncNotifierProvider<CurrentBranchController, BranchSelection?>(
      CurrentBranchController.new,
    );

final currentBranchWriteEnabledProvider = Provider<bool>((ref) {
  final selection = ref.watch(currentBranchProvider).asData?.value;
  return selection?.canCreateRecords ?? false;
});

const noBranchAccessScope = '__no_branch_access__';

final currentBranchReadScopeProvider = Provider<String?>((ref) {
  final branchState = ref.watch(currentBranchProvider);
  final selection = branchState.asData?.value;
  if (selection == null) return noBranchAccessScope;
  return selection.branchId;
});

final currentWritableBranchIdProvider = Provider<String?>((ref) {
  final selection = ref.watch(currentBranchProvider).asData?.value;
  if (selection == null || !selection.canCreateRecords) {
    return null;
  }
  return selection.branchId;
});

const branchWriteBlockedMessage =
    'Switch to a single branch before creating or editing records.';

bool canCreateRecordsForSelection(BranchSelection? selection) {
  return selection?.canCreateRecords == true;
}

BusinessBranch resolveCurrentBranchSelection({
  required BusinessBranch main,
  required List<BusinessBranch> branches,
  required String? selectedId,
  required BusinessMembership? membership,
}) {
  final candidates = branches.isEmpty ? <BusinessBranch>[main] : branches;
  final allowed = membership == null
      ? candidates
      : candidates
            .where((branch) => membership.hasBranchAccess(branch.branchId))
            .toList(growable: false);
  final activeAllowed = allowed
      .where((branch) => branch.isSelectable)
      .toList(growable: false);
  final fallback = activeAllowed.firstWhere(
    (branch) => branch.isMainBranch,
    orElse: () => activeAllowed.isNotEmpty ? activeAllowed.first : main,
  );
  final byId = <String, BusinessBranch>{
    for (final branch in activeAllowed) branch.branchId: branch,
  };
  final byCode = <String, BusinessBranch>{
    for (final branch in activeAllowed) branch.code: branch,
  };
  final selected =
      byId[selectedId] ?? byCode[selectedId?.trim().toUpperCase() ?? ''];
  return selected ?? fallback;
}

BranchSelection resolveInitialBranchSelectionState({
  required String businessId,
  required BusinessBranch main,
  required List<BusinessBranch> branches,
  required BusinessMembership? membership,
  required String? savedBranchId,
  required BranchViewMode savedMode,
}) {
  final accessibleBranches = membership == null
      ? branches
      : branches
            .where((branch) => membership.hasBranchAccess(branch.branchId))
            .toList(growable: false);
  final selectedBranch = resolveCurrentBranchSelection(
    main: main,
    branches: accessibleBranches,
    selectedId: savedBranchId,
    membership: membership,
  );
  final canUseAllBranches =
      membership?.hasPermission(AppPermission.viewCombinedReports) == true ||
      membership?.isOwner == true;
  final viewMode = savedMode == BranchViewMode.allBranches && canUseAllBranches
      ? BranchViewMode.allBranches
      : BranchViewMode.singleBranch;

  return BranchSelection(
    businessId: businessId,
    branches: accessibleBranches.isEmpty
        ? <BusinessBranch>[main]
        : accessibleBranches,
    mainBranch: main,
    selectedBranch: selectedBranch,
    viewMode: viewMode,
    canUseAllBranches: canUseAllBranches,
    canSwitchBranch:
        activeAllowedBranchCount(accessibleBranches) > 1 &&
        (membership?.isOwner == true ||
            membership?.hasPermission(AppPermission.switchBranch) == true),
  );
}

int activeAllowedBranchCount(List<BusinessBranch> branches) {
  return branches.where((branch) => branch.isSelectable).length;
}

class CurrentBranchController extends AsyncNotifier<BranchSelection?> {
  static const _activeBusinessKey = 'current_branch:business';
  static const _prefsModePrefix = 'current_branch:mode:';
  static const _prefsBranchPrefix = 'current_branch:id:';

  BusinessBranchRepository get _repo =>
      ref.read(businessBranchRepositoryProvider);

  @override
  Future<BranchSelection?> build() async {
    final profile = ref.watch(currentUserProfileProvider).asData?.value;
    final activeBusiness = ref.watch(activeBusinessProvider).asData?.value;
    if (profile == null || activeBusiness is! ActiveBusinessData) {
      await _clearActiveBusinessPointer();
      return null;
    }

    final businessId = activeBusiness.business.businessId;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final membership = ref
        .watch(currentBusinessMembershipProvider)
        .asData
        ?.value;
    if (membership == null || !membership.status.canAccessBusiness) {
      return null;
    }

    await _saveActiveBusinessPointer(businessId);

    final branchesAsync = ref.watch(businessBranchesProvider(businessId));
    if (branchesAsync.hasError) {
      throw branchesAsync.error!;
    }
    var branches = branchesAsync.asData?.value;
    if (branches == null) return null;
    if (branches.isEmpty && membership.isOwner) {
      final createdMain = await _repo.ensureMainBranch(
        businessId,
        createdBy: uid,
      );
      branches = <BusinessBranch>[createdMain];
    }
    if (branches.isEmpty) return null;
    final resolvedBranches = branches;
    final saved = await _readSavedSelection(businessId);
    final access = resolveBranchAccessContext(
      businessId: businessId,
      membership: membership,
      branches: resolvedBranches,
      persistedBranchId: saved.branchId,
    );
    if (access.activeBranchId == null) return null;
    final main = resolvedBranches.firstWhere(
      (branch) => branch.isMainBranch,
      orElse: () => resolvedBranches.first,
    );
    final selection = resolveInitialBranchSelectionState(
      businessId: businessId,
      main: main,
      branches: resolvedBranches,
      membership: membership,
      savedBranchId: access.activeBranchId,
      savedMode: saved.mode,
    );

    await _saveSelection(
      businessId,
      mode: selection.viewMode,
      branchId: selection.branchId,
    );

    return selection;
  }

  Future<bool> selectBranch(String branchId) async {
    final selection = state.asData?.value;
    if (selection == null) return false;

    BusinessBranch? branch;
    for (final candidate in selection.branches) {
      if (candidate.branchId == branchId) {
        branch = candidate;
        break;
      }
    }
    if (branch == null || !branch.isSelectable) return false;

    final membership = ref
        .read(currentBusinessMembershipProvider)
        .asData
        ?.value;
    if (membership == null ||
        !membership.hasBranchAccess(branchId) ||
        (!membership.isOwner &&
            !membership.hasPermission(AppPermission.switchBranch))) {
      return false;
    }

    await _saveSelection(
      selection.businessId,
      mode: BranchViewMode.singleBranch,
      branchId: branchId,
    );

    state = AsyncValue.data(
      BranchSelection(
        businessId: selection.businessId,
        branches: selection.branches,
        mainBranch: selection.mainBranch,
        selectedBranch: branch,
        viewMode: BranchViewMode.singleBranch,
        canUseAllBranches: selection.canUseAllBranches,
        canSwitchBranch: selection.canSwitchBranch,
      ),
    );
    return true;
  }

  Future<void> selectAllBranches() async {
    final selection = state.asData?.value;
    if (selection == null || !selection.canUseAllBranches) return;

    await _saveSelection(
      selection.businessId,
      mode: BranchViewMode.allBranches,
      branchId: null,
    );

    state = AsyncValue.data(
      BranchSelection(
        businessId: selection.businessId,
        branches: selection.branches,
        mainBranch: selection.mainBranch,
        selectedBranch: selection.selectedBranch,
        viewMode: BranchViewMode.allBranches,
        canUseAllBranches: selection.canUseAllBranches,
        canSwitchBranch: selection.canSwitchBranch,
      ),
    );
  }

  Future<void> clearInMemorySelection() async {
    state = const AsyncValue.data(null);
    await _clearActiveBusinessPointer();
  }

  Future<_SavedSelection> _readSavedSelection(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final savedBusiness = prefs.getString(_activeBusinessKey)?.trim();
    if (savedBusiness != null &&
        savedBusiness.isNotEmpty &&
        savedBusiness != businessId) {
      return const _SavedSelection(mode: BranchViewMode.singleBranch);
    }

    final modeRaw = prefs
        .getString('$_prefsModePrefix$businessId')
        ?.trim()
        .toLowerCase();
    final mode = modeRaw == 'all'
        ? BranchViewMode.allBranches
        : BranchViewMode.singleBranch;

    final branchId = prefs.getString('$_prefsBranchPrefix$businessId')?.trim();
    return _SavedSelection(
      mode: mode,
      branchId: branchId == null || branchId.isEmpty ? null : branchId,
    );
  }

  Future<void> _saveSelection(
    String businessId, {
    required BranchViewMode mode,
    required String? branchId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeBusinessKey, businessId);
    await prefs.setString(
      '$_prefsModePrefix$businessId',
      mode == BranchViewMode.allBranches ? 'all' : 'single',
    );
    if (branchId == null || branchId.trim().isEmpty) {
      await prefs.remove('$_prefsBranchPrefix$businessId');
    } else {
      await prefs.setString('$_prefsBranchPrefix$businessId', branchId.trim());
    }
  }

  Future<void> _saveActiveBusinessPointer(String businessId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeBusinessKey, businessId);
  }

  Future<void> _clearActiveBusinessPointer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeBusinessKey);
  }
}

class _SavedSelection {
  const _SavedSelection({required this.mode, this.branchId});

  final BranchViewMode mode;
  final String? branchId;
}
