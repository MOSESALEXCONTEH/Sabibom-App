import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/billing/domain/billing_models.dart';

void main() {
  test('SubscriptionPlan reads its entitlement limits', () {
    final plan = SubscriptionPlan.fromMap('free', <String, dynamic>{
      'name': 'Free',
      'limits': <String, dynamic>{'branches.max': 1, 'reports.export': false},
      'googlePlayProductId': 'sabibom_pro_monthly',
    });

    expect(plan.limits['branches.max'], 1);
    expect(plan.limits['reports.export'], isFalse);
    expect(plan.googlePlayProductId, 'sabibom_pro_monthly');
  });

  group('BusinessSubscription', () {
    final now = DateTime(2026, 8, 5, 12);

    test('allows active access before its end date', () {
      final subscription = BusinessSubscription(
        businessId: 'business-1',
        planId: 'plan-1',
        status: 'active',
        accessType: 'complimentary',
        currentPeriodEnd: now.add(const Duration(days: 30)),
      );
      expect(subscription.hasAccessAt(now), isTrue);
    });

    test('blocks expired and paused subscriptions', () {
      final expired = BusinessSubscription(
        businessId: 'business-1',
        planId: 'plan-1',
        status: 'active',
        accessType: 'paid',
        currentPeriodEnd: now.subtract(const Duration(seconds: 1)),
      );
      const paused = BusinessSubscription(
        businessId: 'business-1',
        planId: 'plan-1',
        status: 'paused',
        accessType: 'paid',
      );
      expect(expired.hasAccessAt(now), isFalse);
      expect(paused.hasAccessAt(now), isFalse);
    });

    test('canceled subscription remains active only until period end', () {
      final current = BusinessSubscription(
        businessId: 'business-1',
        planId: 'plan-1',
        status: 'canceled',
        accessType: 'paid',
        currentPeriodEnd: now.add(const Duration(days: 2)),
      );
      const missingEnd = BusinessSubscription(
        businessId: 'business-1',
        planId: 'plan-1',
        status: 'canceled',
        accessType: 'paid',
      );

      expect(current.hasAccessAt(now), isTrue);
      expect(missingEnd.hasAccessAt(now), isFalse);
    });
  });
}
