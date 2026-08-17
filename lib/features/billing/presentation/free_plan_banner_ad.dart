import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../application/ads_providers.dart';

class FreePlanBannerAd extends ConsumerStatefulWidget {
  const FreePlanBannerAd({super.key});

  @override
  ConsumerState<FreePlanBannerAd> createState() => _FreePlanBannerAdState();
}

class _FreePlanBannerAdState extends ConsumerState<FreePlanBannerAd> {
  BannerAd? _banner;
  bool _loading = false;

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shouldShow = ref.watch(shouldShowFreePlanAdsProvider);
    final configuration = ref
        .watch(mobileAdsConfigurationProvider)
        .asData
        ?.value;
    if (!shouldShow || configuration == null) {
      _disposeBanner();
      return const SizedBox.shrink();
    }
    if (_banner == null && !_loading) {
      _load(configuration.effectiveBannerUnitId);
    }
    final banner = _banner;
    if (banner == null) return const SizedBox.shrink();
    return Semantics(
      label: 'Advertisement',
      child: Center(
        child: SizedBox(
          width: banner.size.width.toDouble(),
          height: banner.size.height.toDouble(),
          child: AdWidget(ad: banner),
        ),
      ),
    );
  }

  Future<void> _load(String unitId) async {
    _loading = true;
    final consent = ConsentInformation.instance;
    final consentReady = Completer<void>();
    consent.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
        if (!consentReady.isCompleted) consentReady.complete();
      },
      (_) {
        if (!consentReady.isCompleted) consentReady.complete();
      },
    );
    await consentReady.future;
    if (!await consent.canRequestAds()) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    await MobileAds.instance.initialize();
    final banner = BannerAd(
      adUnitId: unitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _banner = ad as BannerAd;
            _loading = false;
          });
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _loading = false);
        },
      ),
    );
    await banner.load();
  }

  void _disposeBanner() {
    final banner = _banner;
    if (banner == null) return;
    _banner = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => banner.dispose());
  }
}
