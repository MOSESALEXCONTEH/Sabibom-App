import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/billing/domain/billing_models.dart';

void main() {
  group('BusinessAccess', () {
    final now = DateTime(2026, 8, 5, 12);

    test('preserves access for businesses not migrated to billing yet', () {
      final access = BusinessAccess.fromSubscription(null, now: now);
      expect(access.allowed, isTrue);
      expect(access.isLegacyGrace, isTrue);
    });

    test('allows active complimentary access before its end date', () {
      final access = BusinessAccess.fromSubscription(
        BusinessSubscription(
          businessId: 'business-1',
          planId: 'plan-1',
          status: 'active',
          accessType: 'complimentary',
          currentPeriodEnd: now.add(const Duration(days: 30)),
        ),
        now: now,
      );
      expect(access.allowed, isTrue);
      expect(access.isLegacyGrace, isFalse);
    });

    test('blocks expired and paused subscriptions', () {
      final expired = BusinessAccess.fromSubscription(
        BusinessSubscription(
          businessId: 'business-1',
          planId: 'plan-1',
          status: 'active',
          accessType: 'paid',
          currentPeriodEnd: now.subtract(const Duration(seconds: 1)),
        ),
        now: now,
      );
      final paused = BusinessAccess.fromSubscription(
        const BusinessSubscription(
          businessId: 'business-1',
          planId: 'plan-1',
          status: 'paused',
          accessType: 'paid',
        ),
        now: now,
      );
      expect(expired.allowed, isFalse);
      expect(paused.allowed, isFalse);
    });
  });
}
