import 'package:flutter/material.dart';

import '../formatting/record_date_filter.dart';
import '../theme/app_spacing.dart';

class RecordDateFilterBar extends StatelessWidget {
  const RecordDateFilterBar({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final RecordDatePeriod selected;
  final ValueChanged<RecordDatePeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: RecordDatePeriod.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final period = RecordDatePeriod.values[index];
          return ChoiceChip(
            label: Text(period.label),
            selected: selected == period,
            onSelected: (_) => onSelected(period),
          );
        },
      ),
    );
  }
}
