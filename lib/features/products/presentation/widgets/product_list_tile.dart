import 'package:flutter/material.dart';

import '../../../../core/formatting/currency_formatter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../sales/domain/sale_models.dart';
import '../../domain/product.dart';
import 'stock_status_badge.dart';

class ProductListTile extends StatelessWidget {
  const ProductListTile({
    required this.product,
    required this.currencySymbol,
    required this.onTap,
    this.showProfit = false,
    this.inventoryEnabled = true,
    super.key,
  });

  final Product product;
  final String currencySymbol;
  final VoidCallback onTap;
  final bool showProfit;
  final bool inventoryEnabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final imageUrl = product.imageUrl?.trim();
    final stockLabel = inventoryEnabled
        ? (product.trackStock
              ? '${_qty(product.quantity)} ${product.unit}'
              : 'Untracked')
        : product.unit;
    final priceLabel = formatCurrency(
      minorToMoney(product.sellingPriceMinor),
      symbol: currencySymbol,
    );
    final profitLabel = formatCurrency(
      minorToMoney(product.profitEstimateMinor),
      symbol: currencySymbol,
    );
    final metadata = <String>[
      if (product.categoryName?.trim().isNotEmpty == true)
        product.categoryName!.trim(),
      if (product.sku?.trim().isNotEmpty == true) product.sku!.trim(),
    ].join(' | ');

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              _ProductImage(product: product, imageUrl: imageUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      metadata.isEmpty ? product.unit : metadata,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 7),
                    if (inventoryEnabled)
                      StockStatusBadge(product: product)
                    else
                      Text(
                        product.isArchived ? 'Archived' : 'Available',
                        style: TextStyle(
                          color: product.isArchived
                              ? scheme.onSurfaceVariant
                              : AppColors.secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      priceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stockLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (showProfit) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        '+$profitLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _qty(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.product, required this.imageUrl});

  final Product product;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final fallbackIcon = product.isArchived
        ? Icons.archive_outlined
        : Icons.inventory_2_outlined;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return AppNetworkImage(
        url: imageUrl!,
        cid: product.imageCid,
        width: 58,
        height: 58,
        borderRadius: BorderRadius.circular(8),
        fallbackIcon: fallbackIcon,
      );
    }
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(fallbackIcon, color: Theme.of(context).colorScheme.primary),
    );
  }
}
