import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/billing/domain/billing_entitlements.dart';
import 'package:sabibom/features/billing/domain/billing_models.dart';
import 'package:sabibom/features/billing/domain/billing_resolution.dart';

void main() {
  final now = DateTime(2026, 8, 16, 12);

  SubscriptionPlan plan({
    required String id,
    required String tier,
    double price = 10,
    Map<String, dynamic> limits = const <String, dynamic>{},
  }) {
    return SubscriptionPlan.fromMap(id, <String, dynamic>{
      'name': tier == 'free' ? 'Free' : 'Pro',
      'tier': tier,
      'price': price,
      'limits': limits,
    });
  }

  BusinessSubscription subscription({
    String planId = 'pro-monthly',
    String status = 'active',
    String accessType = 'paid',
    DateTime? end,
  }) {
    return BusinessSubscription(
      businessId: 'business-1',
      planId: planId,
      status: status,
      accessType: accessType,
      currentPeriodEnd: end,
    );
  }

  test('business without a subscription resolves to Free', () {
    final result = ResolvedBusinessEntitlements.resolve(
      subscription: null,
      plans: const <SubscriptionPlan>[],
      now: now,
    );

    expect(result.tier, BillingTier.free);
    expect(result.source, EntitlementResolutionSource.freeDefault);
  });

  test('expired and paused subscriptions downgrade to Free', () {
    final expired = ResolvedBusinessEntitlements.resolve(
      subscription: subscription(end: now.subtract(const Duration(seconds: 1))),
      plans: const <SubscriptionPlan>[],
      now: now,
    );
    final paused = ResolvedBusinessEntitlements.resolve(
      subscription: subscription(status: 'paused'),
      plans: const <SubscriptionPlan>[],
      now: now,
    );

    expect(expired.tier, BillingTier.free);
    expect(expired.source, EntitlementResolutionSource.expiredDowngrade);
    expect(paused.tier, BillingTier.free);
    expect(paused.source, EntitlementResolutionSource.inactiveDowngrade);
  });

  test('active plan resolves its tier and entitlement overrides', () {
    final result = ResolvedBusinessEntitlements.resolve(
      subscription: subscription(),
      plans: <SubscriptionPlan>[
        plan(
          id: 'pro-monthly',
          tier: 'pro',
          limits: const <String, dynamic>{
            BillingEntitlementKeys.sabiDailyRequests: 200,
          },
        ),
      ],
      now: now,
    );

    expect(result.tier, BillingTier.pro);
    expect(
      result.entitlements.limit(BillingEntitlementKeys.sabiDailyRequests),
      200,
    );
  });

  test('active complimentary access receives Pro-equivalent entitlements', () {
    final result = ResolvedBusinessEntitlements.resolve(
      subscription: subscription(accessType: 'complimentary'),
      plans: const <SubscriptionPlan>[],
      now: now,
    );

    expect(result.tier, BillingTier.complimentary);
    expect(result.source, EntitlementResolutionSource.complimentary);
    expect(
      result.entitlements.isEnabled(BillingEntitlementKeys.reportsExport),
      isTrue,
    );
  });

  test(
    'active paid subscription preserves Pro access if plan is unavailable',
    () {
      final result = ResolvedBusinessEntitlements.resolve(
        subscription: subscription(planId: 'paid-plan'),
        plans: const <SubscriptionPlan>[],
        now: now,
      );

      expect(result.tier, BillingTier.pro);
      expect(result.source, EntitlementResolutionSource.activePlan);
    },
  );
}
