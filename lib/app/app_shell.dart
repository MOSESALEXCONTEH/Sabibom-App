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

class AuthenticatedAppShell extends ConsumerStatefulWidget {
  const AuthenticatedAppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AuthenticatedAppShell> createState() =>
      _AuthenticatedAppShellState();
}

class _AuthenticatedAppShellState extends ConsumerState<AuthenticatedAppShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _replayPending());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _replayPending();
  }

  void _replayPending() {
    if (!mounted) return;
    unawaited(ref.read(offlineMutationQueueProvider).syncPending());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = ref.watch(isOnlineProvider).asData?.value ?? true;
    ref.listen(isOnlineProvider, (previous, next) {
      if (previous?.asData?.value == false && next.asData?.value == true) {
        _replayPending();
      }
    });
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
            Expanded(child: widget.navigationShell),
          ],
        ),
        bottomNavigationBar: ModernBottomNavigation(
          terminology: terminology,
          selectedIndex: widget.navigationShell.currentIndex,
          onDestinationSelected: (index) => widget.navigationShell.goBranch(
            index,
            initialLocation: index == widget.navigationShell.currentIndex,
          ),
        ),
      ),
    );
  }
}
