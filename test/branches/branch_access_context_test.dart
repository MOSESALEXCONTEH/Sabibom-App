import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/branches/domain/branch_access_context.dart';
import 'package:sabibom/features/branches/domain/business_branch.dart';
import 'package:sabibom/features/team/domain/business_membership.dart';

void main() {
  const east = BusinessBranch(
    branchId: 'east',
    businessId: 'biz',
    name: 'East',
    code: 'EAST',
    status: BranchStatus.active,
    isMainBranch: false,
  );
  const west = BusinessBranch(
    branchId: 'west',
    businessId: 'biz',
    name: 'West',
    code: 'WEST',
    status: BranchStatus.active,
    isMainBranch: false,
  );
  const inactive = BusinessBranch(
    branchId: 'closed',
    businessId: 'biz',
    name: 'Closed',
    code: 'CLOSED',
    status: BranchStatus.inactive,
    isMainBranch: false,
  );
  final main = BusinessBranch.main(businessId: 'biz');
  final branches = <BusinessBranch>[main, east, west, inactive];

  BusinessMembership member({
    String role = 'cashier',
    List<String> assigned = const ['east'],
    List<String> permissions = const ['view_branch'],
    String? defaultBranchId,
    String status = 'active',
    bool owner = false,
  }) {
    return BusinessMembership.fromMap('user', 'biz', {
      'roleId': role,
      'role': role,
      'status': status,
      'isOwner': owner,
      'assignedBranchIds': assigned,
      'permissions': permissions,
      'defaultBranchId': defaultBranchId,
    });
  }

  test('owner accesses and switches among every active branch', () {
    final context = resolveBranchAccessContext(
      businessId: 'biz',
      membership: member(role: 'owner', owner: true, assigned: const []),
      branches: branches,
    );
    expect(context.accessibleBranchIds, {'main', 'east', 'west'});
    expect(context.canSwitchBranch, isTrue);
    expect(context.canManageBranches, isTrue);
  });

  test('manager switches only among assigned branches', () {
    final context = resolveBranchAccessContext(
      businessId: 'biz',
      membership: member(
        role: 'manager',
        assigned: const ['east', 'west'],
        permissions: const [
          'view_branch',
          'switch_branch',
          'manage_branch_operations',
        ],
      ),
      branches: branches,
    );
    expect(context.accessibleBranchIds, {'east', 'west'});
    expect(context.canSwitchBranch, isTrue);
    expect(context.canManageBranches, isFalse);
  });

  test('single branch cashier does not switch', () {
    final context = resolveBranchAccessContext(
      businessId: 'biz',
      membership: member(),
      branches: branches,
    );
    expect(context.activeBranchId, 'east');
    expect(context.canSwitchBranch, isFalse);
  });

  test(
    'assigned staff keeps default branch access with legacy permissions',
    () {
      final context = resolveBranchAccessContext(
        businessId: 'biz',
        membership: member(role: 'staff', permissions: const ['create_sale']),
        branches: branches,
      );
      expect(context.accessibleBranchIds, {'east'});
      expect(context.activeBranchId, 'east');
    },
  );

  test('multiple assignments without switch permission cannot switch', () {
    final context = resolveBranchAccessContext(
      businessId: 'biz',
      membership: member(assigned: const ['east', 'west']),
      branches: branches,
    );
    expect(context.accessibleBranchIds, {'east', 'west'});
    expect(context.canSwitchBranch, isFalse);
  });

  test('explicit switch permission enables multiple assigned branches', () {
    final context = resolveBranchAccessContext(
      businessId: 'biz',
      membership: member(
        assigned: const ['east', 'west'],
        permissions: const ['view_branch', 'switch_branch'],
      ),
      branches: branches,
    );
    expect(context.canSwitchBranch, isTrue);
  });

  test('view all does not grant operational branch access', () {
    final context = resolveBranchAccessContext(
      businessId: 'biz',
      membership: member(
        assigned: const ['east'],
        permissions: const ['view_branch', 'view_all_branches'],
      ),
      branches: branches,
    );
    expect(context.canViewAllBranches, isTrue);
    expect(context.accessibleBranchIds, {'east'});
  });

  test('combined reports does not grant branch management', () {
    final context = resolveBranchAccessContext(
      businessId: 'biz',
      membership: member(
        permissions: const ['view_branch', 'view_combined_reports'],
      ),
      branches: branches,
    );
    expect(context.canViewCombinedReports, isTrue);
    expect(context.canManageBranches, isFalse);
  });

  test('invalid cache uses authorized default then first branch', () {
    final withDefault = resolveBranchAccessContext(
      businessId: 'biz',
      membership: member(
        assigned: const ['east', 'west'],
        defaultBranchId: 'west',
      ),
      branches: branches,
      persistedBranchId: 'main',
    );
    expect(withDefault.activeBranchId, 'west');

    final first = resolveBranchAccessContext(
      businessId: 'biz',
      membership: member(assigned: const ['east', 'west']),
      branches: branches,
      persistedBranchId: 'main',
    );
    expect(first.activeBranchId, 'east');
  });

  test('inactive, duplicate, and nonexistent assignments are removed', () {
    final context = resolveBranchAccessContext(
      businessId: 'biz',
      membership: member(assigned: const ['east', 'east', 'closed', 'missing']),
      branches: branches,
    );
    expect(context.accessibleBranchIds, {'east'});
  });

  test('disabled or unassigned member has no active branch', () {
    final disabled = resolveBranchAccessContext(
      businessId: 'biz',
      membership: member(status: 'disabled'),
      branches: branches,
    );
    final unassigned = resolveBranchAccessContext(
      businessId: 'biz',
      membership: member(assigned: const []),
      branches: branches,
    );
    expect(disabled.activeBranchId, isNull);
    expect(unassigned.activeBranchId, isNull);
  });

  test('branch from another business is never accessible', () {
    const foreign = BusinessBranch(
      branchId: 'foreign',
      businessId: 'other',
      name: 'Foreign',
      code: 'FOREIGN',
      status: BranchStatus.active,
      isMainBranch: false,
    );
    final context = resolveBranchAccessContext(
      businessId: 'biz',
      membership: member(assigned: const ['foreign']),
      branches: const [foreign],
    );
    expect(context.accessibleBranchIds, isEmpty);
  });
}
