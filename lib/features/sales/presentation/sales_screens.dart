import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/formatting/currency_formatter.dart';
import '../../../core/formatting/record_date_filter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_list_primitives.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../../core/widgets/app_tab_page_scaffold.dart';
import '../../../core/widgets/barcode_scanner_screen.dart';
import '../../../core/widgets/list_bulk_actions.dart';
import '../../../core/widgets/record_date_filter_bar.dart';
import '../../branches/application/current_branch_providers.dart';
import '../../branches/application/branch_query_error.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../business_setup/application/business_experience_providers.dart';
import '../application/sale_cart_controller.dart';
import '../application/sales_providers.dart' as sales;
import '../data/firestore_sales_repository.dart';
import '../data/sales_repository.dart';
import '../domain/quantity_input.dart';
import '../domain/sale_models.dart';
import 'sales_navigation.dart';
import 'widgets/sale_receipt_preview.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  var _selectionMode = false;
  RecordDatePeriod _datePeriod = RecordDatePeriod.all;
  final Set<String> _selected = <String>{};
  List<String> _visibleIds = const [];

  void _clearSelection() => setState(() {
    _selectionMode = false;
    _selected.clear();
  });

  @override
  Widget build(BuildContext context) {
    final activeBusiness = ref.watch(activeBusinessProvider);
    final terminology = ref.watch(currentBusinessTerminologyProvider);
    final hasBusiness = activeBusiness.asData?.value is ActiveBusinessData;
    final businessId = switch (activeBusiness.asData?.value) {
      ActiveBusinessData(:final business) => business.businessId,
      _ => null,
    };
    return AppTabPageScaffold(
      title: _selectionMode
          ? '${_selected.length} selected'
          : terminology.sales,
      subtitle: _selectionMode
          ? 'Swipe left or select transactions to void'
          : 'Recent transactions and receipts',
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
                    : () => _bulkVoid(businessId),
                deleteTooltip: 'Void selected',
              ),
            )
          : null,
      floatingActionButton: hasBusiness && !_selectionMode
          ? FloatingActionButton.extended(
              heroTag: 'fab-new-sale',
              onPressed: () => context.push(AppRoutes.newSale),
              icon: const Icon(Icons.add),
              label: Text('New ${terminology.sale}'),
            )
          : null,
      body: activeBusiness.when(
        loading: () => const AppListSkeleton(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        ),
        error: (_, _) => AppEmptyState(
          title: 'Set up your business first',
          description:
              'Create your business profile before recording sales and printing receipts.',
          icon: Icons.storefront_outlined,
          actionLabel: 'Set Up Business',
          onAction: () => context.push(AppRoutes.businessSetup),
        ),
        data: (state) => switch (state) {
          ActiveBusinessData(:final business) => _SalesHistory(
            businessId: business.businessId,
            datePeriod: _datePeriod,
            onDatePeriodChanged: (period) =>
                setState(() => _datePeriod = period),
            selectionMode: _selectionMode,
            selectedIds: _selected,
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
          _ => AppEmptyState(
            title: 'Set up your business first',
            description:
                'Create your business profile before recording sales and printing receipts.',
            icon: Icons.storefront_outlined,
            actionLabel: 'Set Up Business',
            onAction: () => context.push(AppRoutes.businessSetup),
          ),
        },
      ),
    );
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b) || a.length != b.length) return identical(a, b);
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _bulkVoid(String businessId) async {
    if (_selected.isEmpty) return;
    final writableBranchId = ref.read(currentWritableBranchIdProvider);
    if (writableBranchId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(branchWriteBlockedMessage)));
      return;
    }
    final ok = await confirmListDelete(
      context,
      title: 'Void ${_selected.length} sales?',
      message:
          'Selected sales will be voided and stock will be restored where tracked.',
      confirmLabel: 'Void',
    );
    if (!ok) return;
    final repo = ref.read(sales.salesRepositoryProvider);
    var count = 0;
    for (final id in _selected.toList()) {
      try {
        await repo.voidSale(
          businessId,
          id,
          branchId: writableBranchId,
          reason: 'Removed from sales list',
        );
        count++;
      } catch (_) {}
    }
    ref.invalidate(sales.salesHistoryProvider(businessId));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Voided $count sales.')));
    _clearSelection();
  }
}

class _SalesHistory extends ConsumerWidget {
  const _SalesHistory({
    required this.businessId,
    required this.datePeriod,
    required this.onDatePeriodChanged,
    required this.selectionMode,
    required this.selectedIds,
    required this.onVisibleIds,
    required this.onToggleSelected,
    required this.onEnterSelection,
  });

  final String businessId;
  final RecordDatePeriod datePeriod;
  final ValueChanged<RecordDatePeriod> onDatePeriodChanged;
  final bool selectionMode;
  final Set<String> selectedIds;
  final ValueChanged<List<String>> onVisibleIds;
  final ValueChanged<String> onToggleSelected;
  final ValueChanged<String> onEnterSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(sales.salesHistoryProvider(businessId));
    final branchId = ref.watch(currentBranchReadScopeProvider);
    return history.when(
      loading: () => const AppListSkeleton(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      ),
      error: (error, _) {
        final view = branchQueryErrorView(
          error,
          queryName: 'sales',
          businessId: businessId,
          branchId: branchId,
          limit: 25,
        );
        return AppErrorState(
          message: view.message,
          onRetry: () => ref.invalidate(sales.salesHistoryProvider(businessId)),
        );
      },
      data: (saleItems) {
        final filteredItems = saleItems
            .where((sale) => recordFallsInPeriod(sale.createdAt, datePeriod))
            .toList(growable: false);
        onVisibleIds(
          filteredItems
              .where((s) => s.saleStatus != SaleStatus.voided)
              .map((s) => s.saleId)
              .toList(growable: false),
        );
        return Column(
          children: <Widget>[
            RecordDateFilterBar(
              selected: datePeriod,
              onSelected: onDatePeriodChanged,
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: filteredItems.isEmpty
                  ? AppEmptyState(
                      title: 'No sales in this period',
                      description: datePeriod == RecordDatePeriod.all
                          ? 'Complete your first sale and it will appear here.'
                          : 'Choose another date range to see older sales.',
                      icon: Icons.receipt_long_outlined,
                      actionLabel: 'New Sale',
                      actionIcon: Icons.add,
                      onAction: () => context.push(AppRoutes.newSale),
                    )
                  : RefreshIndicator(
                      onRefresh: () async => ref.invalidate(
                        sales.salesHistoryProvider(businessId),
                      ),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          0,
                          AppSpacing.lg,
                          AppTabChrome.bottomInset,
                        ),
                        itemCount: filteredItems.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final sale = filteredItems[index];
                          final canVoid = sale.saleStatus != SaleStatus.voided;
                          final tile = AppListRow(
                            onTap: () => SalesNavigation.openSaleDetails(
                              context,
                              sale.saleId,
                            ),
                            leading: const AppListAvatar(
                              icon: Icons.receipt_long_outlined,
                            ),
                            title: sale.receiptNumber,
                            subtitle:
                                '${sale.customerName} · ${sale.paymentMethod.label}'
                                '${canVoid ? '' : ' · VOIDED'}\n'
                                '${formatRecordDateTime(sale.createdAt)}',
                            isThreeLine: true,
                            trailing: Text(
                              formatCurrency(
                                minorToMoney(sale.totalMinor),
                                code: sale.currencyCode,
                                symbol: sale.currencySymbol,
                              ),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                decoration: canVoid
                                    ? null
                                    : TextDecoration.lineThrough,
                              ),
                            ),
                          );
                          return SelectableDismissibleTile(
                                id: sale.saleId,
                                selectionMode: selectionMode,
                                selected: selectedIds.contains(sale.saleId),
                                onToggleSelected: onToggleSelected,
                                enabled: canVoid,
                                dismissLabel: 'Void',
                                confirmTitle: 'Void sale?',
                                confirmMessage:
                                    '“${sale.receiptNumber}” will be voided and stock restored where tracked.',
                                confirmLabel: 'Void',
                                onDismissed: (id) async {
                                  final writableBranchId = ref.read(
                                    currentWritableBranchIdProvider,
                                  );
                                  if (writableBranchId == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          branchWriteBlockedMessage,
                                        ),
                                      ),
                                    );
                                    return false;
                                  }
                                  try {
                                    await ref
                                        .read(sales.salesRepositoryProvider)
                                        .voidSale(
                                          businessId,
                                          id,
                                          branchId: writableBranchId,
                                          reason: 'Removed from sales list',
                                        );
                                    ref.invalidate(
                                      sales.salesHistoryProvider(businessId),
                                    );
                                    return true;
                                  } catch (_) {
                                    return false;
                                  }
                                },
                                child: GestureDetector(
                                  onLongPress: canVoid
                                      ? () => onEnterSelection(sale.saleId)
                                      : null,
                                  child: tile,
                                ),
                              )
                              .animate()
                              .fadeIn(
                                duration: AppMotion.standard,
                                delay: Duration(
                                  milliseconds: 20 * index.clamp(0, 12),
                                ),
                                curve: AppMotion.entranceCurve,
                              )
                              .slideY(
                                begin: 0.03,
                                end: 0,
                                duration: AppMotion.standard,
                                curve: AppMotion.entranceCurve,
                              );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class NewSaleScreen extends ConsumerStatefulWidget {
  const NewSaleScreen({super.key});
  @override
  ConsumerState<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends ConsumerState<NewSaleScreen> {
  String _query = '';

  Future<void> _scanProduct(List<SaleProduct> products) async {
    final barcode = await scanBarcode(context);
    if (!mounted || barcode == null) return;
    final normalized = barcode.trim();
    SaleProduct? match;
    for (final product in products) {
      if (product.barcode?.trim() == normalized) {
        match = product;
        break;
      }
    }
    if (match == null) {
      setState(() => _query = normalized);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No product matches this barcode.')),
      );
      return;
    }
    if (match.isOutOfStock) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${match.name} is out of stock.')));
      return;
    }
    ref.read(saleCartProvider.notifier).addProduct(match);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${match.name} added to cart.')));
  }

  @override
  Widget build(BuildContext context) {
    final terminology = ref.watch(currentBusinessTerminologyProvider);
    final activeBusiness = ref.watch(activeBusinessProvider).asData?.value;
    if (activeBusiness is! ActiveBusinessData) {
      return const Scaffold(body: SafeArea(child: _SalesBusinessRequired()));
    }
    final business = activeBusiness.business;
    final products = ref.watch(sales.saleProductsProvider(business.businessId));
    final cart = ref.watch(saleCartProvider);
    final filteredProducts =
        products.asData?.value.where((product) {
          final query = _query.toLowerCase().trim();
          return query.isEmpty ||
              product.name.toLowerCase().contains(query) ||
              (product.sku ?? '').toLowerCase().contains(query) ||
              (product.barcode ?? '').contains(query);
        }).toList() ??
        const <SaleProduct>[];
    final totals = cart.totals(
      taxEnabled: business.taxEnabled,
      taxPercentage: business.taxPercentage,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('New ${terminology.sale}'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('${cart.items.length} items')),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (cart.items.isNotEmpty) ...<Widget>[
                OutlinedButton.icon(
                  onPressed: () => _showCartSheet(context, business),
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: Text(
                    'View cart (${cart.items.length} '
                    '${cart.items.length == 1 ? 'item' : 'items'})',
                  ),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                onPressed: cart.items.isEmpty
                    ? null
                    : () => context.push(AppRoutes.checkout),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      const Text('Checkout'),
                      Text(
                        formatCurrency(
                          minorToMoney(totals.totalMinor),
                          code: business.currency.code,
                          symbol: business.currency.symbol,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          children: <Widget>[
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText:
                    'Search ${terminology.products.toLowerCase()}, SKU or barcode',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Scan barcode',
                      onPressed: products.hasValue
                          ? () => _scanProduct(products.value!)
                          : null,
                      icon: const Icon(Icons.qr_code_scanner),
                    ),
                    IconButton(
                      tooltip: 'Add custom item',
                      onPressed: () => _showCustomItemSheet(context),
                      icon: const Icon(Icons.add_box_outlined),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: products.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) =>
                    const Center(child: Text('Could not load products.')),
                data: (_) {
                  if (filteredProducts.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Text(
                              'No active products found.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Add products from the Products tab, or add a custom item to continue.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.tonal(
                              onPressed: () => context.go(AppRoutes.products),
                              child: const Text('Go to Products'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final useSingleColumn =
                          constraints.maxWidth < 340 ||
                          MediaQuery.textScalerOf(context).scale(1) > 1.3;
                      return GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: useSingleColumn ? 1 : 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: useSingleColumn ? 138 : 164,
                        ),
                        itemCount: filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = filteredProducts[index];
                          final cartItem = cart.items
                              .where(
                                (item) =>
                                    item.productId == product.productId &&
                                    !item.isCustomItem,
                              )
                              .firstOrNull;
                          return Card(
                            shape: cartItem == null
                                ? null
                                : RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      width: 1.6,
                                    ),
                                  ),
                            child: InkWell(
                              onTap: product.isOutOfStock
                                  ? null
                                  : () => ref
                                        .read(saleCartProvider.notifier)
                                        .addProduct(product),
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        CircleAvatar(
                                          radius: 17,
                                          backgroundColor: context.brandTint,
                                          child: Icon(
                                            product.isOutOfStock
                                                ? Icons.block
                                                : Icons.inventory_2_outlined,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            size: 19,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        if (cartItem != null)
                                          Expanded(
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: _QuantityStepper(
                                                quantity: cartItem.quantity,
                                                unit: cartItem.unit,
                                                quantityInput:
                                                    cartItem.quantityInput,
                                                onIncrease: () => ref
                                                    .read(
                                                      saleCartProvider.notifier,
                                                    )
                                                    .addProduct(product),
                                                onDecrease: () => ref
                                                    .read(
                                                      saleCartProvider.notifier,
                                                    )
                                                    .decreaseQuantity(
                                                      cartItem.saleItemId,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        if (cartItem == null) const Spacer(),
                                      ],
                                    ),
                                    const Spacer(),
                                    Text(
                                      product.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      formatCurrency(
                                        minorToMoney(product.sellingPriceMinor),
                                        code: business.currency.code,
                                        symbol: business.currency.symbol,
                                      ),
                                    ),
                                    Text(
                                      product.isOutOfStock
                                          ? 'Out of stock'
                                          : '${product.quantity} ${product.unit}',
                                      style: TextStyle(
                                        color: product.isOutOfStock
                                            ? Colors.red
                                            : context.mutedTextColor,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomItemSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _AddCustomItemSheet(
          onSubmit: (name, quantityText, unitPriceText) {
            final parsedQty = parseQuantityInput(quantityText);
            if (!parsedQty.isValid) {
              return 'Quantity must include a number greater than zero (e.g. 2 bags).';
            }
            final parsedPrice = parseMoneyInput(unitPriceText);
            if (!parsedPrice.isValid) {
              return 'Enter a unit price number, or text like paid.';
            }
            return ref
                .read(saleCartProvider.notifier)
                .addCustomItem(
                  name: name,
                  quantity: parsedQty.quantity,
                  unit: parsedQty.unit,
                  quantityInput: parsedQty.raw,
                  unitPrice: parsedPrice.amount,
                  unitPriceInput: parsedPrice.raw,
                );
          },
        );
      },
    );
  }

  void _showCartSheet(BuildContext context, dynamic business) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CartReviewSheet(business: business),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.onIncrease,
    required this.onDecrease,
    this.quantityInput,
    this.unit = 'unit',
  });

  final double quantity;
  final String? quantityInput;
  final String unit;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final label = formatSaleQuantityLabel(
      quantity: quantity,
      unit: unit,
      quantityInput: quantityInput,
    );
    return Container(
      decoration: BoxDecoration(
        color: context.brandTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          InkWell(
            customBorder: const CircleBorder(),
            onTap: onDecrease,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.remove, size: 15, color: primary),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 50),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
          InkWell(
            customBorder: const CircleBorder(),
            onTap: onIncrease,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.add, size: 15, color: primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet listing everything in the sale so the merchant can adjust
/// quantities or remove items before heading to checkout.
class _CartReviewSheet extends ConsumerWidget {
  const _CartReviewSheet({required this.business});

  final dynamic business;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(saleCartProvider);
    final totals = cart.totals(
      taxEnabled: business.taxEnabled,
      taxPercentage: business.taxPercentage,
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Cart',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (cart.items.isNotEmpty)
                  TextButton(
                    onPressed: () =>
                        ref.read(saleCartProvider.notifier).clear(),
                    child: const Text('Clear all'),
                  ),
              ],
            ),
            if (cart.items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('Your cart is empty.')),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: cart.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = cart.items[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  formatSaleUnitPriceLabel(
                                    formattedMoney: formatCurrency(
                                      minorToMoney(item.unitPriceMinor),
                                      code: business.currency.code,
                                      symbol: business.currency.symbol,
                                    ),
                                    unitPriceInput: item.unitPriceInput,
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.mutedTextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _QuantityStepper(
                            quantity: item.quantity,
                            unit: item.unit,
                            quantityInput: item.quantityInput,
                            onIncrease: () => ref
                                .read(saleCartProvider.notifier)
                                .increaseQuantity(item.saleItemId),
                            onDecrease: () => ref
                                .read(saleCartProvider.notifier)
                                .decreaseQuantity(item.saleItemId),
                          ),
                          IconButton(
                            tooltip: 'Remove item',
                            onPressed: () => ref
                                .read(saleCartProvider.notifier)
                                .removeItem(item.saleItemId),
                            icon: const Icon(Icons.delete_outline, size: 20),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text(
                  'Total',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  formatCurrency(
                    minorToMoney(totals.totalMinor),
                    code: business.currency.code,
                    symbol: business.currency.symbol,
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: cart.items.isEmpty
                  ? null
                  : () {
                      Navigator.pop(context);
                      context.push(AppRoutes.checkout);
                    },
              child: const Text('Go to Checkout'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddCustomItemSheet extends StatefulWidget {
  const _AddCustomItemSheet({required this.onSubmit});

  final String? Function(String name, String quantityText, String unitPriceText)
  onSubmit;

  @override
  State<_AddCustomItemSheet> createState() => _AddCustomItemSheetState();
}

class _AddCustomItemSheetState extends State<_AddCustomItemSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  late final TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _quantityController = TextEditingController(text: '1');
    _priceController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Add custom item',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Item name'),
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.none,
                    decoration: const InputDecoration(
                      labelText: 'Quantity / unit',
                      hintText: 'e.g. 2 bags',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _priceController,
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Unit price',
                      hintText: 'e.g. 50 or paid',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final error = widget.onSubmit(
                  _nameController.text,
                  _quantityController.text,
                  _priceController.text,
                );
                if (error != null) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error)));
                  return;
                }
                if (!mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Add item'),
            ),
          ],
        ),
      ),
    );
  }
}

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _amountController = TextEditingController();
  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeBusiness = ref.watch(activeBusinessProvider).asData?.value;
    if (activeBusiness is! ActiveBusinessData) {
      return const Scaffold(body: SafeArea(child: _SalesBusinessRequired()));
    }
    final business = activeBusiness.business;
    final cart = ref.watch(saleCartProvider);
    final totals = cart.totals(
      taxEnabled: business.taxEnabled,
      taxPercentage: business.taxPercentage,
    );
    final customers = ref.watch(
      sales.saleCustomersProvider(business.businessId),
    );
    final requiresCustomer =
        cart.paymentMethod == PaymentMethod.credit ||
        totals.balanceDueMinor > 0;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      // Hide the sticky bar while typing so the amount field stays visible.
      bottomNavigationBar: keyboardInset > 0
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: cart.isSubmitting || cart.items.isEmpty
                      ? null
                      : () => _completeSale(business),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      cart.isSubmitting
                          ? 'Completing sale...'
                          : 'Complete Sale',
                    ),
                  ),
                ),
              ),
            ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + keyboardInset),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: <Widget>[
          Text(
            'Items (${cart.items.length})',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: <Widget>[
                  for (final item in cart.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  formatSaleUnitPriceLabel(
                                    formattedMoney: formatCurrency(
                                      minorToMoney(item.unitPriceMinor),
                                      code: business.currency.code,
                                      symbol: business.currency.symbol,
                                    ),
                                    unitPriceInput: item.unitPriceInput,
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.mutedTextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _QuantityStepper(
                            quantity: item.quantity,
                            unit: item.unit,
                            quantityInput: item.quantityInput,
                            onIncrease: () => ref
                                .read(saleCartProvider.notifier)
                                .increaseQuantity(item.saleItemId),
                            onDecrease: () => ref
                                .read(saleCartProvider.notifier)
                                .decreaseQuantity(item.saleItemId),
                          ),
                          IconButton(
                            tooltip: 'Remove item',
                            onPressed: () => ref
                                .read(saleCartProvider.notifier)
                                .removeItem(item.saleItemId),
                            icon: const Icon(Icons.delete_outline, size: 20),
                          ),
                        ],
                      ),
                    ),
                  if (cart.items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No items in this sale yet.'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Payment', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<PaymentMethod>(
            initialValue: cart.paymentMethod,
            items: PaymentMethod.values
                .map(
                  (method) => DropdownMenuItem(
                    value: method,
                    child: Text(method.label),
                  ),
                )
                .toList(),
            onChanged: (method) {
              if (method != null) {
                ref.read(saleCartProvider.notifier).setPaymentMethod(method);
              }
            },
          ),
          const SizedBox(height: 16),
          customers.when(
            data: (items) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                DropdownButtonFormField<SaleCustomer?>(
                  initialValue: cart.customer,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: requiresCustomer
                        ? 'Customer (required for credit/partial payment)'
                        : 'Customer (optional for cash sales)',
                  ),
                  items: <DropdownMenuItem<SaleCustomer?>>[
                    const DropdownMenuItem<SaleCustomer?>(
                      value: null,
                      child: Text('Walk-in customer'),
                    ),
                    ...items.map(
                      (customer) => DropdownMenuItem<SaleCustomer?>(
                        value: customer,
                        child: Text(
                          customer.phone == null || customer.phone!.isEmpty
                              ? customer.name
                              : '${customer.name} · ${customer.phone}',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (customer) => ref
                      .read(saleCartProvider.notifier)
                      .selectCustomer(customer),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final createdId = await context.pushNamed<String>(
                        AppRouteNames.newCustomer,
                        queryParameters: const <String, String>{
                          'returnTo': 'checkout',
                        },
                      );
                      if (createdId == null || !mounted) return;
                      ref.invalidate(
                        sales.saleCustomersProvider(business.businessId),
                      );
                      final refreshed = await ref.read(
                        sales.saleCustomersProvider(business.businessId).future,
                      );
                      final match = refreshed
                          .where((customer) => customer.customerId == createdId)
                          .firstOrNull;
                      if (match != null && mounted) {
                        ref
                            .read(saleCartProvider.notifier)
                            .selectCustomer(match);
                      }
                    },
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Add new customer'),
                  ),
                ),
                if (cart.customer != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => ref
                          .read(saleCartProvider.notifier)
                          .selectCustomer(null),
                      child: const Text('Remove selected customer'),
                    ),
                  ),
              ],
            ),
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('Could not load customers.'),
          ),
          if (requiresCustomer)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'A customer is required so credit balances can be tracked safely.',
                style: TextStyle(color: AppColors.mutedText),
              ),
            ),
          if (cart.paymentMethod == PaymentMethod.cash) ...<Widget>[
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (value) => ref
                  .read(saleCartProvider.notifier)
                  .setAmountReceived(double.tryParse(value) ?? 0),
              decoration: const InputDecoration(labelText: 'Amount received'),
            ),
          ],
          const SizedBox(height: 24),
          _TotalsCard(totals: totals, business: business),
          if (requiresCustomer && cart.customer == null)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'A customer is required for credit or partial payment.',
                style: TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _completeSale(dynamic business) async {
    final cart = ref.read(saleCartProvider);
    final totals = cart.totals(
      taxEnabled: business.taxEnabled,
      taxPercentage: business.taxPercentage,
    );
    final branchId = ref.read(currentWritableBranchIdProvider);
    final branchSelection = ref.read(currentBranchProvider).asData?.value;
    if (branchId == null || branchSelection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select an active branch before recording a sale.'),
        ),
      );
      return;
    }
    final branch = branchSelection.branches.firstWhere(
      (candidate) => candidate.branchId == branchId,
      orElse: () => branchSelection.mainBranch,
    );
    if (branch.branchId != branchId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select an active branch before recording a sale.'),
        ),
      );
      return;
    }
    if ((cart.paymentMethod == PaymentMethod.credit ||
            totals.balanceDueMinor > 0) &&
        cart.customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a customer for credit or partial payment.'),
        ),
      );
      return;
    }
    final saleId = ref.read(saleCartProvider.notifier).beginSubmission();
    try {
      final completed = await ref
          .read(sales.salesRepositoryProvider)
          .completeSale(
            CompleteSaleRequest(
              business: business,
              cart: cart,
              saleId: saleId,
              cashierName: null,
              branchId: branchId,
              branchNameSnapshot: branch.name,
              branchCodeSnapshot: branch.code,
            ),
          );
      ref.read(saleCartProvider.notifier).finishSubmission(succeeded: true);
      if (mounted) {
        context.go(
          '${AppRoutes.sales}/success/${completed.saleId}',
          extra: completed,
        );
      }
    } on SaleException catch (error) {
      ref.read(saleCartProvider.notifier).finishSubmission(succeeded: false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.friendlyMessage)));
      }
    } catch (_) {
      ref.read(saleCartProvider.notifier).finishSubmission(succeeded: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong while completing the sale.'),
          ),
        );
      }
    }
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals, required this.business});
  final SaleTotals totals;
  final dynamic business;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          _totalRow('Subtotal', totals.subtotalMinor),
          if (totals.itemDiscountMinor + totals.orderDiscountMinor > 0)
            _totalRow(
              'Discount',
              -(totals.itemDiscountMinor + totals.orderDiscountMinor),
            ),
          if (totals.taxMinor > 0) _totalRow('Tax', totals.taxMinor),
          const Divider(),
          _totalRow('Total', totals.totalMinor, bold: true),
          _totalRow('Amount paid', totals.amountPaidMinor),
          if (totals.balanceDueMinor > 0)
            _totalRow('Balance due', totals.balanceDueMinor, bold: true),
          if (totals.changeMinor > 0)
            _totalRow('Change', totals.changeMinor, bold: true),
        ],
      ),
    ),
  );
  Widget _totalRow(String label, int amount, {bool bold = false}) => Builder(
    builder: (context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            formatCurrency(
              minorToMoney(amount),
              code: business.currency.code,
              symbol: business.currency.symbol,
            ),
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

class SaleCompleteScreen extends ConsumerWidget {
  const SaleCompleteScreen({required this.saleId, this.completed, super.key});
  final String saleId;
  final CompletedSale? completed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    final saleAsync = active is ActiveBusinessData
        ? ref.watch(
            sales.saleDocumentProvider((active.business.businessId, saleId)),
          )
        : null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                children: <Widget>[
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.75, end: 1),
                    duration: AppMotion.resolve(context, AppMotion.emphasized),
                    curve: Curves.easeOutBack,
                    builder: (context, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: const Icon(
                      Icons.check_circle,
                      size: 56,
                      color: Color(0xFF12B76A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sale completed',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(completed?.receiptNumber ?? 'Receipt ready'),
                  if (completed != null)
                    Text(formatCurrency(minorToMoney(completed!.totalMinor))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Receipt rendered with the merchant's default template.
            Expanded(
              child: active is! ActiveBusinessData || saleAsync == null
                  ? const SizedBox.shrink()
                  : saleAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, _) => const SizedBox.shrink(),
                      data: (sale) => sale == null
                          ? const SizedBox.shrink()
                          : SaleReceiptPreview(
                              sale: sale,
                              business: active.business,
                              showActions: true,
                            ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                children: <Widget>[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () =>
                          SalesNavigation.openSaleReceipt(context, saleId),
                      child: const Text('View Receipt'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () =>
                          SalesNavigation.openSaleDetails(context, saleId),
                      child: const Text('View Sale Details'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go(AppRoutes.sales),
                    child: const Text('Back to Sales'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DigitalReceiptScreen extends ConsumerWidget {
  const DigitalReceiptScreen({required this.saleId, super.key});
  final String saleId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) {
      return const Scaffold(body: _SalesBusinessRequired());
    }
    final future = ref.watch(
      sales.saleDocumentProvider((active.business.businessId, saleId)),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Digital Receipt')),
      body: future.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not load receipt.')),
        data: (sale) {
          if (sale == null) {
            return const Center(child: Text('Receipt not found.'));
          }
          // Renders the merchant's default receipt design (frozen at
          // checkout) instead of a plain generic layout.
          return SaleReceiptPreview(
            sale: sale,
            business: active.business,
            showActions: true,
          );
        },
      ),
    );
  }
}

class _SalesBusinessRequired extends StatelessWidget {
  const _SalesBusinessRequired();

  @override
  Widget build(BuildContext context) => AppEmptyState(
    title: 'Set up your business first',
    description:
        'Create your business profile before recording sales and printing receipts.',
    icon: Icons.storefront_outlined,
    actionLabel: 'Set Up Business',
    onAction: () => context.push(AppRoutes.businessSetup),
  );
}
