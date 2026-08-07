import 'package:flutter/material.dart';

import '../../../../core/widgets/app_status_views.dart';

/// Thin wrapper kept for any remaining call sites; prefer [AppEmptyState]
/// directly in new code.
class ProductsEmptyState extends StatelessWidget {
  const ProductsEmptyState({required this.onAdd, super.key});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      title: 'No products yet',
      description:
          'Add products or services so you can select them while recording sales.',
      icon: Icons.inventory_2_outlined,
      actionLabel: 'Add Product',
      actionIcon: Icons.add,
      onAction: onAdd,
    );
  }
}
