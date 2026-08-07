import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/team/data/team_repository.dart';
import 'package:sabibom/features/team/domain/business_membership.dart';

void main() {
  test(
    'branch assignment permission updates assigned and default branch',
    () async {
      final firestore = FakeFirebaseFirestore();
      final repository = TeamRepository(firestore: firestore);
      final business = firestore.collection('businesses').doc('biz1');
      for (final branch in const [('east', 'East'), ('west', 'West')]) {
        await business.collection('branches').doc(branch.$1).set({
          'branchId': branch.$1,
          'businessId': 'biz1',
          'name': branch.$2,
          'code': branch.$1.toUpperCase(),
          'status': 'active',
          'isMainBranch': false,
        });
      }
      await business.collection('members').doc('staff').set({
        'uid': 'staff',
        'businessId': 'biz1',
        'roleId': 'staff',
        'role': 'staff',
        'status': 'active',
        'assignedBranchIds': ['east'],
        'defaultBranchId': 'east',
      });
      final actor = BusinessMembership.fromMap('admin', 'biz1', {
        'roleId': 'admin',
        'status': 'active',
        'assignedBranchIds': ['east', 'west'],
        'permissions': ['view_branch', 'assign_staff_to_branches'],
      });

      await repository.updateMemberBranchAccess(
        businessId: 'biz1',
        targetUid: 'staff',
        assignedBranchIds: {'east', 'west'},
        allBranchesAccess: false,
        defaultBranchId: 'west',
        updatedBy: 'admin',
        actor: actor,
      );

      final updated = (await business.collection('members').doc('staff').get())
          .data()!;
      expect(updated['assignedBranchIds'], containsAll(['east', 'west']));
      expect(updated['defaultBranchId'], 'west');
      expect(updated['permissionOverrides'], contains('view_branch'));
      expect(
        (await business.collection('staff_activity').get()).docs,
        hasLength(1),
      );
    },
  );
}
