import 'package:flutter_test/flutter_test.dart';

import 'package:sabibom/features/team/domain/approval_models.dart';
import 'package:sabibom/features/team/domain/app_permission.dart';
import 'package:sabibom/features/team/domain/business_membership.dart';
import 'package:sabibom/features/notifications/data/notifications_repository.dart';

void main() {
  group('ApprovalPolicies', () {
    test('defaults do not force sale void approval', () {
      const policies = ApprovalPolicies();
      expect(policies.requireSaleVoidApproval, isFalse);
    });

    test('fromMap reads requireSaleVoidApproval', () {
      final policies = ApprovalPolicies.fromMap({
        'requireSaleVoidApproval': true,
      });
      expect(policies.requireSaleVoidApproval, isTrue);
    });
  });

  group('Void permission gate', () {
    test('cashier without void_sale cannot void', () {
      final cashier = BusinessMembership.fromMap('c1', 'b1', {
        'roleId': 'cashier',
        'status': 'active',
        'permissions': ['create_sale'],
      });
      expect(cashier.hasPermission(AppPermission.voidSale), isFalse);
    });

    test('manager with void_sale can void', () {
      final manager = BusinessMembership.fromMap('m1', 'b1', {
        'roleId': 'manager',
        'status': 'active',
        'permissions': ['void_sale', 'approve_sensitive_actions'],
      });
      expect(manager.hasPermission(AppPermission.voidSale), isTrue);
    });
  });

  group('Notifications', () {
    test('notification type parse', () {
      expect(
        AppNotificationType.fromStorage('approval_requested'),
        AppNotificationType.approvalRequested,
      );
      expect(
        AppNotificationType.fromStorage('invitation_accepted'),
        AppNotificationType.invitationAccepted,
      );
    });
  });
}
