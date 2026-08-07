import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/formatting/currency_formatter.dart';
import '../../../core/sync/record_sync_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../branches/application/current_branch_providers.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../inventory/application/inventory_providers.dart';
import '../../inventory/domain/branch_inventory.dart';
import '../../inventory/domain/inventory_batch.dart';
import '../../sales/domain/sale_models.dart';
import '../../team/application/team_providers.dart';
import '../../team/domain/app_permission.dart';
import '../application/products_providers.dart';
import '../data/products_repository.dart';
import '../domain/product.dart';
import 'widgets/product_expiry_line.dart';
import 'widgets/stock_status_badge.dart';

class ProductDetailsScreen extends ConsumerWidget {
  const ProductDetailsScreen({required this.productId, super.key});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trimmed = productId.trim();
    if (trimmed.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Product Details')),
        body: const Center(child: Text('This product could not be found.')),
      );
    }

    final active = ref.watch(activeBusinessProvider);
    return active.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('Product Details')),
        body: const Center(
          child: Text('Something went wrong. Please try again.'),
        ),
      ),
      data: (state) => switch (state) {
        ActiveBusinessData(:final business) => _ProductDetailsBody(
          businessId: business.businessId,
          productId: trimmed,
          currencySymbol: business.currency.symbol,
        ),
        _ => Scaffold(
          appBar: AppBar(title: const Text('Product Details')),
          body: const Center(
            child: Text('Set up or select a business to continue.'),
          ),
        ),
      },
    );
  }
}

class _ProductDetailsBody extends ConsumerWidget {
  const _ProductDetailsBody({
    required this.businessId,
    required this.productId,
    required this.currencySymbol,
  });

  final String businessId;
  final String productId;
  final String currencySymbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(productDetailProvider((businessId, productId)));
    final movements = ref.watch(
      productMovementsProvider((businessId, productId)),
    );
    final batches = ref.watch(
      productInventoryBatchesProvider((businessId, productId)),
    );
    final branchSelection = ref.watch(currentBranchProvider).asData?.value;
    final branchBreakdown = branchSelection?.isAllBranchesMode == true
        ? ref.watch(
            productBranchInventoryBreakdownProvider((businessId, productId)),
          )
        : null;
    final canViewCost = ref.watch(
      hasPermissionProvider(AppPermission.viewCostPrice),
    );
    final canViewProfit =
        ref.watch(hasPermissionProvider(AppPermission.viewProductProfit)) ||
        ref.watch(hasPermissionProvider(AppPermission.viewProfit));
    final canViewPotential =
        ref.watch(
          hasPermissionProvider(AppPermission.viewProductPotentialProfit),
        ) ||
        canViewProfit;
    final canViewExpiry = ref.watch(
      hasPermissionProvider(AppPermission.viewProductExpiry),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        actions: <Widget>[
          RecordSyncStatusIcon(
            request: RecordSyncRequest(
              businessId: businessId,
              collection: 'products',
              recordId: productId,
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: () => context.pushNamed(
              AppRouteNames.editProduct,
              pathParameters: <String, String>{'productId': productId},
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: FilledButton.tonal(
            onPressed: () =>
                ref.invalidate(productDetailProvider((businessId, productId))),
            child: const Text('Retry'),
          ),
        ),
        data: (product) {
          if (product == null) {
            return const Center(
              child: Text(
                'This record could not be found. It may have been removed or archived.',
              ),
            );
          }
          final canArchive = ref.watch(
            hasPermissionProvider(AppPermission.archiveProduct),
          );
          final canManage = ref.watch(
            hasPermissionProvider(AppPermission.manageProducts),
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: <Widget>[
              Text(
                product.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              StockStatusBadge(product: product),
              if (canViewExpiry && product.tracksExpiry) ...<Widget>[
                const SizedBox(height: 8),
                ProductExpiryLine(product: product),
              ],
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: <Widget>[
                      _row(
                        'Selling price',
                        formatCurrency(
                          minorToMoney(product.sellingPriceMinor),
                          symbol: currencySymbol,
                        ),
                      ),
                      if (canViewCost)
                        _row(
                          'Cost',
                          formatCurrency(
                            minorToMoney(product.costPriceMinor),
                            symbol: currencySymbol,
                          ),
                        ),
                      if (canViewPotential && canViewCost)
                        _row(
                          'Profit per unit',
                          formatCurrency(
                            minorToMoney(product.profitEstimateMinor),
                            symbol: currencySymbol,
                          ),
                        ),
                      _row(
                        'SKU',
                        product.sku?.isNotEmpty == true ? product.sku! : '—',
                      ),
                      _row(
                        'Barcode',
                        product.barcode?.isNotEmpty == true
                            ? product.barcode!
                            : '—',
                      ),
                      _row(
                        'Category',
                        product.categoryName?.isNotEmpty == true
                            ? product.categoryName!
                            : '—',
                      ),
                      _row(
                        'Stock',
                        product.trackStock
                            ? '${product.quantity} ${product.unit}'
                            : 'Not tracked',
                      ),
                      _row(
                        'Low-stock threshold',
                        product.trackStock
                            ? '${product.lowStockThreshold}'
                            : '—',
                      ),
                      _row('Unit', product.unit),
                      _row('Status', product.isActive ? 'Active' : 'Archived'),
                      if (product.description?.isNotEmpty == true)
                        _row('Description', product.description!),
                      _row(
                        'Created',
                        product.createdAt == null
                            ? '—'
                            : DateFormat.yMMMd().add_jm().format(
                                product.createdAt!,
                              ),
                      ),
                      _row(
                        'Updated',
                        product.updatedAt == null
                            ? '—'
                            : DateFormat.yMMMd().add_jm().format(
                                product.updatedAt!,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              if (branchBreakdown != null) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  'Stock by branch',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                branchBreakdown.when(
                  loading: () => const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  error: (_, _) => const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Could not load branch stock breakdown.'),
                    ),
                  ),
                  data: (rows) => _BranchInventoryBreakdownCard(
                    rows: rows,
                    branchNames: <String, String>{
                      for (final branch in branchSelection!.branches)
                        branch.branchId: '${branch.name} (${branch.code})',
                    },
                    unit: product.unit,
                  ),
                ),
              ],
              if (canViewExpiry) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  'Expiry',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: <Widget>[
                        _row(
                          'Tracking',
                          product.tracksExpiry ? 'Enabled' : 'Not tracked',
                        ),
                        if (product.tracksExpiry) ...<Widget>[
                          _row(
                            'Status',
                            product.expiryStatus.storedValue.replaceAll(
                              '_',
                              ' ',
                            ),
                          ),
                          _row(
                            'Nearest expiry',
                            product.nextExpiryDate == null
                                ? (product.unknownExpiryQuantity > 0
                                      ? 'Unknown'
                                      : '—')
                                : DateFormat.yMMMd().format(
                                    product.nextExpiryDate!,
                                  ),
                          ),
                          _row(
                            'Expiring soon qty',
                            '${product.expiringQuantity}',
                          ),
                          _row('Expired qty', '${product.expiredQuantity}'),
                          _row(
                            'Unknown expiry qty',
                            '${product.unknownExpiryQuantity}',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (product.tracksExpiry) ...<Widget>[
                  const SizedBox(height: 8),
                  batches.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) =>
                        const Text('Could not load inventory batches.'),
                    data: (items) {
                      final active = items
                          .where(
                            (batch) =>
                                batch.quantityRemaining > 0 &&
                                batch.status != InventoryBatchStatus.voided &&
                                batch.status != InventoryBatchStatus.depleted,
                          )
                          .toList();
                      if (active.isEmpty) {
                        return const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No active stock batches.'),
                          ),
                        );
                      }
                      return Card(
                        child: Column(
                          children: active
                              .map(
                                (batch) => ListTile(
                                  title: Text(
                                    batch.expiryDateKnown &&
                                            batch.expiryDate != null
                                        ? 'Expires ${DateFormat.yMMMd().format(batch.expiryDate!)}'
                                        : 'Expiry date unknown',
                                  ),
                                  subtitle: Text(
                                    '${batch.quantityRemaining}/${batch.quantityReceived} ${product.unit}'
                                    '${canViewCost ? ' · Cost ${formatCurrency(minorToMoney(batch.unitCostMinor), symbol: currencySymbol)}' : ''}'
                                    '${batch.sourceNumber != null ? ' · ${batch.sourceNumber}' : ''}',
                                  ),
                                  trailing: Text(batch.status.name),
                                ),
                              )
                              .toList(),
                        ),
                      );
                    },
                  ),
                ],
              ],
              if ((canViewProfit || canViewPotential) &&
                  canViewCost) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  'Product profit',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: <Widget>[
                        if (canViewPotential) ...<Widget>[
                          _row(
                            'Current stock cost',
                            formatCurrency(
                              minorToMoney(product.stockCostValueMinor),
                              symbol: currencySymbol,
                            ),
                          ),
                          _row(
                            'Expected revenue',
                            formatCurrency(
                              minorToMoney(product.expectedStockRevenueMinor),
                              symbol: currencySymbol,
                            ),
                          ),
                          _row(
                            product.potentialProfitRemainingMinor < 0
                                ? 'Estimated potential loss'
                                : 'Estimated profit remaining',
                            formatCurrency(
                              minorToMoney(
                                product.potentialProfitRemainingMinor,
                              ),
                              symbol: currencySymbol,
                            ),
                          ),
                        ],
                        if (canViewProfit) ...<Widget>[
                          _row(
                            'Profit already made',
                            formatCurrency(
                              minorToMoney(product.realizedGrossProfitMinor),
                              symbol: currencySymbol,
                            ),
                          ),
                          _row(
                            'Total projected gross profit',
                            formatCurrency(
                              minorToMoney(
                                product.totalProjectedGrossProfitMinor,
                              ),
                              symbol: currencySymbol,
                            ),
                          ),
                          if (product.profitIsEstimated)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Some older sales do not contain enough cost information for an exact profit calculation.',
                              ),
                            ),
                        ],
                        const SizedBox(height: 6),
                        const Text(
                          'Remaining profit is a current stock estimate, not guaranteed.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.pushNamed(
                  AppRouteNames.editProduct,
                  pathParameters: <String, String>{'productId': productId},
                ),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit Product'),
              ),
              const SizedBox(height: 8),
              if (product.trackStock)
                OutlinedButton.icon(
                  onPressed: () => context.pushNamed(
                    AppRouteNames.adjustStock,
                    pathParameters: <String, String>{'productId': productId},
                  ),
                  icon: const Icon(Icons.tune),
                  label: const Text('Adjust Stock'),
                ),
              const SizedBox(height: 8),
              if (canArchive)
                TextButton.icon(
                  onPressed: () => _toggleArchive(context, ref, product),
                  icon: Icon(
                    product.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                  label: Text(
                    product.isArchived ? 'Restore Product' : 'Archive Product',
                  ),
                ),
              if (canManage && product.isArchived) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                  ),
                  onPressed: () => _deleteProduct(context, ref, product),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete Product Permanently'),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Recent inventory movements',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              movements.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) =>
                    const Text('Could not load inventory history.'),
                data: (items) {
                  if (items.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No inventory movements yet.'),
                      ),
                    );
                  }
                  return Card(
                    child: Column(
                      children: items
                          .map(
                            (item) => ListTile(
                              title: Text(item.type.label),
                              subtitle: Text(
                                item.createdAt == null
                                    ? 'Stock ${item.stockBefore} → ${item.stockAfter}'
                                    : '${DateFormat.MMMd().add_jm().format(item.createdAt!)} · ${item.stockBefore} → ${item.stockAfter}',
                              ),
                              trailing: Text(
                                item.quantityChange > 0
                                    ? '+${item.quantityChange}'
                                    : '${item.quantityChange}',
                                style: TextStyle(
                                  color: item.quantityChange >= 0
                                      ? AppColors.secondary
                                      : Colors.red,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _toggleArchive(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) async {
    try {
      await ref
          .read(productsRepositoryProvider)
          .setProductStatus(
            businessId,
            product.id,
            product.isArchived ? ProductStatus.active : ProductStatus.archived,
          );
      ref.invalidate(productDetailProvider((businessId, productId)));
      ref.invalidate(productsListProvider(businessId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              product.isArchived ? 'Product restored.' : 'Product archived.',
            ),
          ),
        );
      }
    } on ProductException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.friendlyMessage)));
      }
    }
  }

  Future<void> _deleteProduct(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text(
          product.trackStock && product.quantity > 0
              ? 'Stock must be zero before permanent delete. Adjust stock first, or keep the product archived.'
              : '“${product.name}” will be permanently removed. Sales history stays in reports, but this product will no longer appear in your catalog.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: product.trackStock && product.quantity > 0
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final branchId = ref.read(currentWritableBranchIdProvider);
    if (branchId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(branchWriteBlockedMessage)),
        );
      }
      return;
    }
    try {
      await ref
          .read(productsRepositoryProvider)
          .deleteArchivedProduct(businessId, product.id, branchId: branchId);
      ref.invalidate(productsListProvider(businessId));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Product deleted.')));
        context.pop();
      }
    } on ProductException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.friendlyMessage)));
      }
    }
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.mutedText),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _BranchInventoryBreakdownCard extends StatelessWidget {
  const _BranchInventoryBreakdownCard({
    required this.rows,
    required this.branchNames,
    required this.unit,
  });

  final List<BranchInventory> rows;
  final Map<String, String> branchNames;
  final String unit;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No branch inventory records yet.'),
        ),
      );
    }
    return Card(
      child: Column(
        children: rows
            .map((row) {
              final branchName = branchNames[row.branchId] ?? row.branchId;
              return ListTile(
                title: Text(branchName),
                trailing: Text(
                  '${row.availableQuantity} $unit',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}
