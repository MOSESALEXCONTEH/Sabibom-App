import 'app_permission.dart';
import 'business_membership.dart';

/// Reusable permission checks. Prefer membership.hasPermission for hot paths.
abstract final class PermissionService {
  static bool hasPermission(
    BusinessMembership? membership,
    AppPermission permission,
  ) {
    if (membership == null) return false;
    return membership.hasPermission(permission);
  }

  static bool hasAnyPermission(
    BusinessMembership? membership,
    Iterable<AppPermission> permissions,
  ) {
    if (membership == null) return false;
    return membership.hasAnyPermission(permissions);
  }

  static bool hasAllPermissions(
    BusinessMembership? membership,
    Iterable<AppPermission> permissions,
  ) {
    if (membership == null) return false;
    return membership.hasAllPermissions(permissions);
  }

  static bool canManageStaff(BusinessMembership? membership) {
    return hasPermission(membership, AppPermission.manageStaff);
  }

  static bool canViewProfit(BusinessMembership? membership) {
    return hasPermission(membership, AppPermission.viewProfit);
  }

  static bool canApprove(BusinessMembership? membership) {
    return hasPermission(membership, AppPermission.approveSensitiveActions);
  }

  /// Managers cannot grant permissions they do not have (owners can grant all).
  static bool canGrantPermission(
    BusinessMembership granter,
    AppPermission permission,
  ) {
    if (granter.isOwner) return true;
    final def = PermissionRegistry.byCode(permission);
    if (def?.ownerOnly == true) return false;
    return granter.hasPermission(permission);
  }

  static Set<AppPermission> filterGrantable(
    BusinessMembership granter,
    Iterable<AppPermission> requested,
  ) {
    return requested.where((p) => canGrantPermission(granter, p)).toSet();
  }
}
