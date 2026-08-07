import 'package:flutter/material.dart';

import '../../../../core/formatting/currency_formatter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_list_primitives.dart';
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
    super.key,
  });

  final Product product;
  final String currencySymbol;
  final VoidCallback onTap;
  final bool showProfit;

  @override
  Widget build(BuildContext context) {
    final imageUrl = product.imageUrl?.trim();
    final stockLabel = product.trackStock
        ? '${_qty(product.quantity)} ${product.unit}'
        : 'Untracked';
    final priceLabel = formatCurrency(
      minorToMoney(product.sellingPriceMinor),
      symbol: currencySymbol,
    );
    final profitLabel = showProfit
        ? ' · Profit ${formatCurrency(minorToMoney(product.profitEstimateMinor), symbol: currencySymbol)}'
        : '';

    return AppListRow(
      onTap: onTap,
      isThreeLine: true,
      leading: imageUrl != null && imageUrl.isNotEmpty
          ? AppNetworkImage(
              url: imageUrl,
              width: 40,
              height: 40,
              borderRadius: BorderRadius.circular(20),
              fallbackIcon: product.isArchived
                  ? Icons.archive_outlined
                  : Icons.inventory_2_outlined,
            )
          : AppListAvatar(
              icon: product.isArchived
                  ? Icons.archive_outlined
                  : Icons.inventory_2_outlined,
            ),
      title: product.name,
      subtitle: '$priceLabel · $stockLabel$profitLabel',
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          StockStatusBadge(product: product),
          if (product.isLowStock)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Low stock',
                style: TextStyle(color: AppColors.warning, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  static String _qty(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }
}
