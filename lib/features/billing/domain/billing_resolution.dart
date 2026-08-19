import 'billing_entitlements.dart';
import 'billing_models.dart';

enum EntitlementResolutionSource {
  freeDefault,
  activePlan,
  complimentary,
  globalFreeAccess,
  expiredDowngrade,
  inactiveDowngrade,
}

class ResolvedBusinessEntitlements {
  const ResolvedBusinessEntitlements({
    required this.entitlements,
    required this.source,
    this.subscription,
    this.plan,
  });

  factory ResolvedBusinessEntitlements.resolve({
    required BusinessSubscription? subscription,
    required List<SubscriptionPlan> plans,
    DateTime? now,
  }) {
    if (subscription == null) {
      return ResolvedBusinessEntitlements(
        entitlements: BusinessEntitlements.forTier(BillingTier.free),
        source: EntitlementResolutionSource.freeDefault,
      );
    }

    final resolvedNow = now ?? DateTime.now();
    if (!subscription.hasAccessAt(resolvedNow)) {
      final expired = subscription.accessEnd?.isAfter(resolvedNow) == false;
      return ResolvedBusinessEntitlements(
        entitlements: BusinessEntitlements.forTier(BillingTier.free),
        source: expired
            ? EntitlementResolutionSource.expiredDowngrade
            : EntitlementResolutionSource.inactiveDowngrade,
        subscription: subscription,
      );
    }

    final plan = _findPlan(plans, subscription.planId);
    if (subscription.accessType == 'complimentary') {
      return ResolvedBusinessEntitlements(
        entitlements: BusinessEntitlements.fromMap(
          tier: BillingTier.complimentary,
          values: plan?.limits ?? const <String, dynamic>{},
        ),
        source: EntitlementResolutionSource.complimentary,
        subscription: subscription,
        plan: plan,
      );
    }

    final tier = _resolvePaidTier(plan, subscription.planId);
    return ResolvedBusinessEntitlements(
      entitlements: BusinessEntitlements.fromMap(
        tier: tier,
        values: plan?.limits ?? const <String, dynamic>{},
      ),
      source: EntitlementResolutionSource.activePlan,
      subscription: subscription,
      plan: plan,
    );
  }

  final BusinessEntitlements entitlements;
  final EntitlementResolutionSource source;
  final BusinessSubscription? subscription;
  final SubscriptionPlan? plan;

  BillingTier get tier => entitlements.tier;

  bool get wasDowngraded =>
      source == EntitlementResolutionSource.expiredDowngrade ||
      source == EntitlementResolutionSource.inactiveDowngrade;

  ResolvedBusinessEntitlements withGlobalFreeAccess() {
    if (tier == BillingTier.pro || tier == BillingTier.complimentary) {
      return this;
    }
    return ResolvedBusinessEntitlements(
      entitlements: BusinessEntitlements.globalFreeAccess(),
      source: EntitlementResolutionSource.globalFreeAccess,
      subscription: subscription,
      plan: plan,
    );
  }

  static SubscriptionPlan? _findPlan(
    List<SubscriptionPlan> plans,
    String planId,
  ) {
    for (final plan in plans) {
      if (plan.id == planId) return plan;
    }
    return null;
  }

  static BillingTier _resolvePaidTier(SubscriptionPlan? plan, String planId) {
    final declaredTier = plan?.tier.trim().toLowerCase();
    if (declaredTier == 'free') return BillingTier.free;
    if (declaredTier == 'pro') return BillingTier.pro;

    final searchable = '${plan?.id ?? planId} ${plan?.name ?? ''}'
        .toLowerCase();
    if (searchable.contains('free') || plan?.price == 0) {
      return BillingTier.free;
    }
    return BillingTier.pro;
  }
}
