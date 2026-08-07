import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sabibom/features/auth/application/user_profile_provider.dart';
import 'package:sabibom/features/branches/application/current_branch_providers.dart';
import 'package:sabibom/features/branches/data/authorized_business_branch_repository.dart';
import 'package:sabibom/features/branches/data/business_branch_repository.dart';
import 'package:sabibom/features/branches/domain/business_branch.dart';
import 'package:sabibom/features/dashboard/application/dashboard_providers.dart';
import 'package:sabibom/features/team/application/team_providers.dart';
import 'package:sabibom/features/team/domain/business_membership.dart';

void main() {
  group('Phase 1 multi-branch behavior', () {
    test('1. Business without branches gets one Main Branch', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreBusinessBranchRepository(firestore: firestore);

      final branch = await repo.ensureMainBranch('biz1', createdBy: 'owner1');

      expect(branch.branchId, 'main');
      expect(branch.isMainBranch, isTrue);
      expect(branch.code, 'MAIN');
      expect(branch.status, BranchStatus.active);
    });

    test('2. Main-branch creation is idempotent', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreBusinessBranchRepository(firestore: firestore);

      await repo.ensureMainBranch('biz1', createdBy: 'owner1');
      await repo.ensureMainBranch('biz1', createdBy: 'owner1');
      final branches = await repo.listBranches('biz1');

      expect(branches.where((b) => b.isMainBranch).length, 1);
      expect(branches.where((b) => b.branchId == 'main').length, 1);
    });

    test('3. Second main branch is rejected', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreBusinessBranchRepository(firestore: firestore);
      await repo.ensureMainBranch('biz1', createdBy: 'owner1');

      await firestore
          .collection('businesses')
          .doc('biz1')
          .collection('branches')
          .doc('rogue')
          .set({
            'branchId': 'rogue',
            'businessId': 'biz1',
            'name': 'Rogue Main',
            'code': 'RG',
            'isMainBranch': true,
            'status': 'active',
          });

      await expectLater(
        () => repo.listBranches('biz1'),
        throwsA(isA<BranchException>()),
      );
    });

    test('4. Duplicate branch code is rejected', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreBusinessBranchRepository(firestore: firestore);
      await _seedActiveMember(firestore, 'biz1', 'owner1');
      await repo.ensureMainBranch('biz1', createdBy: 'owner1');

      await repo.createBranch(
        businessId: 'biz1',
        name: 'East',
        code: 'east',
        createdBy: 'owner1',
      );

      await expectLater(
        () => repo.createBranch(
          businessId: 'biz1',
          name: 'East 2',
          code: 'EAST',
          createdBy: 'owner1',
        ),
        throwsA(isA<BranchException>()),
      );
    });

    test('5. Owner sees all branches', () {
      final owner = BusinessMembership.fromMap('u1', 'biz1', {
        'roleId': 'owner',
        'status': 'active',
        'isOwner': true,
      });
      expect(owner.hasBranchAccess('main'), isTrue);
      expect(owner.hasBranchAccess('east'), isTrue);
      expect(owner.canUseAllBranchesReports, isTrue);
    });

    test('6. Branch manager sees assigned branches', () {
      final manager = BusinessMembership.fromMap('u2', 'biz1', {
        'roleId': 'manager',
        'status': 'active',
        'assignedBranchIds': ['east'],
        'defaultBranchId': 'east',
        'permissions': ['view_branches', 'switch_branches'],
      });
      expect(manager.hasBranchAccess('east'), isTrue);
      expect(manager.hasBranchAccess('main'), isFalse);
    });

    test('7. Staff cannot see unassigned branches', () {
      final staff = BusinessMembership.fromMap('u3', 'biz1', {
        'roleId': 'cashier',
        'status': 'active',
        'assignedBranchIds': ['main'],
      });
      expect(staff.hasBranchAccess('main'), isTrue);
      expect(staff.hasBranchAccess('west'), isFalse);
    });

    test('8. Saved current branch restores', () {
      final main = BusinessBranch.main(businessId: 'biz1');
      final east = const BusinessBranch(
        branchId: 'east',
        businessId: 'biz1',
        name: 'East',
        code: 'EAST',
        status: BranchStatus.active,
        isMainBranch: false,
      );
      final membership = BusinessMembership.fromMap('u2', 'biz1', {
        'roleId': 'manager',
        'status': 'active',
        'assignedBranchIds': ['east'],
        'permissions': ['view_branches', 'switch_branches'],
      });

      final resolved = resolveInitialBranchSelectionState(
        businessId: 'biz1',
        main: main,
        branches: [main, east],
        membership: membership,
        savedBranchId: 'east',
        savedMode: BranchViewMode.singleBranch,
      );

      expect(resolved.selectedBranch.branchId, 'east');
      expect(resolved.viewMode, BranchViewMode.singleBranch);
    });

    test('9. Invalid saved branch falls back to an assigned branch', () {
      final main = BusinessBranch.main(businessId: 'biz1');
      final east = const BusinessBranch(
        branchId: 'east',
        businessId: 'biz1',
        name: 'East',
        code: 'EAST',
        status: BranchStatus.active,
        isMainBranch: false,
      );
      final membership = BusinessMembership.fromMap('u2', 'biz1', {
        'roleId': 'manager',
        'status': 'active',
        'assignedBranchIds': ['east'],
      });

      final resolved = resolveInitialBranchSelectionState(
        businessId: 'biz1',
        main: main,
        branches: [main, east],
        membership: membership,
        savedBranchId: 'missing',
        savedMode: BranchViewMode.singleBranch,
      );

      expect(resolved.selectedBranch.branchId, 'east');
    });

    test('10. Inactive saved branch falls back safely', () {
      final main = BusinessBranch.main(businessId: 'biz1');
      final inactive = const BusinessBranch(
        branchId: 'west',
        businessId: 'biz1',
        name: 'West',
        code: 'WEST',
        status: BranchStatus.inactive,
        isMainBranch: false,
      );

      final resolved = resolveInitialBranchSelectionState(
        businessId: 'biz1',
        main: main,
        branches: [main, inactive],
        membership: null,
        savedBranchId: 'west',
        savedMode: BranchViewMode.singleBranch,
      );

      expect(resolved.selectedBranch.branchId, 'main');
    });

    test('11. Branch switching updates resolved app state', () {
      final main = BusinessBranch.main(businessId: 'biz1');
      final east = const BusinessBranch(
        branchId: 'east',
        businessId: 'biz1',
        name: 'East',
        code: 'EAST',
        status: BranchStatus.active,
        isMainBranch: false,
      );
      final membership = BusinessMembership.fromMap('owner', 'biz1', {
        'roleId': 'owner',
        'status': 'active',
        'isOwner': true,
      });

      final initial = resolveInitialBranchSelectionState(
        businessId: 'biz1',
        main: main,
        branches: [main, east],
        membership: membership,
        savedBranchId: 'main',
        savedMode: BranchViewMode.singleBranch,
      );
      final switched = resolveInitialBranchSelectionState(
        businessId: 'biz1',
        main: main,
        branches: [main, east],
        membership: membership,
        savedBranchId: 'east',
        savedMode: BranchViewMode.singleBranch,
      );

      expect(initial.branchId, 'main');
      expect(switched.selectedBranch.branchId, 'east');
      expect(switched.branchId, 'east');
    });

    test('12. All Branches requires permission', () {
      final main = BusinessBranch.main(businessId: 'biz1');
      final staff = BusinessMembership.fromMap('u3', 'biz1', {
        'roleId': 'cashier',
        'status': 'active',
        'assignedBranchIds': ['main'],
        'permissions': ['view_branches'],
      });
      final resolved = resolveInitialBranchSelectionState(
        businessId: 'biz1',
        main: main,
        branches: [main],
        membership: staff,
        savedBranchId: null,
        savedMode: BranchViewMode.allBranches,
      );

      expect(resolved.canUseAllBranches, isFalse);
      expect(resolved.viewMode, BranchViewMode.singleBranch);
    });

    test('13. All Branches is read-only for creation', () {
      final selection = BranchSelection(
        businessId: 'biz1',
        branches: [BusinessBranch.main(businessId: 'biz1')],
        mainBranch: BusinessBranch.main(businessId: 'biz1'),
        selectedBranch: BusinessBranch.main(businessId: 'biz1'),
        viewMode: BranchViewMode.allBranches,
        canUseAllBranches: true,
      );
      expect(canCreateRecordsForSelection(selection), isFalse);
    });

    test('14. Last active branch cannot be deactivated', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreBusinessBranchRepository(firestore: firestore);
      await repo.ensureMainBranch('biz1', createdBy: 'owner1');

      await expectLater(
        () => repo.setBranchStatus(
          businessId: 'biz1',
          branchId: 'main',
          status: BranchStatus.inactive,
          updatedBy: 'owner1',
        ),
        throwsA(isA<BranchException>()),
      );
    });

    test('15. Main branch cannot be deleted or deactivated', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreBusinessBranchRepository(firestore: firestore);
      await repo.ensureMainBranch('biz1', createdBy: 'owner1');

      await expectLater(
        () => repo.updateBranch(
          businessId: 'biz1',
          branchId: 'main',
          name: 'Main Branch',
          code: 'MAIN',
          status: BranchStatus.inactive,
          updatedBy: 'owner1',
        ),
        throwsA(isA<BranchException>()),
      );
    });

    test('16. Branch code normalization works', () {
      expect(normalizeBranchCode(' east_1 '), 'EAST_1');
      expect(isValidBranchCode('A1'), isTrue);
      expect(isValidBranchCode('ABCDEFGHIJKLM'), isFalse);
      expect(isValidBranchCode('A'), isFalse);
      expect(isValidBranchCode('AB!'), isFalse);
    });

    test('17. Branch access is checked outside UI', () {
      final main = BusinessBranch.main(businessId: 'biz1');
      expect(
        matchesBranchScopeWithMode(
          <String, dynamic>{'branchId': 'west'},
          viewMode: BranchViewMode.singleBranch,
          branchId: 'east',
          mainBranchId: main.branchId,
        ),
        isFalse,
      );
    });

    test('18. Existing single-branch businesses still work', () {
      final main = BusinessBranch.main(businessId: 'biz1');
      final selection = resolveInitialBranchSelectionState(
        businessId: 'biz1',
        main: main,
        branches: [main],
        membership: null,
        savedBranchId: null,
        savedMode: BranchViewMode.singleBranch,
      );
      expect(selection.selectedBranch.branchId, 'main');
      expect(selection.branchId, 'main');
    });

    test('19. Signed-out state clears branch context', () async {
      SharedPreferences.setMockInitialValues({
        'current_branch:business': 'biz1',
      });
      final repo = _MemoryBranchRepo(
        branchesByBusiness: {
          'biz1': [BusinessBranch.main(businessId: 'biz1')],
        },
      );
      final container = ProviderContainer(
        overrides: [
          businessBranchRepositoryProvider.overrideWithValue(repo),
          currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
          activeBusinessProvider.overrideWith(
            (ref) => Stream.value(const ActiveBusinessNone()),
          ),
          currentBusinessMembershipProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final selection = await container.read(currentBranchProvider.future);
      expect(selection, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('current_branch:business'), isNull);
    });

    test('20. Switching businesses rejects previous branch context', () {
      final main = BusinessBranch.main(businessId: 'biz2');
      final west = const BusinessBranch(
        branchId: 'west',
        businessId: 'biz2',
        name: 'West',
        code: 'WEST',
        status: BranchStatus.active,
        isMainBranch: false,
      );
      final membership = BusinessMembership.fromMap('owner', 'biz2', {
        'roleId': 'owner',
        'status': 'active',
        'isOwner': true,
      });

      final selection = resolveInitialBranchSelectionState(
        businessId: 'biz2',
        main: main,
        branches: [main, west],
        membership: membership,
        savedBranchId: 'east',
        savedMode: BranchViewMode.singleBranch,
      );
      expect(selection.selectedBranch.branchId, 'main');
      expect(selection.businessId, 'biz2');
    });

    test(
      '21. Assigned staff repository reads only assigned branch docs',
      () async {
        final main = BusinessBranch.main(businessId: 'biz1');
        final east = const BusinessBranch(
          branchId: 'east',
          businessId: 'biz1',
          name: 'East',
          code: 'EAST',
          status: BranchStatus.active,
          isMainBranch: false,
        );
        final member = BusinessMembership.fromMap('staff', 'biz1', {
          'roleId': 'staff',
          'status': 'active',
          'assignedBranchIds': ['east'],
          'permissions': ['view_branch'],
        });
        final repository = AuthorizedBusinessBranchRepository(
          delegate: _MemoryBranchRepo(
            branchesByBusiness: {
              'biz1': [main, east],
            },
          ),
          membership: member,
        );

        expect(
          (await repository.listBranches(
            'biz1',
          )).map((branch) => branch.branchId),
          ['east'],
        );
        expect(
          (await repository.watchBranches('biz1').first).map(
            (branch) => branch.branchId,
          ),
          ['east'],
        );
      },
    );
  });

  group('Compatibility scope helper', () {
    test('Main branch includes branchless legacy records', () {
      expect(
        matchesBranchScopeWithMode(
          const <String, dynamic>{},
          viewMode: BranchViewMode.singleBranch,
          branchId: 'main',
          mainBranchId: 'main',
        ),
        isTrue,
      );
    });

    test('Other branch excludes branchless legacy records', () {
      expect(
        matchesBranchScopeWithMode(
          const <String, dynamic>{},
          viewMode: BranchViewMode.singleBranch,
          branchId: 'east',
          mainBranchId: 'main',
        ),
        isFalse,
      );
    });

    test('All branches mode includes all records', () {
      expect(
        matchesBranchScopeWithMode(
          const <String, dynamic>{'branchId': 'east'},
          viewMode: BranchViewMode.allBranches,
          branchId: null,
          mainBranchId: 'main',
        ),
        isTrue,
      );
    });

    test('No-branch scope never behaves like All Branches', () {
      expect(
        matchesBranchScope(const <String, dynamic>{
          'branchId': 'main',
        }, noBranchAccessScope),
        isFalse,
      );
      expect(
        matchesBranchScope(const <String, dynamic>{
          'branchId': 'east',
        }, noBranchAccessScope),
        isFalse,
      );
      expect(
        matchesBranchScope(const <String, dynamic>{}, noBranchAccessScope),
        isFalse,
      );
    });
  });
}

Future<void> _seedActiveMember(
  FakeFirebaseFirestore firestore,
  String businessId,
  String uid,
) {
  return firestore
      .collection('businesses')
      .doc(businessId)
      .collection('members')
      .doc(uid)
      .set({'status': 'active'});
}

class _MemoryBranchRepo implements BusinessBranchRepository {
  _MemoryBranchRepo({
    required Map<String, List<BusinessBranch>> branchesByBusiness,
  }) : _store = {
         for (final entry in branchesByBusiness.entries)
           entry.key: List<BusinessBranch>.from(entry.value),
       };

  final Map<String, List<BusinessBranch>> _store;

  @override
  Future<BusinessBranch> ensureMainBranch(
    String businessId, {
    String? createdBy,
  }) async {
    final list = _store.putIfAbsent(businessId, () => <BusinessBranch>[]);
    final existing = list
        .where((b) => b.branchId == 'main')
        .toList(growable: false);
    if (existing.isNotEmpty) {
      return existing.first;
    }
    final main = BusinessBranch.main(
      businessId: businessId,
      createdBy: createdBy,
    );
    list.add(main);
    return main;
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
    throw UnimplementedError();
  }

  @override
  Future<BusinessBranch?> getBranch(String businessId, String branchId) async {
    final list = _store[businessId] ?? const <BusinessBranch>[];
    for (final branch in list) {
      if (branch.branchId == branchId) return branch;
    }
    return null;
  }

  @override
  Future<BusinessBranch?> getBranchByCode(
    String businessId,
    String code,
  ) async {
    final list = _store[businessId] ?? const <BusinessBranch>[];
    final normalized = normalizeBranchCode(code);
    for (final branch in list) {
      if (branch.code == normalized) return branch;
    }
    return null;
  }

  @override
  Future<List<BusinessBranch>> listBranches(String businessId) async {
    return List<BusinessBranch>.from(
      _store[businessId] ?? const <BusinessBranch>[],
    );
  }

  @override
  Future<void> setBranchStatus({
    required String businessId,
    required String branchId,
    required BranchStatus status,
    required String updatedBy,
  }) async {
    final list = _store[businessId] ?? const <BusinessBranch>[];
    for (var index = 0; index < list.length; index++) {
      if (list[index].branchId == branchId) {
        list[index] = list[index].copyWith(status: status);
        return;
      }
    }
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
    throw UnimplementedError();
  }

  @override
  Stream<BusinessBranch?> watchBranch(String businessId, String branchId) {
    return Stream.fromFuture(getBranch(businessId, branchId));
  }

  @override
  Stream<List<BusinessBranch>> watchBranches(String businessId) {
    return Stream.value(_store[businessId] ?? const <BusinessBranch>[]);
  }
}
