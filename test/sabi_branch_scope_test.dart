import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/sabi/data/local_business_answers.dart';

void main() {
  group('SabiBranchScope', () {
    test('East includes only East records', () {
      const scope = SabiBranchScope(branchId: 'east', isMainBranch: false);

      expect(scope.matches({'branchId': 'east'}), isTrue);
      expect(scope.matches({'branchId': 'main'}), isFalse);
      expect(scope.matches(<String, dynamic>{}), isFalse);
    });

    test('Main retains branchless compatibility', () {
      const scope = SabiBranchScope(branchId: 'main-id', isMainBranch: true);

      expect(scope.matches({'branchId': 'main-id'}), isTrue);
      expect(scope.matches(<String, dynamic>{}), isTrue);
      expect(scope.matches({'branchId': ''}), isTrue);
      expect(scope.matches({'branchId': 'east'}), isFalse);
    });

    test('All Branches includes branch-owned and legacy records', () {
      const scope = SabiBranchScope(branchId: null, isMainBranch: false);

      expect(scope.matches({'branchId': 'east'}), isTrue);
      expect(scope.matches(<String, dynamic>{}), isTrue);
    });
  });
}
