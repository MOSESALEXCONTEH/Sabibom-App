import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Confirms a swipe or bulk remove/archive/void action.
Future<bool> confirmListDelete(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Remove',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

/// Wraps a list row with swipe-to-delete and optional multi-select checkbox.
class SelectableDismissibleTile extends StatelessWidget {
  const SelectableDismissibleTile({
    required this.id,
    required this.child,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelected,
    required this.onDismissed,
    this.dismissLabel = 'Remove',
    this.confirmTitle = 'Remove item?',
    this.confirmMessage = 'This cannot be undone from the list.',
    this.confirmLabel = 'Remove',
    this.enabled = true,
    super.key,
  });

  final String id;
  final Widget child;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<String> onToggleSelected;
  final Future<bool> Function(String id) onDismissed;
  final String dismissLabel;
  final String confirmTitle;
  final String confirmMessage;
  final String confirmLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final row = selectionMode
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 18, right: AppSpacing.sm),
                child: Checkbox(
                  value: selected,
                  onChanged: enabled
                      ? (_) => onToggleSelected(id)
                      : null,
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: enabled ? () => onToggleSelected(id) : null,
                  onLongPress: enabled ? () => onToggleSelected(id) : null,
                  child: AbsorbPointer(absorbing: true, child: child),
                ),
              ),
            ],
          )
        : child;

    if (selectionMode || !enabled) return row;

    return Dismissible(
      key: ValueKey<String>('dismiss-$id'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        final ok = await confirmListDelete(
          context,
          title: confirmTitle,
          message: confirmMessage,
          confirmLabel: confirmLabel,
        );
        if (!ok) return false;
        return onDismissed(id);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              dismissLabel,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.delete_outline, color: Colors.white),
          ],
        ),
      ),
      child: row,
    );
  }
}

/// App-bar actions for entering/leaving multi-select and running bulk delete.
List<Widget> bulkSelectActions({
  required bool selectionMode,
  required int selectedCount,
  required int totalCount,
  required VoidCallback onEnter,
  required VoidCallback onExit,
  required VoidCallback onSelectAll,
  required VoidCallback? onDeleteSelected,
  String deleteTooltip = 'Remove selected',
}) {
  if (!selectionMode) {
    return [
      IconButton(
        tooltip: 'Select items',
        onPressed: onEnter,
        icon: const Icon(Icons.checklist_outlined),
      ),
    ];
  }
  return [
    if (selectedCount < totalCount)
      IconButton(
        tooltip: 'Select all',
        onPressed: onSelectAll,
        icon: const Icon(Icons.select_all),
      ),
    IconButton(
      tooltip: deleteTooltip,
      onPressed: selectedCount == 0 ? null : onDeleteSelected,
      icon: const Icon(Icons.delete_outline),
    ),
    IconButton(
      tooltip: 'Cancel',
      onPressed: onExit,
      icon: const Icon(Icons.close),
    ),
  ];
}
