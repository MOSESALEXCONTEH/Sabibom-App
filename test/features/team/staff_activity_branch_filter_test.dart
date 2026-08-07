import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/team/domain/staff_activity.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  StaffActivity activity(String id, String? branchId) => StaffActivity(
    id: id,
    businessId: 'business-1',
    branchId: branchId,
    userId: 'user-1',
    userName: 'Staff',
    userRole: 'cashier',
    actionType: StaffActionType.saleCreated,
    description: 'Created a sale',
  );

  test('non-main branch excludes main and legacy branchless activity', () {
    final result = filterStaffActivityForBranch(
      activities: <StaffActivity>[
        activity('legacy', null),
        activity('main', 'main'),
        activity('east', 'east'),
      ],
      selectedBranchId: 'east',
      isMainBranch: false,
    );

    expect(result.map((item) => item.id), <String>['east']);
  });

  test('main branch keeps main and legacy branchless activity', () {
    final result = filterStaffActivityForBranch(
      activities: <StaffActivity>[
        activity('legacy', null),
        activity('main', 'main'),
        activity('east', 'east'),
      ],
      selectedBranchId: 'main',
      isMainBranch: true,
    );

    expect(result.map((item) => item.id), <String>['legacy', 'main']);
  });

  test('parses the operational API activity schema', () {
    final timestamp = Timestamp.fromDate(DateTime(2026, 8, 3));
    final result = StaffActivity.fromMap('activity-1', <String, dynamic>{
      'businessId': 'business-1',
      'branchId': 'east',
      'type': 'sale',
      'title': 'Sale completed',
      'subtitle': 'Receipt SB-001',
      'referenceId': 'sale-1',
      'createdBy': 'cashier-1',
      'createdByName': 'James',
      'timestamp': timestamp,
    });

    expect(result.actionType, StaffActionType.saleCreated);
    expect(result.userId, 'cashier-1');
    expect(result.userName, 'James');
    expect(result.description, 'Receipt SB-001');
    expect(result.entityId, 'sale-1');
    expect(result.branchId, 'east');
    expect(result.createdAt, timestamp.toDate());
  });
}
