import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/theme/app_spacing.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../team/application/team_providers.dart';
import '../../team/domain/app_permission.dart';
import '../../team/presentation/team_widgets.dart';

/// Owner/developer-only release readiness indicators (no secrets).
class ReleaseReadinessScreen extends ConsumerWidget {
  const ReleaseReadinessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(currentBusinessMembershipProvider).asData?.value;
    final isOwner = membership?.isOwner == true;
    final canEdit = ref.watch(
      hasPermissionProvider(AppPermission.editBusinessSettings),
    );
    if (!isOwner && !canEdit && !kDebugMode) {
      return const AccessDeniedScreen(
        message: 'Release readiness is only available to owners.',
      );
    }

    final active = ref.watch(activeBusinessProvider).asData?.value;
    final businessLabel = active is ActiveBusinessData
        ? '${active.business.name}${active.business.isDemo ? ' (Demo)' : ''}'
        : 'No active business';

    return Scaffold(
      appBar: AppBar(title: const Text('Release readiness')),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snap) {
          final info = snap.data;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _row('App version', info == null ? '…' : info.version),
              _row('Build number', info == null ? '…' : info.buildNumber),
              _row('Environment', kReleaseMode ? 'release' : 'debug'),
              _row(
                'Firebase initialized',
                Firebase.apps.isEmpty ? 'No' : 'Yes',
              ),
              _row(
                'Auth status',
                FirebaseAuth.instance.currentUser == null
                    ? 'Signed out'
                    : 'Signed in',
              ),
              _row('Active business', businessLabel),
              _row(
                'Package',
                info?.packageName ?? 'com.sabibom.app',
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'This screen never shows tokens, API keys or private keys. '
                'Use docs/launch_checklist.md and docs/go_no_go_report.md for the full gate.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Text(
          value,
          textAlign: TextAlign.end,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
