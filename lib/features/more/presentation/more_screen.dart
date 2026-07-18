import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/application/auth_controller.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('More')),
    body: ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: <Widget>[
        _item(
          context,
          Icons.storefront_outlined,
          'Business Profile',
          () => context.push(AppRoutes.businessProfile),
        ),
        _item(
          context,
          Icons.payments_outlined,
          'Expenses',
          () => context.push(AppRoutes.expenses),
        ),
        _item(
          context,
          Icons.bar_chart_outlined,
          'Reports',
          () => context.push(AppRoutes.reports),
        ),
        _item(
          context,
          Icons.settings_outlined,
          'Settings',
          () => context.push(AppRoutes.settings),
        ),
        _item(
          context,
          Icons.support_agent_outlined,
          'Help and Support',
          () => context.push(AppRoutes.help),
        ),
        _item(
          context,
          Icons.info_outline,
          'About SabiBom',
          () => context.push(AppRoutes.about),
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
          onPressed: () => _confirmSignOut(context, ref),
        ),
      ],
    ),
  );

  Widget _item(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap,
  ) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign in again at any time.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authControllerProvider.notifier).signOut();
    if (context.mounted) context.go(AppRoutes.onboarding);
  }
}
