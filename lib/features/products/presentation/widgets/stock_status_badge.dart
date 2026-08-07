import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/product.dart';

class StockStatusBadge extends StatelessWidget {
  const StockStatusBadge({required this.product, super.key});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, background, foreground) = switch (product) {
      _ when product.isArchived => (
        'Archived',
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      _ when !product.trackStock => (
        'Untracked',
        context.brandTint,
        scheme.primary,
      ),
      _ when product.isOutOfStock => (
        'Out of stock',
        context.dangerTint,
        scheme.error,
      ),
      _ when product.isLowStock => (
        'Low stock',
        context.warningTint,
        context.isDarkTheme ? const Color(0xFFFBBF24) : const Color(0xFF92400E),
      ),
      _ => (
        'In stock',
        context.successTint,
        context.isDarkTheme ? const Color(0xFF6CE9A6) : const Color(0xFF027A48),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
