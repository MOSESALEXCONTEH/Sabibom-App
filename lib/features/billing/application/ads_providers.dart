import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/billing_entitlements.dart';
import '../presentation/billing_gate.dart';

class MobileAdsConfiguration {
  const MobileAdsConfiguration({
    required this.enabled,
    required this.bannerUnitId,
  });

  factory MobileAdsConfiguration.fromMap(Map<String, dynamic> data) {
    final ads = data['ads'];
    final mobile = ads is Map ? ads['mobile'] : null;
    final values = mobile is Map
        ? Map<String, dynamic>.from(mobile)
        : const <String, dynamic>{};
    return MobileAdsConfiguration(
      enabled: values['enabled'] == true,
      bannerUnitId: values['androidBannerUnitId'] as String? ?? '',
    );
  }

  static const disabled = MobileAdsConfiguration(
    enabled: false,
    bannerUnitId: '',
  );

  final bool enabled;
  final String bannerUnitId;

  String get effectiveBannerUnitId => kDebugMode
      ? 'ca-app-pub-3940256099942544/6300978111'
      : bannerUnitId.trim();
}

final mobileAdsConfigurationProvider = StreamProvider<MobileAdsConfiguration>((
  ref,
) {
  return FirebaseFirestore.instance
      .collection('platform_settings')
      .doc('public')
      .snapshots()
      .map(
        (snapshot) => snapshot.exists && snapshot.data() != null
            ? MobileAdsConfiguration.fromMap(snapshot.data()!)
            : MobileAdsConfiguration.disabled,
      );
});

final shouldShowFreePlanAdsProvider = Provider<bool>((ref) {
  final planAllowsAds = ref.watch(
    entitlementEnabledProvider(BillingEntitlementKeys.adsEnabled),
  );
  final configuration =
      ref.watch(mobileAdsConfigurationProvider).asData?.value ??
      MobileAdsConfiguration.disabled;
  return planAllowsAds &&
      configuration.enabled &&
      configuration.effectiveBannerUnitId.isNotEmpty;
});
