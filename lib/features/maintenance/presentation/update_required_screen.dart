import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_spacing.dart';
import '../application/release_gate.dart';

class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({
    required this.decision,
    required this.onCheckAgain,
    super.key,
  });

  final ReleaseGateDecision decision;
  final VoidCallback onCheckAgain;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  String? _error;

  Future<void> _open(Uri uri, {required String failureMessage}) async {
    setState(() => _error = null);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) setState(() => _error = failureMessage);
    } catch (_) {
      if (mounted) setState(() => _error = failureMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = widget.decision.policy;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Icon(
                        Icons.system_update_alt,
                        size: 52,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    policy.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(policy.message, textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.md),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        children: [
                          _VersionRow(
                            label: 'Installed',
                            value:
                                '${widget.decision.currentVersion} (${widget.decision.currentBuildNumber})',
                          ),
                          _VersionRow(
                            label: 'Required build',
                            value: policy.minimumBuildNumber ?? 'Unavailable',
                          ),
                          if (policy.displayVersion != null)
                            _VersionRow(
                              label: 'Available version',
                              value:
                                  '${policy.displayVersion} (${policy.latestBuildNumber ?? '—'})',
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: policy.storeUrl == null
                          ? null
                          : () => _open(
                              Uri.parse(policy.storeUrl!),
                              failureMessage:
                                  'Google Play could not be opened. Check your connection or contact support.',
                            ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Update in Google Play'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          setState(() => _error = null);
                          widget.onCheckAgain();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Checking update status…'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Check again'),
                      ),
                      TextButton(
                        onPressed: () => _open(
                          Uri.parse('https://sabibom.com/support'),
                          failureMessage:
                              'Support could not be opened. Visit sabibom.com/support.',
                        ),
                        child: const Text('Contact support'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: AppSpacing.sm),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
