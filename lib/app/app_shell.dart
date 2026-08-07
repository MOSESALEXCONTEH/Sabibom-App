import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/services/connectivity_service.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/app_status_views.dart';
import '../features/billing/application/billing_providers.dart';
import 'widgets/modern_bottom_navigation.dart';

class AuthenticatedAppShell extends ConsumerWidget {
  const AuthenticatedAppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = ref.watch(isOnlineProvider).asData?.value ?? true;
    final access = ref.watch(currentBusinessAccessProvider).asData?.value;
    final accessBlocked = access != null && !access.allowed;
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
            Expanded(
              child: accessBlocked
                  ? const _SubscriptionRequired()
                  : navigationShell,
            ),
          ],
        ),
        bottomNavigationBar: ModernBottomNavigation(
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

class _SubscriptionRequired extends StatelessWidget {
  const _SubscriptionRequired();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.lock_clock_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Business access has ended',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Open Plans & Billing to review this business subscription.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => context.push('/settings/billing'),
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Plans & Billing'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
