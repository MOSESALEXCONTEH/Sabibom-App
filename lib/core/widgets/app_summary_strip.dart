import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

class AppSummaryStrip extends StatelessWidget {
  const AppSummaryStrip({required this.items, super.key});

  final List<AppSummaryItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: items
          .map(
            (item) => Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(item.icon, size: 17, color: item.color),
                const SizedBox(width: AppSpacing.xs),
                Text(item.label, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          )
          .toList(growable: false),
    );
  }
}

class AppSummaryItem {
  const AppSummaryItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;
}
