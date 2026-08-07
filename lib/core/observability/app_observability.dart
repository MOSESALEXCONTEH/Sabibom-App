import 'dart:ui';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract final class AppObservability {
  static Future<void> initialize() async {
    final enabled = kReleaseMode;
    await Future.wait(<Future<void>>[
      FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled),
      FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(enabled),
      FirebasePerformance.instance.setPerformanceCollectionEnabled(enabled),
    ]);

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      if (enabled) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      if (enabled) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      }
      return true;
    };

    ErrorWidget.builder = (details) {
      if (!kReleaseMode) return ErrorWidget(details.exception);
      return const _ProductionErrorView();
    };
  }

  static Future<void> identifyUser(String? uid) async {
    if (!kReleaseMode) return;
    await FirebaseCrashlytics.instance.setUserIdentifier(uid ?? 'signed-out');
    await FirebaseAnalytics.instance.setUserId(id: uid);
  }

  static Future<void> recordNonFatal(
    Object error,
    StackTrace stack, {
    required String reason,
  }) async {
    if (!kReleaseMode) return;
    await FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      reason: reason,
      fatal: false,
    );
  }
}

class _ProductionErrorView extends StatelessWidget {
  const _ProductionErrorView();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'This screen could not be displayed.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Close this screen and try again.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
