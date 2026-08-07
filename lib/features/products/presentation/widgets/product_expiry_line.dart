import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/product.dart';

class ProductExpiryLine extends StatelessWidget {
  const ProductExpiryLine({required this.product, super.key});

  final Product product;

  @override
  Widget build(BuildContext context) {
    if (!product.tracksExpiry) return const SizedBox.shrink();
    final text = _label(product);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: _color(product.expiryStatus),
      ),
    );
  }

  static String _label(Product product) {
    if (product.unknownExpiryQuantity > 0 && product.nextExpiryDate == null) {
      return 'Expiry date unknown';
    }
    final date = product.nextExpiryDate;
    if (date == null) {
      return product.unknownExpiryQuantity > 0
          ? 'Expiry date unknown'
          : 'Expiry tracked';
    }
    final formatted = DateFormat('d MMM yyyy').format(date);
    final qty = product.nextExpiryBatchQuantity;
    final qtyLabel = qty == qty.roundToDouble()
        ? qty.toInt().toString()
        : qty.toStringAsFixed(2);
    return switch (product.expiryStatus) {
      ProductExpiryStatus.expiresToday =>
        'Expires today · $qtyLabel ${product.unit}',
      ProductExpiryStatus.expired => 'Expired $formatted',
      ProductExpiryStatus.expiringSoon ||
      ProductExpiryStatus.safe ||
      ProductExpiryStatus.mixed => 'Expires $formatted · $qtyLabel ${product.unit}',
      ProductExpiryStatus.notTracked => '',
    };
  }

  static Color _color(ProductExpiryStatus status) => switch (status) {
    ProductExpiryStatus.expired ||
    ProductExpiryStatus.expiresToday => Colors.red.shade700,
    ProductExpiryStatus.expiringSoon ||
    ProductExpiryStatus.mixed => AppColors.warning,
    ProductExpiryStatus.safe => AppColors.secondary,
    ProductExpiryStatus.notTracked => AppColors.mutedText,
  };
}
