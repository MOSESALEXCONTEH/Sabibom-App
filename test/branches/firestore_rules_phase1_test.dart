import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 1 Firestore rules coverage', () {
    late String rules;

    setUpAll(() {
      rules = File('firestore.rules').readAsStringSync();
    });

    test('cross-business branch access blocked', () {
      expect(
        rules.contains('request.resource.data.businessId == businessId'),
        isTrue,
      );
      expect(rules.contains('resource.data.businessId == businessId'), isTrue);
    });

    test('unauthorized branch writes blocked', () {
      expect(rules.contains("canManageBranches(businessId)"), isTrue);
      expect(rules.contains('match /branches/{branchId}'), isTrue);
    });

    test('staff self-assignment blocked', () {
      expect(rules.contains('memberId != request.auth.uid'), isTrue);
      expect(
        rules.contains(
          "request.resource.data.get('assignedBranchIds', []) == resource.data.get('assignedBranchIds', [])",
        ),
        isTrue,
      );
      expect(
        rules.contains(
          "request.resource.data.get('allBranchesAccess', false) == resource.data.get('allBranchesAccess', false)",
        ),
        isTrue,
      );
    });

    test('permissive empty-branch auto-grant removed', () {
      expect(
        rules.contains(
          "memberData(businessId).get('assignedBranchIds', []).size() == 0",
        ),
        isFalse,
      );
      expect(rules.contains("&& normalized == 'main'"), isFalse);
      expect(rules.contains('effectiveBranchId(data)'), isTrue);
    });

    test('expense writes require permission and an active assigned branch', () {
      expect(
        rules.contains(
          "hasGrantedBusinessPermission(businessId, 'create_expense')",
        ),
        isTrue,
      );
      expect(rules.contains('canCreateExpenseInBranch'), isTrue);
      expect(rules.contains('branchIsActive(businessId'), isTrue);
    });

    test('owners do not require assigned branch ids', () {
      expect(
        rules.contains(
          'function hasBranchAccess(businessId, branchId) {\n'
          '      return isBusinessOwner(businessId)',
        ),
        isTrue,
      );
    });

    test('supplier masters are business-level and permission protected', () {
      expect(
        rules.contains(
          "hasGrantedBusinessPermission(\n"
          '            businessId,\n'
          "            'manage_suppliers'",
        ),
        isTrue,
      );
      expect(
        rules.contains('&& !hasExplicitBranchId(request.resource.data);'),
        isTrue,
      );
      expect(rules.contains('canRecordSupplierActivity'), isTrue);
    });
  });
}
