import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/billing/domain/billing_entitlements.dart';

void main() {
  group('BusinessEntitlements', () {
    test('Free keeps core records available while limiting premium tools', () {
      final entitlements = BusinessEntitlements.forTier(BillingTier.free);

      expect(entitlements.limit(BillingEntitlementKeys.branchesMax), 1);
      expect(entitlements.limit(BillingEntitlementKeys.staffMax), 2);
      expect(entitlements.limit(BillingEntitlementKeys.reportsHistoryDays), 30);
      expect(entitlements.limit(BillingEntitlementKeys.sabiDailyRequests), 10);
      expect(
        entitlements.isEnabled(BillingEntitlementKeys.reportsAdvanced),
        isFalse,
      );
      expect(
        entitlements.isEnabled(BillingEntitlementKeys.reportsExport),
        isFalse,
      );
      expect(entitlements.isEnabled(BillingEntitlementKeys.adsEnabled), isTrue);
    });

    test('Pro enables premium tools and removes usage limits', () {
      final entitlements = BusinessEntitlements.forTier(BillingTier.pro);

      expect(
        entitlements.isUnlimited(BillingEntitlementKeys.branchesMax),
        isTrue,
      );
      expect(entitlements.isUnlimited(BillingEntitlementKeys.staffMax), isTrue);
      expect(
        entitlements.isUnlimited(BillingEntitlementKeys.reportsHistoryDays),
        isTrue,
      );
      expect(
        entitlements.isUnlimited(BillingEntitlementKeys.sabiDailyRequests),
        isTrue,
      );
      expect(
        entitlements.isEnabled(BillingEntitlementKeys.reportsAdvanced),
        isTrue,
      );
      expect(
        entitlements.isEnabled(BillingEntitlementKeys.reportsExport),
        isTrue,
      );
      expect(
        entitlements.isEnabled(BillingEntitlementKeys.messagingBulk),
        isTrue,
      );
      expect(
        entitlements.isEnabled(BillingEntitlementKeys.adsEnabled),
        isFalse,
      );
    });

    test('Complimentary receives the same product access as Pro', () {
      final pro = BusinessEntitlements.forTier(BillingTier.pro);
      final complimentary = BusinessEntitlements.forTier(
        BillingTier.complimentary,
      );

      expect(complimentary.toMap(), pro.toMap());
    });

    test('stored values override defaults and unknown keys are ignored', () {
      final entitlements = BusinessEntitlements.fromMap(
        tier: BillingTier.free,
        values: const <String, dynamic>{
          BillingEntitlementKeys.staffMax: 5.0,
          BillingEntitlementKeys.reportsExport: true,
          'unknown.limit': 999,
        },
      );

      expect(entitlements.limit(BillingEntitlementKeys.staffMax), 5);
      expect(
        entitlements.isEnabled(BillingEntitlementKeys.reportsExport),
        isTrue,
      );
      expect(entitlements.toMap(), isNot(contains('unknown.limit')));
      expect(entitlements.limit(BillingEntitlementKeys.branchesMax), 1);
    });
  });
}
