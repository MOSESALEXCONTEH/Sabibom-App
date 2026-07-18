import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_logo.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/user_profile_provider.dart';

/// Initial settings home ready for account and business preference sections.
class SettingsScreen extends ConsumerWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).asData?.value;
    final hasBusiness = profile?.hasActiveBusiness == true;
    final setupInProgress = profile?.businessSetupStatus == 'in_progress';
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: <Widget>[
          const Center(child: AppLogo(size: 72)),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: ListTile(
              title: const Text('Business profile'),
              subtitle: Text(
                hasBusiness
                    ? profile?.businessName ?? 'Business set up'
                    : setupInProgress
                    ? 'Setup incomplete'
                    : 'Not set up',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(
                hasBusiness ? AppRoutes.businessProfile : AppRoutes.businessSetup,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Card(child: ListTile(title: Text('Notifications'))),
          const SizedBox(height: AppSpacing.sm),
          const Card(child: ListTile(title: Text('Data and privacy'))),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).signOut();
              if (context.mounted) context.go(AppRoutes.onboarding);
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}