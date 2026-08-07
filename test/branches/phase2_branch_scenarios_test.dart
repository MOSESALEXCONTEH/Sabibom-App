import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/branches/application/current_branch_providers.dart';
import 'package:sabibom/features/branches/data/business_branch_repository.dart';
import 'package:sabibom/features/branches/domain/business_branch.dart';
import 'package:sabibom/features/team/domain/business_membership.dart';

void main() {
  group('Phase 2 branch scenarios', () {
    test('manager assignment requires active member in same business', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreBusinessBranchRepository(firestore: firestore);
      await repo.ensureMainBranch('biz1', createdBy: 'owner1');
      await _seedMember(
        firestore,
        businessId: 'biz1',
        uid: 'manager1',
        status: 'active',
      );

      final branch = await repo.createBranch(
        businessId: 'biz1',
        name: 'East',
        code: 'EAST',
        managerUid: 'manager1',
        createdBy: 'owner1',
      );

      expect(branch.managerUid, 'manager1');
    });

    test('manager assignment rejects non-member and inactive member', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreBusinessBranchRepository(firestore: firestore);
      await repo.ensureMainBranch('biz1', createdBy: 'owner1');

      await expectLater(
        () => repo.createBranch(
          businessId: 'biz1',
          name: 'West',
          code: 'WEST',
          managerUid: 'missing-user',
          createdBy: 'owner1',
        ),
        throwsA(isA<BranchException>()),
      );

      await _seedMember(
        firestore,
        businessId: 'biz1',
        uid: 'inactive-manager',
        status: 'disabled',
      );
      await expectLater(
        () => repo.createBranch(
          businessId: 'biz1',
          name: 'North',
          code: 'NORTH',
          managerUid: 'inactive-manager',
          createdBy: 'owner1',
        ),
        throwsA(isA<BranchException>()),
      );
    });

    test('role permutations enforce all-branch mode permissions', () {
      final main = BusinessBranch.main(businessId: 'biz1');
      final east = const BusinessBranch(
        branchId: 'east',
        businessId: 'biz1',
        name: 'East',
        code: 'EAST',
        status: BranchStatus.active,
        isMainBranch: false,
      );

      final owner = BusinessMembership.fromMap('owner1', 'biz1', {
        'roleId': 'owner',
        'role': 'owner',
        'isOwner': true,
        'status': 'active',
      });
      final managerWithPermission = BusinessMembership.fromMap('manager1', 'biz1', {
        'roleId': 'manager',
        'status': 'active',
        'assignedBranchIds': ['main', 'east'],
        'permissions': ['view_all_branch_reports'],
      });
      final cashier = BusinessMembership.fromMap('cashier1', 'biz1', {
        'roleId': 'cashier',
        'status': 'active',
        'assignedBranchIds': ['main'],
      });

      final ownerSelection = resolveInitialBranchSelectionState(
        businessId: 'biz1',
        main: main,
        branches: [main, east],
        membership: owner,
        savedBranchId: null,
        savedMode: BranchViewMode.allBranches,
      );
      final managerSelection = resolveInitialBranchSelectionState(
        businessId: 'biz1',
        main: main,
        branches: [main, east],
        membership: managerWithPermission,
        savedBranchId: 'east',
        savedMode: BranchViewMode.allBranches,
      );
      final cashierSelection = resolveInitialBranchSelectionState(
        businessId: 'biz1',
        main: main,
        branches: [main, east],
        membership: cashier,
        savedBranchId: 'main',
        savedMode: BranchViewMode.allBranches,
      );

      expect(ownerSelection.viewMode, BranchViewMode.allBranches);
      expect(managerSelection.viewMode, BranchViewMode.allBranches);
      expect(cashierSelection.viewMode, BranchViewMode.singleBranch);
      expect(cashierSelection.canCreateRecords, isTrue);
    });

    test('cross-business switch rejects stale saved branch context', () {
      final main = BusinessBranch.main(businessId: 'biz2');
      final west = const BusinessBranch(
        branchId: 'west',
        businessId: 'biz2',
        name: 'West',
        code: 'WEST',
        status: BranchStatus.active,
        isMainBranch: false,
      );
      final ownerMembership = BusinessMembership.fromMap('owner2', 'biz2', {
        'roleId': 'owner',
        'role': 'owner',
        'isOwner': true,
        'status': 'active',
      });

      final selection = resolveInitialBranchSelectionState(
        businessId: 'biz2',
        main: main,
        branches: [main, west],
        membership: ownerMembership,
        savedBranchId: 'east',
        savedMode: BranchViewMode.allBranches,
      );

      expect(selection.businessId, 'biz2');
      expect(selection.selectedBranch.branchId, 'main');
      expect(selection.viewMode, BranchViewMode.allBranches);
    });

    test('all-branches mode clears writable branch intent', () {
      final main = BusinessBranch.main(businessId: 'biz1');
      final selection = BranchSelection(
        businessId: 'biz1',
        branches: const <BusinessBranch>[],
        mainBranch: main,
        selectedBranch: main,
        viewMode: BranchViewMode.allBranches,
        canUseAllBranches: true,
      );

      expect(selection.branchId, isNull);
      expect(selection.canCreateRecords, isFalse);
    });

    test('single-branch mode retains writable branch intent', () {
      final main = BusinessBranch.main(businessId: 'biz1');
      final east = const BusinessBranch(
        branchId: 'east',
        businessId: 'biz1',
        name: 'East',
        code: 'EAST',
        status: BranchStatus.active,
        isMainBranch: false,
      );
      final selection = BranchSelection(
        businessId: 'biz1',
        branches: <BusinessBranch>[main, east],
        mainBranch: main,
        selectedBranch: east,
        viewMode: BranchViewMode.singleBranch,
        canUseAllBranches: true,
      );

      expect(selection.branchId, 'east');
      expect(selection.canCreateRecords, isTrue);
    });
  });
}

Future<void> _seedMember(
  FakeFirebaseFirestore firestore, {
  required String businessId,
  required String uid,
  required String status,
}) {
  return firestore
      .collection('businesses')
      .doc(businessId)
      .collection('members')
      .doc(uid)
      .set({'status': status, 'role': 'manager'});
}
