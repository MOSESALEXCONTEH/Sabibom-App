import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../sabi/presentation/sabi_navigation.dart';
import '../application/setup_providers.dart';
import '../domain/setup_checklist.dart';

class SetupChecklistCard extends ConsumerStatefulWidget {
  const SetupChecklistCard({super.key});

  @override
  ConsumerState<SetupChecklistCard> createState() => _SetupChecklistCardState();
}

class _SetupChecklistCardState extends ConsumerState<SetupChecklistCard> {
  var _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(setupChecklistProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (progress) {
        if (!progress.shouldShow) return const SizedBox.shrink();
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Complete your SabiBom setup',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: _collapsed ? 'Expand' : 'Collapse',
                      onPressed: () => setState(() => _collapsed = !_collapsed),
                      icon: Icon(
                        _collapsed
                            ? Icons.expand_more
                            : Icons.expand_less,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Dismiss checklist',
                      onPressed: () async {
                        await ref.read(setupChecklistServiceProvider).dismiss();
                        ref.invalidate(setupChecklistProvider);
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  '${progress.completedCount} of ${progress.totalCount} complete',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.mutedText,
                      ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress.totalCount == 0
                      ? 0
                      : progress.completedCount / progress.totalCount,
                ),
                if (!_collapsed) ...[
                  const SizedBox(height: AppSpacing.md),
                  ...progress.steps.map((step) => _StepTile(step: step)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StepTile extends ConsumerWidget {
  const _StepTile({required this.step});
  final SetupChecklistStep step;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        step.isComplete ? Icons.check_circle : Icons.radio_button_unchecked,
        color: step.isComplete
            ? Theme.of(context).colorScheme.primary
            : AppColors.mutedText,
      ),
      title: Text(
        step.title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          decoration: step.isComplete ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(step.description),
      trailing: step.isComplete
          ? null
          : const Icon(Icons.chevron_right, size: 20),
      onTap: step.isComplete
          ? null
          : () async {
              if (step.id == SetupStepId.trySabi) {
                await ref.read(setupChecklistServiceProvider).markTriedSabi();
                ref.invalidate(setupChecklistProvider);
                if (context.mounted) showSabiAssistantSheet(context);
                return;
              }
              _open(context, step.routeName);
            },
    );
  }

  void _open(BuildContext context, String routeName) {
    try {
      context.pushNamed(routeName);
    } catch (_) {
      switch (routeName) {
        case 'newProduct':
          context.pushNamed(AppRouteNames.newProduct);
        case 'newCustomer':
          context.pushNamed(AppRouteNames.newCustomer);
        case 'newSale':
          context.pushNamed(AppRouteNames.newSale);
        case 'settingsReceipt':
          context.pushNamed(AppRouteNames.settingsReceipt);
        case 'settingsNotifications':
          context.pushNamed(AppRouteNames.settingsNotifications);
        case 'settingsBusiness':
          context.push(AppRoutes.businessProfile);
        case 'reports':
          context.pushNamed(AppRouteNames.reports);
        case 'backup':
          context.pushNamed(AppRouteNames.backup);
        default:
          context.go(AppRoutes.home);
      }
    }
  }
}
