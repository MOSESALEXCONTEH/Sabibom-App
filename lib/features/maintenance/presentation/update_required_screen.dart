import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_spacing.dart';
import '../application/release_gate.dart';

class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({required this.decision, super.key});

  final ReleaseGateDecision decision;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.system_update_alt,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Update required',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Your SabiBom version ${decision.currentVersion} is no longer supported. Update to continue securely.',
                  textAlign: TextAlign.center,
                ),
                if (decision.release.releaseNotes?.trim().isNotEmpty ==
                    true) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    decision.release.releaseNotes!,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  onPressed: decision.release.storeUrl == null
                      ? null
                      : () => launchUrl(
                          Uri.parse(decision.release.storeUrl!),
                          mode: LaunchMode.externalApplication,
                        ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Update SabiBom'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
