import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/user_profile_provider.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../data/team_repository.dart';
import '../domain/app_permission.dart';
import '../domain/approval_models.dart';
import '../domain/business_membership.dart';
import '../domain/permission_service.dart';
import '../domain/staff_activity.dart';
import '../domain/staff_invitation.dart';
import '../domain/system_roles.dart';

final teamRepositoryProvider = Provider<TeamRepository>((ref) {
  return TeamRepository();
});

/// Active business id from profile; empty when unset.
final teamBusinessIdProvider = Provider<String?>((ref) {
  final profile = ref.watch(currentUserProfileProvider).asData?.value;
  final id = profile?.activeBusinessId?.trim();
  if (id == null || id.isEmpty) return null;
  return id;
});

/// Current user's membership for the active business.
final currentBusinessMembershipProvider =
    StreamProvider<BusinessMembership?>((ref) {
  final businessId = ref.watch(teamBusinessIdProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (businessId == null || uid == null || uid.isEmpty) {
    return Stream.value(null);
  }

  final repo = ref.watch(teamRepositoryProvider);

  // Ensure default roles once per business (fire-and-forget).
  repo.ensureDefaultRoles(businessId, createdBy: uid);

  return repo.watchMembership(businessId: businessId, uid: uid);
});

final currentUserPermissionsProvider = Provider<Set<AppPermission>>((ref) {
  final membership = ref.watch(currentBusinessMembershipProvider).asData?.value;
  if (membership == null) return const {};
  return membership.effectivePermissions;
});

final hasPermissionProvider =
    Provider.family<bool, AppPermission>((ref, permission) {
  final membership = ref.watch(currentBusinessMembershipProvider).asData?.value;
  return PermissionService.hasPermission(membership, permission);
});

final canManageStaffProvider = Provider<bool>((ref) {
  return ref.watch(hasPermissionProvider(AppPermission.manageStaff));
});

final canViewProfitProvider = Provider<bool>((ref) {
  return ref.watch(hasPermissionProvider(AppPermission.viewProfit));
});

final canApproveSensitiveActionsProvider = Provider<bool>((ref) {
  return ref.watch(hasPermissionProvider(AppPermission.approveSensitiveActions));
});

final teamMembersProvider = StreamProvider<List<BusinessMembership>>((ref) {
  final businessId = ref.watch(teamBusinessIdProvider);
  if (businessId == null) return Stream.value(const []);
  return ref.watch(teamRepositoryProvider).watchMembers(businessId);
});

final teamRolesProvider = StreamProvider<List<RoleDefinition>>((ref) {
  final businessId = ref.watch(teamBusinessIdProvider);
  if (businessId == null) return Stream.value(const []);
  final repo = ref.watch(teamRepositoryProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  repo.ensureDefaultRoles(businessId, createdBy: uid);
  return repo.watchRoles(businessId);
});

final teamInvitationsProvider = StreamProvider<List<StaffInvitation>>((ref) {
  final businessId = ref.watch(teamBusinessIdProvider);
  if (businessId == null) return Stream.value(const []);
  return ref.watch(teamRepositoryProvider).watchInvitations(businessId);
});

final staffActivityProvider = StreamProvider<List<StaffActivity>>((ref) {
  final businessId = ref.watch(teamBusinessIdProvider);
  if (businessId == null) return Stream.value(const []);
  return ref.watch(teamRepositoryProvider).watchActivity(businessId);
});

final approvalPoliciesProvider = StreamProvider<ApprovalPolicies>((ref) {
  final businessId = ref.watch(teamBusinessIdProvider);
  if (businessId == null) {
    return Stream.value(const ApprovalPolicies());
  }
  return ref.watch(teamRepositoryProvider).watchApprovalPolicies(businessId);
});

final pendingApprovalsProvider = StreamProvider<List<ApprovalRequest>>((ref) {
  final businessId = ref.watch(teamBusinessIdProvider);
  if (businessId == null) return Stream.value(const []);
  return ref.watch(teamRepositoryProvider).watchApprovals(
        businessId,
        status: ApprovalStatus.pending,
      );
});

final myApprovalRequestsProvider = StreamProvider<List<ApprovalRequest>>((ref) {
  final businessId = ref.watch(teamBusinessIdProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (businessId == null || uid == null) return Stream.value(const []);
  return ref.watch(teamRepositoryProvider).watchApprovals(
        businessId,
        requestedBy: uid,
      );
});

final memberByIdProvider =
    StreamProvider.family<BusinessMembership?, String>((ref, uid) {
  final businessId = ref.watch(teamBusinessIdProvider);
  if (businessId == null || uid.isEmpty) return Stream.value(null);
  return ref
      .watch(teamRepositoryProvider)
      .watchMembership(businessId: businessId, uid: uid);
});

/// True when an active business exists and the user is an active member.
final hasActiveBusinessAccessProvider = Provider<bool>((ref) {
  final business = ref.watch(activeBusinessProvider).asData?.value;
  final membership = ref.watch(currentBusinessMembershipProvider).asData?.value;
  if (business is! ActiveBusinessData) return false;
  if (membership == null) {
    // Legacy: owner may only be on business.ownerId.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null && business.business.ownerId == uid;
  }
  return membership.status.canAccessBusiness;
});
