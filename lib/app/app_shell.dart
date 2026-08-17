import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/services/connectivity_service.dart';
import '../core/sync/offline_mutation_queue.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/app_status_views.dart';
import '../features/business_setup/application/business_experience_providers.dart';
import 'widgets/modern_bottom_navigation.dart';

class AuthenticatedAppShell extends ConsumerWidget {
  const AuthenticatedAppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = ref.watch(isOnlineProvider).asData?.value ?? true;
    ref.listen(isOnlineProvider, (_, next) {
      if (next.asData?.value == true) {
        unawaited(ref.read(offlineMutationQueueProvider).syncPending());
      }
    });
    if (isOnline) {
      unawaited(ref.read(offlineMutationQueueProvider).syncPending());
    }
    final terminology = ref.watch(currentBusinessTerminologyProvider);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: isDark
                ? const Color(0xFF10141F)
                : AppColors.background,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: isDark
                ? Brightness.light
                : Brightness.dark,
          ),
      child: Scaffold(
        body: Column(
          children: <Widget>[
            if (!isOnline)
              const OfflineBanner(
                message:
                    'Offline: showing saved data. New changes may wait to sync.',
              ),
            Expanded(child: navigationShell),
          ],
        ),
        bottomNavigationBar: ModernBottomNavigation(
          terminology: terminology,
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
        ),
      ),
    );
  }
}
