import '../../team/domain/app_permission.dart';
import '../../team/domain/business_membership.dart';
import 'business_branch.dart';

class BranchAccessContext {
  const BranchAccessContext({
    required this.businessId,
    required this.userId,
    required this.role,
    required this.isOwner,
    required this.assignedBranchIds,
    required this.accessibleBranchIds,
    required this.canSwitchBranch,
    required this.canManageBranches,
    required this.canViewAllBranches,
    required this.canViewCombinedReports,
    required this.activeBranchId,
  });

  final String businessId;
  final String userId;
  final String role;
  final bool isOwner;
  final Set<String> assignedBranchIds;
  final Set<String> accessibleBranchIds;
  final bool canSwitchBranch;
  final bool canManageBranches;
  final bool canViewAllBranches;
  final bool canViewCombinedReports;
  final String? activeBranchId;
}

BranchAccessContext resolveBranchAccessContext({
  required String businessId,
  required BusinessMembership membership,
  required List<BusinessBranch> branches,
  String? persistedBranchId,
}) {
  final active = branches
      .where((branch) => branch.businessId == businessId && branch.isSelectable)
      .toList(growable: false);
  final accessible = membership.isOwner
      ? active
      : active
            .where((branch) => membership.hasBranchAccess(branch.branchId))
            .toList(growable: false);
  final ids = accessible.map((branch) => branch.branchId).toSet();
  final defaultId = membership.defaultBranchId?.trim();
  final recentId = persistedBranchId?.trim();
  final activeBranchId = defaultId != null && ids.contains(defaultId)
      ? defaultId
      : recentId != null && ids.contains(recentId)
      ? recentId
      : accessible.isEmpty
      ? null
      : accessible.first.branchId;
  final maySwitch =
      membership.isOwner ||
      membership.hasPermission(AppPermission.switchBranch);

  return BranchAccessContext(
    businessId: businessId,
    userId: membership.uid,
    role: membership.roleId,
    isOwner: membership.isOwner,
    assignedBranchIds: Set.unmodifiable(membership.assignedBranchIds),
    accessibleBranchIds: Set.unmodifiable(ids),
    canSwitchBranch: maySwitch && ids.length > 1,
    canManageBranches:
        membership.isOwner ||
        membership.hasPermission(AppPermission.manageBranches),
    canViewAllBranches:
        membership.isOwner ||
        membership.hasPermission(AppPermission.viewAllBranches),
    canViewCombinedReports:
        membership.isOwner ||
        membership.hasPermission(AppPermission.viewCombinedReports),
    activeBranchId: activeBranchId,
  );
}
