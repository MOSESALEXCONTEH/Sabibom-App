import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as timezone_data;

import 'app/app.dart';
import 'core/observability/app_observability.dart';
import 'features/notifications/data/push_notification_bootstrap.dart';
import 'firebase_options.dart';

/// Initializes platform services before mounting the SabiBom application.
Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      timezone_data.initializeTimeZones();
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        try {
          await FirebaseAppCheck.instance.activate(
            providerAndroid: kDebugMode
                ? const AndroidDebugProvider()
                : const AndroidPlayIntegrityProvider(),
            providerApple: kDebugMode
                ? const AppleDebugProvider()
                : const AppleAppAttestWithDeviceCheckFallbackProvider(),
          );
        } catch (error, stack) {
          AppObservability.recordNonFatal(
            error,
            stack,
            reason: 'app_check_initialization_failed',
          );
        }
      }
      await AppObservability.initialize();

      // Must be registered once as a top-level handler.
      FirebaseMessaging.onBackgroundMessage(
        sabibomFirebaseMessagingBackgroundHandler,
      );

      // Register FCM tokens and attach only the opaque user ID to diagnostics.
      final pushNotifications = PushNotificationBootstrap();
      FirebaseAuth.instance.authStateChanges().listen((user) {
        AppObservability.identifyUser(user?.uid);
        if (user == null) return;
        pushNotifications.registerCurrentUserToken();
      });

      runApp(const ProviderScope(child: SabiBomApp()));
    },
    (error, stack) {
      AppObservability.recordNonFatal(
        error,
        stack,
        reason: 'uncaught_zone_error',
      );
    },
  );
}
