import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class SabiPromptChip extends StatelessWidget {
  const SabiPromptChip({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  IconData get _icon {
    final value = label.toLowerCase();
    if (value.contains('customer') || value.contains('owe')) {
      return Icons.people_alt_outlined;
    }
    if (value.contains('sell') || value.contains('receipt')) {
      return Icons.trending_up;
    }
    if (value.contains('product') || value.contains('stock')) {
      return Icons.inventory_2_outlined;
    }
    if (value.contains('spend') || value.contains('supplier')) {
      return Icons.account_balance_wallet_outlined;
    }
    return Icons.auto_awesome_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: context.brandTint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: context.brandTintBorder),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: <Widget>[
                Icon(_icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: context.textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: context.mutedTextColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
