import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_motion.dart';
import '../../team/application/team_providers.dart';
import '../../team/domain/app_permission.dart';
import '../../team/domain/business_membership.dart';
import '../application/current_branch_providers.dart';
import '../domain/business_branch.dart';

class BranchSelector extends ConsumerWidget {
  const BranchSelector({
    super.key,
    this.compact = false,
    this.transparent = false,
    this.onManageBranches,
  });

  final bool compact;
  final bool transparent;
  final VoidCallback? onManageBranches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectionAsync = ref.watch(currentBranchProvider);
    final membership = ref
        .watch(currentBusinessMembershipProvider)
        .asData
        ?.value;
    return selectionAsync.when(
      loading: () => compact
          ? const SizedBox(width: 140, height: 36)
          : _BranchBadge.loading(compact: compact, transparent: transparent),
      error: (_, _) =>
          _BranchBadge.error(compact: compact, transparent: transparent),
      data: (selection) {
        if (selection == null) {
          return Semantics(
            label: 'No branch assigned',
            child: Text(
              'No branch assigned',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          );
        }
        return _BranchBadge(
          selection: selection,
          membership: membership,
          onSelect: (branch) => ref
              .read(currentBranchProvider.notifier)
              .selectBranch(branch.branchId),
          onSelectAllBranches: () =>
              ref.read(currentBranchProvider.notifier).selectAllBranches(),
          onManageBranches: onManageBranches,
          compact: compact,
          transparent: transparent,
        );
      },
    );
  }
}

class _BranchBadge extends StatelessWidget {
  const _BranchBadge({
    required this.selection,
    required this.onSelect,
    required this.onSelectAllBranches,
    required this.compact,
    required this.transparent,
    this.onManageBranches,
    this.membership,
  });

  const _BranchBadge.loading({required this.compact, required this.transparent})
    : selection = null,
      membership = null,
      onSelect = null,
      onSelectAllBranches = null,
      onManageBranches = null;

  const _BranchBadge.error({required this.compact, required this.transparent})
    : selection = null,
      membership = null,
      onSelect = null,
      onSelectAllBranches = null,
      onManageBranches = null;

  final BranchSelection? selection;
  final BusinessMembership? membership;
  final Future<bool> Function(BusinessBranch branch)? onSelect;
  final VoidCallback? onSelectAllBranches;
  final VoidCallback? onManageBranches;
  final bool compact;
  final bool transparent;

  @override
  Widget build(BuildContext context) {
    final activeSelection = selection;
    if (activeSelection == null) {
      return compact
          ? const SizedBox(width: 120, height: 36)
          : const SizedBox.shrink();
    }
    final current = activeSelection.selectedBranch;
    final isAll = activeSelection.isAllBranchesMode;

    final canSwitch = activeSelection.canSwitchBranch;
    final canManage =
        membership?.hasPermission(AppPermission.manageBranches) == true;
    final branchLabel = isAll ? 'All Branches' : current.name;
    final branchCodeLabel = isAll
        ? 'Consolidated read-only view'
        : current.code;
    final statusLabel = isAll ? 'consolidated' : current.status.name;
    final child = Container(
      padding: EdgeInsets.symmetric(
        horizontal: transparent ? 8 : (compact ? 10 : 12),
        vertical: transparent ? 6 : (compact ? 8 : 10),
      ),
      decoration: BoxDecoration(
        color: transparent
            ? Colors.transparent
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: transparent
              ? Colors.white.withValues(alpha: 0.28)
              : Theme.of(context).dividerColor,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined, size: compact ? 16 : 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        branchLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (!transparent && !isAll && current.isMainBranch) ...[
                      const SizedBox(width: 6),
                      _MiniBadge(label: 'Main'),
                    ],
                    if (!transparent && isAll) ...[
                      const SizedBox(width: 6),
                      _MiniBadge(label: 'Read-only'),
                    ],
                  ],
                ),
                if (!transparent) ...[
                  const SizedBox(height: 2),
                  Text(
                    branchCodeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!transparent) ...[
            const SizedBox(width: 8),
            _MiniBadge(
              label: statusLabel,
              color: isAll
                  ? Colors.blueGrey
                  : (current.isActive ? Colors.green : Colors.orange),
            ),
          ],
          if (canSwitch ||
              activeSelection.canUseAllBranches ||
              (canManage && onManageBranches != null)) ...[
            if (!transparent) const SizedBox(width: 4),
            IconButton(
              tooltip: 'Switch branch',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              onPressed: onSelect == null
                  ? null
                  : () => _showBranchPicker(
                      context,
                      activeSelection,
                      onSelect!,
                      onSelectAllBranches,
                      canManage ? onManageBranches : null,
                    ),
              icon: const Icon(Icons.more_vert, size: 18),
            ),
          ],
        ],
      ),
    );

    final animated = AnimatedSwitcher(
      duration: AppMotion.resolve(context, AppMotion.standard),
      switchInCurve: AppMotion.entranceCurve,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey<String>(isAll ? 'all' : current.branchId),
        child: child,
      ),
    );
    if (compact) return animated;
    return Material(color: Colors.transparent, child: animated);
  }

  Future<void> _showBranchPicker(
    BuildContext context,
    BranchSelection selection,
    Future<bool> Function(BusinessBranch branch) onSelect,
    VoidCallback? onSelectAllBranches,
    VoidCallback? onManageBranches,
  ) async {
    final chosen = await showModalBottomSheet<_BranchChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title: Text('Switch branch'),
            subtitle: Text('Choose where new records should be created.'),
          ),
          if (selection.canUseAllBranches)
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text('All Branches'),
              subtitle: const Text('Consolidated read-only view.'),
              trailing: selection.isAllBranchesMode
                  ? const Icon(Icons.check, size: 18)
                  : null,
              onTap: () =>
                  Navigator.of(context).pop(const _BranchChoice.allBranches()),
            ),
          for (final branch in selection.branches)
            ListTile(
              leading: Icon(
                branch.isMainBranch ? Icons.star : Icons.storefront_outlined,
              ),
              title: Text(branch.name),
              subtitle: Text(branch.code),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (branch.isMainBranch) const Text('Main'),
                  if (!branch.isSelectable)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Text('Inactive'),
                    ),
                  if (!selection.isAllBranchesMode &&
                      selection.selectedBranch.branchId == branch.branchId)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.check, size: 18),
                    ),
                ],
              ),
              enabled: branch.isSelectable,
              onTap: branch.isSelectable
                  ? () => Navigator.of(
                      context,
                    ).pop(_BranchChoice.singleBranch(branch))
                  : null,
            ),
          if (onManageBranches != null)
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Manage Branches'),
              onTap: () => Navigator.of(
                context,
              ).pop(const _BranchChoice.manageBranches()),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    if (chosen.mode == _BranchChoiceMode.single && chosen.branch != null) {
      final switched = await onSelect(chosen.branch!);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            switched
                ? 'Switched to ${chosen.branch!.name}.'
                : 'You do not have access to that branch.',
          ),
        ),
      );
      return;
    }
    if (chosen.mode == _BranchChoiceMode.all && onSelectAllBranches != null) {
      onSelectAllBranches();
      return;
    }
    if (chosen.mode == _BranchChoiceMode.manage && onManageBranches != null) {
      onManageBranches();
    }
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: (color ?? Theme.of(context).colorScheme.primary).withValues(
        alpha: 0.12,
      ),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: color ?? Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

enum _BranchChoiceMode { single, all, manage }

class _BranchChoice {
  const _BranchChoice._(this.mode, this.branch);

  const _BranchChoice.singleBranch(BusinessBranch branch)
    : this._(_BranchChoiceMode.single, branch);

  const _BranchChoice.allBranches() : this._(_BranchChoiceMode.all, null);

  const _BranchChoice.manageBranches() : this._(_BranchChoiceMode.manage, null);

  final _BranchChoiceMode mode;
  final BusinessBranch? branch;
}
