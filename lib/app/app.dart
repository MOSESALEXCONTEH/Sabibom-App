import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';
import 'theme_mode_provider.dart';
import '../features/maintenance/data/runtime_configuration_repository.dart';
import '../features/maintenance/presentation/maintenance_screen.dart';
import '../features/maintenance/application/release_gate.dart';
import '../features/maintenance/presentation/update_required_screen.dart';
import '../features/billing/application/ad_consent_controller.dart';

/// Root widget that configures SabiBom's routed Material application.
class SabiBomApp extends ConsumerStatefulWidget {
  /// Creates the application root.
  const SabiBomApp({super.key});

  @override
  ConsumerState<SabiBomApp> createState() => _SabiBomAppState();
}

class _SabiBomAppState extends ConsumerState<SabiBomApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ref.read(adConsentControllerProvider).initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshRuntimeConfiguration();
  }

  void _refreshRuntimeConfiguration() {
    ref
      ..invalidate(runtimeConfigurationProvider)
      ..invalidate(releaseGateProvider);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final runtime = ref.watch(runtimeConfigurationProvider).asData?.value;
    final releaseDecision = ref.watch(releaseGateProvider).asData?.value;
    return MaterialApp.router(
      title: 'SabiBom',
      debugShowCheckedModeBanner: false,
      theme: SabiBomTheme.light,
      darkTheme: SabiBomTheme.dark,
      themeMode: themeMode,
      routerConfig: appRouter,
      builder: (context, child) {
        final maintenance = runtime?.maintenance;
        if (maintenance?.blocksMobile == true) {
          return MaintenanceScreen(
            configuration: maintenance!,
            onRetry: _refreshRuntimeConfiguration,
          );
        }
        if (releaseDecision?.updateRequired == true) {
          return UpdateRequiredScreen(
            decision: releaseDecision!,
            onCheckAgain: _refreshRuntimeConfiguration,
          );
        }
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
