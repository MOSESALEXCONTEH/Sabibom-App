import 'package:flutter_test/flutter_test.dart';

import 'package:sabibom/features/team/domain/app_permission.dart';
import 'package:sabibom/features/team/domain/business_membership.dart';
import 'package:sabibom/features/team/domain/permission_service.dart';
import 'package:sabibom/features/team/domain/staff_activity.dart';
import 'package:sabibom/features/team/domain/staff_invitation.dart';
import 'package:sabibom/features/team/domain/system_roles.dart';
import 'package:sabibom/features/team/data/team_repository.dart';

void main() {
  group('PermissionRegistry', () {
    test('contains stable codes and groups', () {
      expect(PermissionRegistry.all, isNotEmpty);
      expect(
        PermissionRegistry.byCode(AppPermission.voidSale)?.title,
        'Void sales',
      );
      expect(PermissionRegistry.byGroup(PermissionGroup.sales), isNotEmpty);
    });

    test('AppPermission.tryParse works', () {
      expect(AppPermission.tryParse('view_profit'), AppPermission.viewProfit);
      expect(AppPermission.tryParse('missing'), isNull);
    });
  });

  group('SystemRoles', () {
    test('default roles created once shape', () {
      final roles = SystemRoles.buildDefaults('biz1');
      expect(roles.map((r) => r.id), containsAll(SystemRoleIds.all));
      expect(roles.every((r) => r.isSystemRole), isTrue);
    });

    test('owner receives full permissions', () {
      expect(
        SystemRoles.defaultPermissionsFor(SystemRoleIds.owner).length,
        AppPermission.values.length,
      );
    });

    test('cashier restrictions', () {
      final perms = SystemRoles.defaultPermissionsFor(SystemRoleIds.cashier);
      expect(perms.contains(AppPermission.createSale), isTrue);
      expect(perms.contains(AppPermission.viewProfit), isFalse);
      expect(perms.contains(AppPermission.manageStaff), isFalse);
    });

    test('stock keeper restrictions', () {
      final perms = SystemRoles.defaultPermissionsFor(
        SystemRoleIds.stockKeeper,
      );
      expect(perms.contains(AppPermission.adjustStock), isTrue);
      expect(perms.contains(AppPermission.viewProfit), isFalse);
      expect(perms.contains(AppPermission.manageStaff), isFalse);
    });

    test('accountant restrictions', () {
      final perms = SystemRoles.defaultPermissionsFor(SystemRoleIds.accountant);
      expect(perms.contains(AppPermission.viewProfit), isTrue);
      expect(perms.contains(AppPermission.createExpense), isTrue);
      expect(perms.contains(AppPermission.manageStaff), isFalse);
    });
  });

  group('BusinessMembership', () {
    test('owner membership loads with full access', () {
      final m = BusinessMembership.fromMap('u1', 'b1', {
        'role': 'owner',
        'status': 'active',
        'isOwner': true,
      });
      expect(m.isOwner, isTrue);
      expect(m.hasPermission(AppPermission.manageStaff), isTrue);
      expect(m.hasPermission(AppPermission.viewProfit), isTrue);
    });

    test('active cashier membership loads', () {
      final m = BusinessMembership.fromMap('u2', 'b1', {
        'roleId': 'cashier',
        'roleName': 'Cashier',
        'status': 'active',
        'permissions': ['create_sale', 'view_own_sales'],
      });
      expect(m.status, MemberStatus.active);
      expect(m.hasPermission(AppPermission.createSale), isTrue);
      expect(m.hasPermission(AppPermission.viewProfit), isFalse);
    });

    test('disabled member rejected', () {
      final m = BusinessMembership.fromMap('u3', 'b1', {
        'roleId': 'cashier',
        'status': 'disabled',
        'permissions': ['create_sale'],
      });
      expect(m.hasPermission(AppPermission.createSale), isFalse);
    });

    test('removed member rejected', () {
      final m = BusinessMembership.fromMap('u4', 'b1', {
        'roleId': 'manager',
        'status': 'removed',
        'permissions': ['manage_staff'],
      });
      expect(m.hasPermission(AppPermission.manageStaff), isFalse);
    });

    test('snapshot id used correctly', () {
      final m = BusinessMembership.fromMap('docUid', 'biz', {
        'role': 'cashier',
        'status': 'active',
      });
      expect(m.uid, 'docUid');
      expect(m.businessId, 'biz');
    });

    test('permission denials override grants', () {
      final m = BusinessMembership.fromMap('u5', 'b1', {
        'roleId': 'manager',
        'status': 'active',
        'permissions': ['view_all_branch_reports'],
        'permissionDenials': ['view_all_branch_reports'],
      });
      expect(m.hasPermission(AppPermission.viewCombinedReports), isFalse);
      expect(m.canUseAllBranchesReports, isFalse);
    });

    test('all branch permissions are available in registry', () {
      expect(PermissionRegistry.byCode(AppPermission.viewBranch), isNotNull);
      expect(
        PermissionRegistry.byCode(AppPermission.manageBranches),
        isNotNull,
      );
      expect(PermissionRegistry.byCode(AppPermission.switchBranch), isNotNull);
      expect(
        PermissionRegistry.byCode(AppPermission.viewCombinedReports),
        isNotNull,
      );
      expect(
        PermissionRegistry.byCode(AppPermission.assignStaffToBranches),
        isNotNull,
      );
    });
  });

  group('PermissionService', () {
    test('manager cannot grant unavailable permission', () {
      final manager = BusinessMembership.fromMap('m1', 'b1', {
        'roleId': 'manager',
        'status': 'active',
        'permissions': ['manage_staff', 'create_sale'],
      });
      expect(
        PermissionService.canGrantPermission(manager, AppPermission.createSale),
        isTrue,
      );
      expect(
        PermissionService.canGrantPermission(manager, AppPermission.viewProfit),
        isFalse,
      );
    });

    test('owner can grant any permission', () {
      final owner = BusinessMembership.fromMap('o1', 'b1', {
        'roleId': 'owner',
        'isOwner': true,
        'status': 'active',
      });
      expect(
        PermissionService.canGrantPermission(owner, AppPermission.viewProfit),
        isTrue,
      );
    });
  });

  group('Invitations', () {
    test('invite code is strong and non-empty', () {
      final a = TeamRepository.generateInviteCode();
      final b = TeamRepository.generateInviteCode();
      expect(a.length, 8);
      expect(b.length, 8);
      // Extremely unlikely to collide; still assert format.
      expect(RegExp(r'^[A-Z0-9]+$').hasMatch(a), isTrue);
    });

    test('invitation expiry detection', () {
      final expired = StaffInvitation(
        id: 'i1',
        businessId: 'b1',
        businessName: 'Shop',
        roleId: 'cashier',
        roleName: 'Cashier',
        permissionsSnapshot: const {},
        status: InvitationStatus.pending,
        invitedBy: 'o1',
        inviteCode: 'ABCD1234',
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(expired.isExpired, isTrue);
      expect(expired.isAcceptable, isFalse);
    });

    test('pending invitation is acceptable', () {
      final live = StaffInvitation(
        id: 'i2',
        businessId: 'b1',
        businessName: 'Shop',
        roleId: 'cashier',
        roleName: 'Cashier',
        permissionsSnapshot: {AppPermission.createSale},
        status: InvitationStatus.pending,
        invitedBy: 'o1',
        inviteCode: 'ABCD1234',
        expiresAt: DateTime.now().add(const Duration(days: 2)),
      );
      expect(live.isAcceptable, isTrue);
    });
  });

  group('Staff activity metadata', () {
    test('strips secrets from metadata', () {
      final activity = StaffActivity(
        id: 'a1',
        businessId: 'b1',
        userId: 'u1',
        userName: 'Ada',
        userRole: 'manager',
        actionType: StaffActionType.roleChanged,
        description: 'Changed role',
        metadata: {
          'role': 'cashier',
          'token': 'secret-value',
          'api_key': 'x',
          'password': 'nope',
        },
      );
      final map = activity.toCreateMap();
      final meta = map['metadata'] as Map<String, Object?>;
      expect(meta.containsKey('token'), isFalse);
      expect(meta.containsKey('api_key'), isFalse);
      expect(meta.containsKey('password'), isFalse);
      expect(meta['role'], 'cashier');
    });
  });
}
