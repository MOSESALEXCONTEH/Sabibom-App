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
    required this.limits,
    required this.trialDays,
    required this.tier,
    required this.googlePlayProductId,
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
      limits:
          (data['limits'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value),
          ) ??
          const <String, dynamic>{},
      trialDays: (data['trialDays'] as num?)?.toInt() ?? 0,
      tier: data['tier'] as String? ?? '',
      googlePlayProductId: data['googlePlayProductId'] as String? ?? '',
    );
  }

  final String id;
  final String name;
  final String description;
  final String currency;
  final double price;
  final String billingInterval;
  final List<String> features;
  final Map<String, dynamic> limits;
  final int trialDays;
  final String tier;
  final String googlePlayProductId;
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
    const accessibleStatuses = <String>{
      'active',
      'trialing',
      'grace_period',
      'canceled',
      'cancelled',
    };
    if (!accessibleStatuses.contains(status)) return false;
    final end = accessEnd;
    if (status == 'canceled' && end == null) return false;
    return end == null || end.isAfter(now);
  }

  DateTime? get accessEnd =>
      status == 'trialing' ? trialEndsAt ?? currentPeriodEnd : currentPeriodEnd;
}
