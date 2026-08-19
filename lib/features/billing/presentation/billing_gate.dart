import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../maintenance/data/runtime_configuration_repository.dart';
import '../application/billing_providers.dart';
import '../domain/billing_entitlements.dart';

final entitlementEnabledProvider = Provider.family<bool, String>((ref, key) {
  final resolved = ref.watch(currentBusinessEntitlementsProvider).asData?.value;
  final entitlements =
      resolved?.entitlements ?? BusinessEntitlements.forTier(BillingTier.free);
  return entitlements.isEnabled(key);
});

final entitlementLimitProvider = Provider.family<int, String>((ref, key) {
  final resolved = ref.watch(currentBusinessEntitlementsProvider).asData?.value;
  final entitlements =
      resolved?.entitlements ?? BusinessEntitlements.forTier(BillingTier.free);
  return entitlements.limit(key);
});

Future<bool> requireEntitlement(
  BuildContext context,
  WidgetRef ref, {
  required String key,
  required String featureName,
}) async {
  final access = ref.read(currentBusinessEntitlementsProvider);
  if (access.isLoading) {
    _showAccessStatus(
      context,
      'Checking feature access. Try again in a moment.',
    );
    return false;
  }
  if (access.hasError) {
    _showAccessStatus(
      context,
      'Could not verify feature access. Check your connection and try again.',
    );
    return false;
  }
  if (access.requireValue.entitlements.isEnabled(key)) return true;
  return _showUpgradeDialog(context, featureName);
}

Future<bool> requireEntitlementCapacity(
  BuildContext context,
  WidgetRef ref, {
  required String key,
  required int currentUsage,
  required String featureName,
}) async {
  final access = ref.read(currentBusinessEntitlementsProvider);
  if (access.isLoading) {
    _showAccessStatus(
      context,
      'Checking feature access. Try again in a moment.',
    );
    return false;
  }
  if (access.hasError) {
    _showAccessStatus(
      context,
      'Could not verify feature access. Check your connection and try again.',
    );
    return false;
  }
  final limit = access.requireValue.entitlements.limit(key);
  if (limit == BusinessEntitlements.unlimited || currentUsage < limit) {
    return true;
  }
  return _showUpgradeDialog(context, featureName);
}

void _showAccessStatus(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> _showUpgradeDialog(
  BuildContext context,
  String featureName,
) async {
  final openBilling = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('$featureName is available on Pro'),
      content: const Text(
        'Your existing business data remains available. Upgrade to Pro to use '
        'this feature.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Not now'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.workspace_premium_outlined),
          label: const Text('View plans'),
        ),
      ],
    ),
  );
  if (openBilling == true && context.mounted) {
    context.pushNamed(AppRouteNames.billing);
  }
  return false;
}

class EntitlementGate extends ConsumerWidget {
  const EntitlementGate({
    required this.entitlementKey,
    required this.featureName,
    required this.child,
    super.key,
  });

  final String entitlementKey;
  final String featureName;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(currentBusinessEntitlementsProvider);
    if (access.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(featureName)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (access.hasError) {
      return Scaffold(
        appBar: AppBar(title: Text(featureName)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.cloud_off_outlined, size: 52),
                  const SizedBox(height: 16),
                  Text(
                    'Could not verify feature access',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Check your connection and try again. No subscription '
                    'change is needed.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      ref
                        ..invalidate(runtimeConfigurationProvider)
                        ..invalidate(currentBusinessSubscriptionProvider)
                        ..invalidate(activeSubscriptionPlansProvider);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final enabled = access.requireValue.entitlements.isEnabled(entitlementKey);
    if (enabled) return child;
    return Scaffold(
      appBar: AppBar(title: Text(featureName)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.workspace_premium_outlined,
                  size: 52,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  '$featureName is a Pro feature',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Upgrade the business plan to unlock this feature. Your '
                  'existing records are not affected.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => context.pushNamed(AppRouteNames.billing),
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: const Text('View plans'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ReportHistoryGate extends ConsumerWidget {
  const ReportHistoryGate({
    required this.reportDate,
    required this.child,
    super.key,
  });

  final DateTime? reportDate;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limit = ref.watch(
      entitlementLimitProvider(BillingEntitlementKeys.reportsHistoryDays),
    );
    final date = reportDate;
    if (date == null || limit == BusinessEntitlements.unlimited) return child;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final oldest = today.subtract(Duration(days: limit - 1));
    final normalized = DateTime(date.year, date.month, date.day);
    if (!normalized.isBefore(oldest)) return child;
    return Scaffold(
      appBar: AppBar(title: const Text('Report history')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.history_toggle_off_outlined, size: 52),
              const SizedBox(height: 16),
              Text(
                'The Free plan includes $limit days of report history.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Upgrade to Pro to view the complete business history.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => context.pushNamed(AppRouteNames.billing),
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('View plans'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
