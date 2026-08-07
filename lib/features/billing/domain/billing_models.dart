import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.currency,
    required this.price,
    required this.billingInterval,
    required this.features,
    required this.trialDays,
  });

  factory SubscriptionPlan.fromMap(String id, Map<String, dynamic> data) {
    return SubscriptionPlan(
      id: id,
      name: data['name'] as String? ?? 'Plan',
      description: data['description'] as String? ?? '',
      currency: data['currency'] as String? ?? 'USD',
      price: (data['price'] as num?)?.toDouble() ?? 0,
      billingInterval: data['billingInterval'] as String? ?? 'monthly',
      features:
          (data['features'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const <String>[],
      trialDays: (data['trialDays'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final String description;
  final String currency;
  final double price;
  final String billingInterval;
  final List<String> features;
  final int trialDays;
}

class BusinessSubscription {
  const BusinessSubscription({
    required this.businessId,
    required this.planId,
    required this.status,
    required this.accessType,
    this.currentPeriodEnd,
    this.trialEndsAt,
  });

  factory BusinessSubscription.fromMap(
    String businessId,
    Map<String, dynamic> data,
  ) {
    return BusinessSubscription(
      businessId: businessId,
      planId: data['planId'] as String? ?? '',
      status: data['status'] as String? ?? 'not_configured',
      accessType: data['accessType'] as String? ?? 'paid',
      currentPeriodEnd: _date(data['currentPeriodEnd']),
      trialEndsAt: _date(data['trialEndsAt']),
    );
  }

  final String businessId;
  final String planId;
  final String status;
  final String accessType;
  final DateTime? currentPeriodEnd;
  final DateTime? trialEndsAt;

  bool hasAccessAt(DateTime now) {
    if (status != 'active' && status != 'trialing') return false;
    final end = status == 'trialing'
        ? trialEndsAt ?? currentPeriodEnd
        : currentPeriodEnd;
    return end == null || end.isAfter(now);
  }
}

class BusinessAccess {
  const BusinessAccess({
    required this.allowed,
    required this.isLegacyGrace,
    this.subscription,
  });

  factory BusinessAccess.fromSubscription(
    BusinessSubscription? subscription, {
    DateTime? now,
  }) {
    if (subscription == null) {
      return const BusinessAccess(allowed: true, isLegacyGrace: true);
    }
    return BusinessAccess(
      allowed: subscription.hasAccessAt(now ?? DateTime.now()),
      isLegacyGrace: false,
      subscription: subscription,
    );
  }

  final bool allowed;
  final bool isLegacyGrace;
  final BusinessSubscription? subscription;
}
