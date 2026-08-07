import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';
import 'theme_mode_provider.dart';
import '../features/maintenance/data/runtime_configuration_repository.dart';
import '../features/maintenance/presentation/maintenance_screen.dart';
import '../features/maintenance/application/release_gate.dart';
import '../features/maintenance/presentation/update_required_screen.dart';

/// Root widget that configures SabiBom's routed Material application.
class SabiBomApp extends ConsumerWidget {
  /// Creates the application root.
  const SabiBomApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            onRetry: () => ref.invalidate(runtimeConfigurationProvider),
          );
        }
        if (releaseDecision?.updateRequired == true) {
          return UpdateRequiredScreen(decision: releaseDecision!);
        }
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
