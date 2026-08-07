import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/branches/domain/business_branch.dart';

void main() {
  group('BusinessBranch Tests', () {
    test('detects multiple main branches', () {
      const branch1 = BusinessBranch(
        branchId: 'main-1',
        businessId: 'biz-1',
        name: 'Main Branch',
        code: 'MAIN',
        address: '123 Main St',
        city: 'Lagos',
        country: 'Nigeria',
        phone: '+234123',
        email: 'main@example.com',
        managerUid: null,
        isMainBranch: true,
        status: BranchStatus.active,
        createdAt: null,
        updatedAt: null,
        createdBy: 'owner-1',
      );

      const branch2 = BusinessBranch(
        branchId: 'main-2',
        businessId: 'biz-1',
        name: 'Second Main Branch',
        code: 'MAIN2',
        address: '456 Main St',
        city: 'Abuja',
        country: 'Nigeria',
        phone: '+234456',
        email: 'main2@example.com',
        managerUid: null,
        isMainBranch: true,
        status: BranchStatus.active,
        createdAt: null,
        updatedAt: null,
        createdBy: 'owner-1',
      );

      expect(hasMultipleMainBranches([branch1, branch2]), true);
    });

    test('validateUniqueBranchCode detects duplicate codes', () {
      final branches = [
        const BusinessBranch(
          branchId: 'b1',
          businessId: 'biz-1',
          name: 'Branch 1',
          code: 'B001',
          address: '123 Main',
          city: 'Lagos',
          country: 'Nigeria',
          phone: '+234123',
          email: 'b1@example.com',
          managerUid: null,
          isMainBranch: false,
          status: BranchStatus.active,
          createdAt: null,
          updatedAt: null,
          createdBy: 'owner-1',
        ),
        const BusinessBranch(
          branchId: 'b2',
          businessId: 'biz-1',
          name: 'Branch 2',
          code: 'B002',
          address: '456 Main',
          city: 'Abuja',
          country: 'Nigeria',
          phone: '+234456',
          email: 'b2@example.com',
          managerUid: null,
          isMainBranch: false,
          status: BranchStatus.active,
          createdAt: null,
          updatedAt: null,
          createdBy: 'owner-1',
        ),
      ];

      expect(validateUniqueBranchCode(branches, 'B003'), true);
      expect(validateUniqueBranchCode(branches, 'B001'), false);
      expect(validateUniqueBranchCode(branches, 'B002'), false);
    });

    test('Branch serialization round-trip', () {
      const original = BusinessBranch(
        branchId: 'b1',
        businessId: 'biz-1',
        name: 'Test Branch',
        code: 'TEST',
        address: '123 Test St',
        city: 'Lagos',
        country: 'Nigeria',
        phone: '+2341234567',
        email: 'test@example.com',
        managerUid: 'manager-1',
        isMainBranch: false,
        status: BranchStatus.active,
        createdAt: null,
        updatedAt: null,
        createdBy: 'owner-1',
      );

      final map = original.toMap();
      final deserialized = BusinessBranch.fromMap(map, 'b1');

      expect(deserialized.branchId, original.branchId);
      expect(deserialized.businessId, original.businessId);
      expect(deserialized.name, original.name);
      expect(deserialized.code, original.code);
      expect(deserialized.status, original.status);
      expect(deserialized.isMainBranch, original.isMainBranch);
    });

    test('Branch status enum values exist', () {
      expect(BranchStatus.active, isNotNull);
      expect(BranchStatus.inactive, isNotNull);
      expect(BranchStatus.archived, isNotNull);
    });

    test('matchesBranchScope only includes records for the selected branch', () {
      final matchingData = <String, dynamic>{'branchId': 'branch-a'};
      final nonMatchingData = <String, dynamic>{'branchId': 'branch-b'};
      final legacyData = <String, dynamic>{};

      expect(matchesBranchScope(matchingData, 'branch-a'), isTrue);
      expect(matchesBranchScope(nonMatchingData, 'branch-a'), isFalse);
      expect(matchesBranchScope(legacyData, 'branch-a'), isFalse);
      expect(matchesBranchScope(legacyData, 'main'), isTrue);
      expect(matchesBranchScope(legacyData, null), isTrue);
    });
  });
}

/// Helper: Check if multiple main branches exist (should always be false in valid system)
bool hasMultipleMainBranches(List<BusinessBranch> branches) {
  return branches.where((b) => b.isMainBranch).length > 1;
}

/// Helper: Validate a branch code is unique within the business
bool validateUniqueBranchCode(List<BusinessBranch> branches, String code) {
  return !branches.any((b) => b.code.toUpperCase() == code.toUpperCase());
}
