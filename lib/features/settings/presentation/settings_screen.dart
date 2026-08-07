import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme_mode_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_list_primitives.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/app_tab_page_scaffold.dart';
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
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppTabChrome.bottomInset + AppSpacing.md,
        ),
        children: <Widget>[
          const Center(child: AppLogo(size: 72)),
          const SizedBox(height: AppSpacing.lg),
          const AppSectionHeader('Business'),
          AppSectionCard(
            children: [
              ListTile(
                leading: Icon(
                  Icons.storefront_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('Business profile'),
                subtitle: Text(
                  hasBusiness
                      ? profile?.businessName ?? 'Business set up'
                      : setupInProgress
                      ? 'Setup incomplete'
                      : 'Not set up',
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: context.mutedTextColor,
                ),
                onTap: () => context.push(
                  hasBusiness
                      ? AppRoutes.businessProfile
                      : AppRoutes.businessSetup,
                ),
              ),
              Divider(height: 1, indent: 56, color: context.borderColor),
              ListTile(
                leading: Icon(
                  Icons.store_mall_directory_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('Business branches'),
                subtitle: const Text('Create and manage branch locations'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: context.mutedTextColor,
                ),
                onTap: () => context.pushNamed(AppRouteNames.settingsBranches),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const AppSectionHeader('Appearance'),
          AppSectionCard(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm + 4,
              AppSpacing.md,
              AppSpacing.md,
            ),
            children: [
              SegmentedButton<ThemeMode>(
                segments: const <ButtonSegment<ThemeMode>>[
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('Auto'),
                    icon: Icon(Icons.brightness_auto_outlined),
                  ),
                ],
                selected: <ThemeMode>{ref.watch(themeModeProvider)},
                onSelectionChanged: (selection) => ref
                    .read(themeModeProvider.notifier)
                    .setMode(selection.first),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const AppSectionHeader('Preferences'),
          AppSectionCard(
            children: [
              ListTile(
                leading: Icon(
                  Icons.notifications_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('Notifications'),
                subtitle: const Text('Choose which alerts you receive'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: context.mutedTextColor,
                ),
                onTap: () =>
                    context.pushNamed(AppRouteNames.settingsNotifications),
              ),
              Divider(height: 1, indent: 56, color: context.borderColor),
              ListTile(
                leading: Icon(
                  Icons.privacy_tip_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('Data and privacy'),
                subtitle: const Text('Security, privacy policy and terms'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: context.mutedTextColor,
                ),
                onTap: () => context.pushNamed(AppRouteNames.settingsSecurity),
              ),
            ],
          ),
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
