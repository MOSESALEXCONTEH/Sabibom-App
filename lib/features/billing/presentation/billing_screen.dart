import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/formatting/currency_formatter.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_status_views.dart';
import '../application/billing_providers.dart';
import '../domain/billing_models.dart';

class BillingScreen extends ConsumerWidget {
  const BillingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(currentBusinessAccessProvider);
    final plans = ref.watch(activeSubscriptionPlansProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Plans & Billing')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(currentBusinessSubscriptionProvider);
          ref.invalidate(activeSubscriptionPlansProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            40,
          ),
          children: <Widget>[
            access.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => AppErrorState(
                title: 'Could not load billing',
                message: '$error',
                onRetry: () =>
                    ref.invalidate(currentBusinessSubscriptionProvider),
              ),
              data: (value) => _AccessCard(access: value),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Available plans',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            plans.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Text('Plans are unavailable: $error'),
              data: (items) => items.isEmpty
                  ? const AppEmptyState(
                      title: 'No active plans',
                      description: 'Active plans will appear here.',
                    )
                  : Column(
                      children: items
                          .map(
                            (plan) => Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.md,
                              ),
                              child: _PlanCard(plan: plan),
                            ),
                          )
                          .toList(growable: false),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.access});
  final BusinessAccess access;

  @override
  Widget build(BuildContext context) {
    final subscription = access.subscription;
    final color = access.allowed
        ? Colors.green
        : Theme.of(context).colorScheme.error;
    final end = subscription?.currentPeriodEnd ?? subscription?.trialEndsAt;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                access.allowed ? Icons.verified_outlined : Icons.lock_outline,
                color: color,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  access.isLegacyGrace
                      ? 'Current access'
                      : subscription?.accessType == 'complimentary'
                      ? 'Complimentary access'
                      : 'Subscription ${subscription?.status ?? ''}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (subscription != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text('Status: ${subscription.status.replaceAll('_', ' ')}'),
            if (end != null)
              Text('Access until ${DateFormat.yMMMd().add_jm().format(end)}'),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});
  final SubscriptionPlan plan;

  @override
  Widget build(BuildContext context) {
    final price = formatCurrency(
      plan.price,
      code: plan.currency,
      symbol: plan.currency,
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  plan.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text('$price / ${plan.billingInterval.replaceAll('_', ' ')}'),
            ],
          ),
          if (plan.description.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(plan.description),
          ],
          if (plan.features.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            ...plan.features.map(
              (feature) => Row(
                children: <Widget>[
                  const Icon(Icons.check, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(feature)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
