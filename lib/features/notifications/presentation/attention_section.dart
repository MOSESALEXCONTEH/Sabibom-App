import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../branches/application/current_branch_providers.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../application/attention_summary_service.dart';
import '../domain/attention_summary.dart';
import 'notification_navigation.dart';
import '../domain/app_notification.dart';

final attentionSummaryServiceProvider = Provider<AttentionSummaryService>(
  (ref) => AttentionSummaryService(),
);

final attentionSummaryProvider =
    FutureProvider.family<AttentionSummary, String>((ref, businessId) async {
      final active = ref.watch(activeBusinessProvider).asData?.value;
      final branchId = ref.watch(currentBranchReadScopeProvider);
      final name = active is ActiveBusinessData
          ? active.business.name
          : 'Business';
      return ref
          .watch(attentionSummaryServiceProvider)
          .build(
            businessId: businessId,
            businessName: name,
            branchId: branchId,
          );
    });

class NeedsAttentionSection extends ConsumerWidget {
  const NeedsAttentionSection({required this.businessId, super.key});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(attentionSummaryProvider(businessId));
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (summary) {
        if (!summary.hasAttention) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Needs your attention',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => context.push(AppRoutes.attention),
                  child: const Text('View all'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ...summary.topAttentionItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Material(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _open(context, item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.md,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _icon(item.iconName),
                            color: AppColors.primary,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.priority.toUpperCase(),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.mutedText,
                                ),
                          ),
                          const Icon(Icons.chevron_right, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  IconData _icon(String name) => switch (name) {
    'inventory' => Icons.inventory_2_outlined,
    'person' => Icons.person_outline,
    'local_shipping' => Icons.local_shipping_outlined,
    'fact_check' => Icons.fact_check_outlined,
    _ => Icons.priority_high_outlined,
  };

  Future<void> _open(BuildContext context, AttentionItem item) async {
    final synthetic = AppNotification(
      id: item.id,
      type: AppNotificationType.systemMessage,
      title: item.title,
      message: item.subtitle,
      status: NotificationStatus.unread,
      priority: NotificationPriority.normal,
      category: NotificationCategory.system,
      routeName: item.routeName,
      routeParameters: item.routeParameters,
      entityId: item.routeParameters.values.isNotEmpty
          ? item.routeParameters.values.first
          : null,
    );
    await openNotificationRoute(context, synthetic);
  }
}

class AttentionScreen extends ConsumerWidget {
  const AttentionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    final businessId = active is ActiveBusinessData
        ? active.business.businessId
        : '';
    if (businessId.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final async = ref.watch(attentionSummaryProvider(businessId));
    return Scaffold(
      appBar: AppBar(title: const Text('Needs your attention')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: FilledButton.icon(
            onPressed: () =>
                ref.invalidate(attentionSummaryProvider(businessId)),
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ),
        data: (summary) {
          if (summary.attentionItems.isEmpty) {
            return const Center(child: Text('Nothing needs attention.'));
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(attentionSummaryProvider(businessId));
              await ref.read(attentionSummaryProvider(businessId).future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: summary.attentionItems.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final item = summary.attentionItems[index];
                return Card(
                  child: ListTile(
                    leading: Icon(_attentionIcon(item.iconName)),
                    title: Text(item.title),
                    subtitle: Text(item.subtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openAttentionItem(context, item),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

IconData _attentionIcon(String name) => switch (name) {
  'inventory' => Icons.inventory_2_outlined,
  'person' => Icons.person_outline,
  'local_shipping' => Icons.local_shipping_outlined,
  'fact_check' => Icons.fact_check_outlined,
  'event_busy' => Icons.event_busy_outlined,
  'schedule' => Icons.schedule_outlined,
  _ => Icons.priority_high_outlined,
};

Future<void> _openAttentionItem(
  BuildContext context,
  AttentionItem item,
) async {
  final synthetic = AppNotification(
    id: item.id,
    type: AppNotificationType.systemMessage,
    title: item.title,
    message: item.subtitle,
    status: NotificationStatus.unread,
    priority: NotificationPriority.normal,
    category: NotificationCategory.system,
    routeName: item.routeName,
    routeParameters: item.routeParameters,
  );
  await openNotificationRoute(context, synthetic);
}
