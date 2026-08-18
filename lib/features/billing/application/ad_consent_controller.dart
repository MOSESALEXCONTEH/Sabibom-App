import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Coordinates Google's UMP consent flow and initializes Mobile Ads at most
/// once per app process.
class AdConsentController {
  Future<bool>? _consentInitialization;
  Future<InitializationStatus>? _mobileAdsInitialization;

  /// Refreshes consent information once for this app launch, presents any
  /// required message, and initializes Mobile Ads only when ads may be
  /// requested. A previous-session consent decision may still permit ads when
  /// the network refresh fails, as recommended by Google UMP.
  Future<bool> initialize() =>
      _consentInitialization ??= _initializeConsentAndAds();

  Future<bool> _initializeConsentAndAds() async {
    try {
      final information = ConsentInformation.instance;
      final update = Completer<FormError?>();
      information.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () {
          if (!update.isCompleted) update.complete();
        },
        (error) {
          if (!update.isCompleted) update.complete(error);
        },
      );

      final updateError = await update.future;
      if (updateError == null) {
        final form = Completer<FormError?>();
        ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (!form.isCompleted) form.complete(error);
        });
        await form.future;
      }

      final canRequestAds = await information.canRequestAds();
      if (canRequestAds) {
        await (_mobileAdsInitialization ??= MobileAds.instance.initialize());
      }
      return canRequestAds;
    } catch (_) {
      return false;
    }
  }

  Future<bool> privacyOptionsRequired() async {
    try {
      await initialize();
      return await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  /// Presents the publisher-rendered privacy options form. Returns a user-safe
  /// error message, or null when the form closes successfully.
  Future<String?> showPrivacyOptions() async {
    if (!await privacyOptionsRequired()) {
      return 'Privacy choices are not required for this device.';
    }
    final shown = Completer<FormError?>();
    ConsentForm.showPrivacyOptionsForm((error) {
      if (!shown.isCompleted) shown.complete(error);
    });
    final error = await shown.future;
    return error == null
        ? null
        : 'Privacy choices could not be opened. Please try again.';
  }
}

final adConsentControllerProvider = Provider<AdConsentController>(
  (ref) => AdConsentController(),
);

final adPrivacyOptionsRequiredProvider = FutureProvider<bool>(
  (ref) => ref.watch(adConsentControllerProvider).privacyOptionsRequired(),
);
