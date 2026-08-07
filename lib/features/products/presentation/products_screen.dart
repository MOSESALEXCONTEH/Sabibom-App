import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../../core/widgets/app_summary_strip.dart';
import '../../../core/widgets/app_tab_page_scaffold.dart';
import '../../../core/widgets/list_bulk_actions.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../team/application/team_providers.dart';
import '../../team/domain/app_permission.dart';
import '../application/products_providers.dart';
import '../domain/product.dart';
import 'widgets/product_list_tile.dart';

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  String _query = '';
  ProductStockFilter _filter = ProductStockFilter.all;
  ProductSort _sort = ProductSort.name;
  String? _category;
  var _selectionMode = false;
  final Set<String> _selected = <String>{};
  List<String> _visibleIds = const [];

  void _clearSelection() => setState(() {
    _selectionMode = false;
    _selected.clear();
  });

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBusinessProvider);
    final hasBusiness = active.asData?.value is ActiveBusinessData;
    final businessId = switch (active.asData?.value) {
      ActiveBusinessData(:final business) => business.businessId,
      _ => null,
    };
    return AppTabPageScaffold(
      title: _selectionMode ? '${_selected.length} selected' : 'Products',
      subtitle: _selectionMode
          ? 'Swipe left or select products to archive'
          : 'Inventory, prices and stock levels',
      trailing: hasBusiness
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: bulkSelectActions(
                selectionMode: _selectionMode,
                selectedCount: _selected.length,
                totalCount: _visibleIds.length,
                onEnter: () => setState(() => _selectionMode = true),
                onExit: _clearSelection,
                onSelectAll: () => setState(() {
                  _selected
                    ..clear()
                    ..addAll(_visibleIds);
                }),
                onDeleteSelected: businessId == null
                    ? null
                    : () => _bulkArchive(businessId),
                deleteTooltip: 'Archive selected',
              ),
            )
          : null,
      floatingActionButton: hasBusiness && !_selectionMode
          ? FloatingActionButton.extended(
              heroTag: 'fab-new-product',
              onPressed: () => context.pushNamed(AppRouteNames.newProduct),
              icon: const Icon(Icons.add),
              label: const Text('Add Product'),
            )
          : null,
      body: active.when(
        loading: () => const AppListSkeleton(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        ),
        error: (_, _) => const AppErrorState(
          title: 'Unable to load products',
          message: 'Something went wrong. Please try again.',
        ),
        data: (state) => switch (state) {
          ActiveBusinessData(:final business) => _ProductsBody(
            businessId: business.businessId,
            currencySymbol: business.currency.symbol,
            query: _query,
            filter: _filter,
            sort: _sort,
            category: _category,
            selectionMode: _selectionMode,
            selectedIds: _selected,
            onQueryChanged: (value) => setState(() => _query = value),
            onFilterChanged: (value) => setState(() => _filter = value),
            onSortChanged: (value) => setState(() => _sort = value),
            onCategoryChanged: (value) => setState(() => _category = value),
            onVisibleIds: (ids) {
              if (!_listEquals(ids, _visibleIds)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _visibleIds = ids);
                });
              }
            },
            onToggleSelected: (id) => setState(() {
              if (_selected.contains(id)) {
                _selected.remove(id);
              } else {
                _selected.add(id);
              }
            }),
            onEnterSelection: (id) => setState(() {
              _selectionMode = true;
              _selected.add(id);
            }),
          ),
          ActiveBusinessNone() => const AppEmptyState(
            title: 'No active business',
            description: 'Set up or select a business to continue.',
            icon: Icons.storefront_outlined,
          ),
          ActiveBusinessFailure(:final message) => AppErrorState(
            title: 'Unable to load products',
            message: message,
          ),
          _ => const AppListSkeleton(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          ),
        },
      ),
    );
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _bulkArchive(String businessId) async {
    if (_selected.isEmpty) return;
    final ok = await confirmListDelete(
      context,
      title: 'Archive ${_selected.length} products?',
      message:
          'Selected products will be archived and hidden from active sales.',
      confirmLabel: 'Archive',
    );
    if (!ok) return;
    final repo = ref.read(productsRepositoryProvider);
    var count = 0;
    for (final id in _selected.toList()) {
      try {
        await repo.setProductStatus(businessId, id, ProductStatus.archived);
        count++;
      } catch (_) {}
    }
    ref.invalidate(productsListProvider(businessId));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Archived $count products.')));
    _clearSelection();
  }
}

class _ProductsBody extends ConsumerWidget {
  const _ProductsBody({
    required this.businessId,
    required this.currencySymbol,
    required this.query,
    required this.filter,
    required this.sort,
    required this.category,
    required this.selectionMode,
    required this.selectedIds,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onSortChanged,
    required this.onCategoryChanged,
    required this.onVisibleIds,
    required this.onToggleSelected,
    required this.onEnterSelection,
  });

  final String businessId;
  final String currencySymbol;
  final String query;
  final ProductStockFilter filter;
  final ProductSort sort;
  final String? category;
  final bool selectionMode;
  final Set<String> selectedIds;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<ProductStockFilter> onFilterChanged;
  final ValueChanged<ProductSort> onSortChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<List<String>> onVisibleIds;
  final ValueChanged<String> onToggleSelected;
  final ValueChanged<String> onEnterSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsListProvider(businessId));
    final canViewProfit =
        ref.watch(
          hasPermissionProvider(AppPermission.viewProductPotentialProfit),
        ) ||
        ref.watch(hasPermissionProvider(AppPermission.viewProductProfit)) ||
        ref.watch(hasPermissionProvider(AppPermission.viewProfit));
    final canViewCost = ref.watch(
      hasPermissionProvider(AppPermission.viewCostPrice),
    );
    final canArchive = ref.watch(
      hasPermissionProvider(AppPermission.archiveProduct),
    );
    final showProfit = canViewProfit && canViewCost;

    return productsAsync.when(
      loading: () => const AppListSkeleton(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      ),
      error: (_, _) => AppErrorState(
        message: 'Could not load products.',
        onRetry: () => ref.invalidate(productsListProvider(businessId)),
      ),
      data: (products) {
        final categories =
            products
                .map((product) => product.categoryName?.trim() ?? '')
                .where((name) => name.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        final filtered = sortProducts(
          products: filterProducts(
            products: products,
            query: query,
            filter: filter,
            category: category,
          ),
          sort: sort,
        );
        onVisibleIds(filtered.map((p) => p.id).toList(growable: false));
        final activeCount = products.where((p) => p.isActive).length;
        final lowStockCount = products.where((p) => p.isLowStock).length;
        final expiringCount = products
            .where(
              (p) =>
                  p.tracksExpiry &&
                  (p.expiryStatus == ProductExpiryStatus.expiringSoon ||
                      p.expiryStatus == ProductExpiryStatus.expiresToday ||
                      p.expiredQuantity > 0),
            )
            .length;

        if (products.isEmpty) {
          return AppEmptyState(
            title: 'No products yet',
            description:
                'Add products or services so you can select them while recording sales.',
            icon: Icons.inventory_2_outlined,
            actionLabel: 'Add Product',
            actionIcon: Icons.add,
            onAction: () => context.pushNamed(AppRouteNames.newProduct),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppSummaryStrip(
                items: <AppSummaryItem>[
                  AppSummaryItem(
                    icon: Icons.inventory_2_outlined,
                    label: '$activeCount products',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  AppSummaryItem(
                    icon: Icons.circle,
                    label: '$lowStockCount low stock',
                    color: Colors.orange,
                  ),
                  AppSummaryItem(
                    icon: Icons.circle,
                    label: '$expiringCount expiry attention',
                    color: Colors.redAccent,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                onChanged: onQueryChanged,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search name, SKU or barcode',
                ),
              ),
              const SizedBox(height: AppSpacing.sm + 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ProductStockFilter.values.map((value) {
                    final selected = filter == value;
                    return Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: ChoiceChip(
                        label: Text(_filterLabel(value)),
                        selected: selected,
                        onSelected: (_) => onFilterChanged(value),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<ProductSort>(
                initialValue: sort,
                decoration: const InputDecoration(labelText: 'Sort by'),
                items: ProductSort.values
                    .map(
                      (value) => DropdownMenuItem<ProductSort>(
                        value: value,
                        child: Text(_sortLabel(value)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onSortChanged(value);
                },
              ),
              if (categories.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String?>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All categories'),
                    ),
                    ...categories.map(
                      (name) => DropdownMenuItem<String?>(
                        value: name,
                        child: Text(name),
                      ),
                    ),
                  ],
                  onChanged: onCategoryChanged,
                ),
              ],
              const SizedBox(height: AppSpacing.sm + 4),
              Expanded(
                child: filtered.isEmpty
                    ? const AppEmptyState(
                        title: 'No matches',
                        description: 'No products match your filters.',
                        icon: Icons.filter_alt_off_outlined,
                      )
                    : RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(productsListProvider(businessId)),
                        child: ListView.separated(
                          padding: const EdgeInsets.only(
                            bottom: AppTabChrome.bottomInset,
                          ),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, index) {
                            final product = filtered[index];
                            final tile = ProductListTile(
                              product: product,
                              currencySymbol: currencySymbol,
                              showProfit: showProfit,
                              onTap: () => context.pushNamed(
                                AppRouteNames.productDetails,
                                pathParameters: <String, String>{
                                  'productId': product.id,
                                },
                              ),
                            );
                            return SelectableDismissibleTile(
                              id: product.id,
                              selectionMode: selectionMode,
                              selected: selectedIds.contains(product.id),
                              onToggleSelected: onToggleSelected,
                              enabled: canArchive && product.isActive,
                              dismissLabel: 'Archive',
                              confirmTitle: 'Archive product?',
                              confirmMessage:
                                  '“${product.name}” will be archived and hidden from active sales.',
                              confirmLabel: 'Archive',
                              onDismissed: (id) async {
                                try {
                                  await ref
                                      .read(productsRepositoryProvider)
                                      .setProductStatus(
                                        businessId,
                                        id,
                                        ProductStatus.archived,
                                      );
                                  ref.invalidate(
                                    productsListProvider(businessId),
                                  );
                                  return true;
                                } catch (_) {
                                  return false;
                                }
                              },
                              child: GestureDetector(
                                onLongPress: canArchive
                                    ? () => onEnterSelection(product.id)
                                    : null,
                                child: tile,
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _filterLabel(ProductStockFilter filter) => switch (filter) {
    ProductStockFilter.all => 'All',
    ProductStockFilter.inStock => 'In Stock',
    ProductStockFilter.lowStock => 'Low Stock',
    ProductStockFilter.outOfStock => 'Out of Stock',
    ProductStockFilter.expiringSoon => 'Expiring Soon',
    ProductStockFilter.expiresToday => 'Expires Today',
    ProductStockFilter.expired => 'Expired',
    ProductStockFilter.expiryUnknown => 'Expiry Unknown',
    ProductStockFilter.noExpiryTracking => 'No Expiry Tracking',
    ProductStockFilter.untracked => 'Untracked',
    ProductStockFilter.archived => 'Archived',
  };

  static String _sortLabel(ProductSort sort) => switch (sort) {
    ProductSort.name => 'Product name',
    ProductSort.nearestExpiry => 'Nearest expiry',
    ProductSort.stockQuantity => 'Stock quantity',
    ProductSort.potentialProfit => 'Potential profit',
    ProductSort.realizedProfit => 'Realized profit',
    ProductSort.stockValue => 'Highest stock value',
    ProductSort.recentlyAdded => 'Recently added',
  };
}
