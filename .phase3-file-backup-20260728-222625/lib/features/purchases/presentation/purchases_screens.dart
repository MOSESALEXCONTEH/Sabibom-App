import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../app/router.dart';
import '../../../core/formatting/currency_formatter.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_list_primitives.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../../core/widgets/list_bulk_actions.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../products/application/products_providers.dart';
import '../../products/domain/product.dart';
import '../../sales/domain/sale_models.dart';
import '../../suppliers/application/suppliers_providers.dart';
import '../../suppliers/domain/supplier.dart';
import '../application/purchases_providers.dart';
import '../data/purchases_repository.dart';
import '../domain/purchase.dart';
import '../domain/purchase_calculator.dart';

class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> {
  var _selectionMode = false;
  final Set<String> _selected = <String>{};
  List<String> _visibleIds = const [];

  void _clearSelection() => setState(() {
        _selectionMode = false;
        _selected.clear();
      });

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) {
      return Scaffold(
        appBar: AppBar(title: const Text('Purchases')),
        body: AppEmptyState(
          title: 'Set up a business first',
          description: 'Create or select a business before recording purchases.',
          icon: Icons.storefront_outlined,
          actionLabel: 'Set Up Business',
          onAction: () => context.push(AppRoutes.businessSetup),
        ),
      );
    }
    final businessId = active.business.businessId;
    final purchases = ref.watch(purchasesProvider(businessId));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode ? '${_selected.length} selected' : 'Purchases',
        ),
        actions: bulkSelectActions(
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
          onDeleteSelected: () => _bulkVoid(businessId),
          deleteTooltip: 'Void selected',
        ),
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.pushNamed(AppRouteNames.newPurchase),
              icon: const Icon(Icons.add),
              label: const Text('New purchase'),
            ),
      body: purchases.when(
        loading: () => const AppListSkeleton(
          padding: EdgeInsets.all(AppSpacing.md),
        ),
        error: (_, _) => AppErrorState(
          message: 'Could not load purchases.',
          onRetry: () => ref.invalidate(purchasesProvider(businessId)),
        ),
        data: (items) {
          final voidable = items
              .where((p) => p.status != PurchaseStatus.voided)
              .map((p) => p.purchaseId)
              .toList(growable: false);
          if (!_listEquals(voidable, _visibleIds)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _visibleIds = voidable);
            });
          }
          if (items.isEmpty) {
            return AppEmptyState(
              title: 'No purchases yet',
              description: 'Record stock purchases from your suppliers.',
              icon: Icons.shopping_cart_outlined,
              actionLabel: 'New purchase',
              actionIcon: Icons.add,
              onAction: () => context.pushNamed(AppRouteNames.newPurchase),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: items.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final purchase = items[index];
              final canVoid = purchase.status != PurchaseStatus.voided;
              final tile = AppListRow(
                onTap: () => context.pushNamed(
                  AppRouteNames.purchaseDetails,
                  pathParameters: <String, String>{
                    'purchaseId': purchase.purchaseId,
                  },
                ),
                leading: const AppListAvatar(
                  icon: Icons.inventory_2_outlined,
                ),
                title: purchase.purchaseNumber,
                subtitle:
                    '${purchase.supplierName} · ${purchase.paymentStatus.name.replaceAll('partially', 'partially ')}'
                    '${canVoid ? '' : ' · VOIDED'}',
                trailing: Text(
                  formatCurrency(
                    minorToMoney(purchase.totalMinor),
                    code: active.business.currency.code,
                    symbol: active.business.currency.symbol,
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration:
                        canVoid ? null : TextDecoration.lineThrough,
                  ),
                ),
              );
              return SelectableDismissibleTile(
                id: purchase.purchaseId,
                selectionMode: _selectionMode,
                selected: _selected.contains(purchase.purchaseId),
                onToggleSelected: (id) => setState(() {
                  if (_selected.contains(id)) {
                    _selected.remove(id);
                  } else {
                    _selected.add(id);
                  }
                }),
                enabled: canVoid,
                dismissLabel: 'Void',
                confirmTitle: 'Void purchase?',
                confirmMessage:
                    '“${purchase.purchaseNumber}” will be marked voided. Use Purchase Return if you need to reverse stock.',
                confirmLabel: 'Void',
                onDismissed: (id) async {
                  try {
                    await ref.read(purchasesRepositoryProvider).voidPurchase(
                          businessId,
                          id,
                          reason: 'Removed from purchases list',
                        );
                    ref.invalidate(purchasesProvider(businessId));
                    return true;
                  } catch (_) {
                    return false;
                  }
                },
                child: GestureDetector(
                  onLongPress: canVoid
                      ? () => setState(() {
                            _selectionMode = true;
                            _selected.add(purchase.purchaseId);
                          })
                      : null,
                  child: tile,
                ),
              );
            },
          );
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

  Future<void> _bulkVoid(String businessId) async {
    if (_selected.isEmpty) return;
    final ok = await confirmListDelete(
      context,
      title: 'Void ${_selected.length} purchases?',
      message:
          'Selected purchases will be marked voided. Use Purchase Return if stock must be reversed.',
      confirmLabel: 'Void',
    );
    if (!ok) return;
    final repo = ref.read(purchasesRepositoryProvider);
    var count = 0;
    for (final id in _selected.toList()) {
      try {
        await repo.voidPurchase(
          businessId,
          id,
          reason: 'Removed from purchases list',
        );
        count++;
      } catch (_) {}
    }
    ref.invalidate(purchasesProvider(businessId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Voided $count purchases.')),
    );
    _clearSelection();
  }
}

class NewPurchaseScreen extends ConsumerStatefulWidget {
  const NewPurchaseScreen({
    this.preselectedSupplierId,
    this.sabiQuery,
    super.key,
  });
  final String? preselectedSupplierId;
  final String? sabiQuery;


  @override
  ConsumerState<NewPurchaseScreen> createState() => _NewPurchaseScreenState();
}

class _NewPurchaseScreenState extends ConsumerState<NewPurchaseScreen> {
  final _paidController = TextEditingController();
  final _taxController = TextEditingController();
  final _deliveryController = TextEditingController();
  final Map<String, PurchaseItem> _items = <String, PurchaseItem>{};
  String? _supplierId;
  String? _purchaseId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _supplierId = widget.preselectedSupplierId;
  }

  @override
  void dispose() {
    _paidController.dispose();
    _taxController.dispose();
    _deliveryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) {
      return const Scaffold(
        body: Center(child: Text('Set up a business first.')),
      );
    }
    final business = active.business;
    final products = ref.watch(productsListProvider(business.businessId));
    final suppliers = ref.watch(suppliersListProvider(business.businessId));
    final totals = _totals;
    return Scaffold(
      appBar: AppBar(title: const Text('New purchase')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _submitting ? null : () => _submit(business),
            child: Text(
              _submitting ? 'Recording purchase...' : 'Complete purchase',
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: <Widget>[
          if (widget.sabiQuery?.trim().isNotEmpty == true) ...<Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'From Sabi: ${widget.sabiQuery!.trim()}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          suppliers.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('Could not load suppliers.'),
            data: (items) => DropdownButtonFormField<Supplier>(
              initialValue: items
                  .where((supplier) => supplier.id == _supplierId)
                  .firstOrNull,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Supplier'),
              items: items
                  .map(
                    (supplier) => DropdownMenuItem(
                      value: supplier,
                      child: Text(supplier.name),
                    ),
                  )
                  .toList(),
              onChanged: (supplier) =>
                  setState(() => _supplierId = supplier?.id),
            ),
          ),
          const SizedBox(height: 20),
          Text('Products', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          products.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('Could not load products.'),
            data: (products) => _ProductPicker(
              products: products.where((product) => product.isActive).toList(),
              selected: _items,
              onAdd: _addProduct,
            ),
          ),
          if (_items.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            ..._items.values.map(
              (item) => _PurchaseLineEditor(
                item: item,
                onChanged: (next) =>
                    setState(() => _items[next.purchaseItemId] = next),
                onRemove: () =>
                    setState(() => _items.remove(item.purchaseItemId)),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Charges and payment',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          TextField(
            controller: _taxController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Tax (%)',
              hintText: '0',
            ),
          ),
          TextField(
            controller: _deliveryController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Delivery charge',
              hintText: '0',
            ),
          ),
          TextField(
            controller: _paidController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Amount paid',
              hintText: '0',
            ),
          ),
          const SizedBox(height: 16),
          _PurchaseTotals(totals: totals, business: business),
        ],
      ),
    );
  }

  PurchaseTotals get _totals {
    try {
      return PurchaseCalculator.calculate(
        items: _items.values.toList(),
        taxPercentage: double.tryParse(_taxController.text) ?? 0,
        deliveryMinor: moneyToMinor(_deliveryController.text),
        amountPaidMinor: moneyToMinor(_paidController.text),
      );
    } on PurchaseException {
      return const PurchaseTotals(
        subtotalMinor: 0,
        itemDiscountMinor: 0,
        orderDiscountMinor: 0,
        taxMinor: 0,
        deliveryMinor: 0,
        totalMinor: 0,
        amountPaidMinor: 0,
        balanceDueMinor: 0,
      );
    }
  }

  void _addProduct(Product product) => setState(() {
    final existing = _items[product.id];
    _items[product.id] = PurchaseItem(
      purchaseItemId: product.id,
      productId: product.id,
      name: product.name,
      sku: product.sku,
      unit: product.unit,
      quantity: (existing?.quantity ?? 0) + 1,
      unitCostMinor: existing?.unitCostMinor ?? product.costPriceMinor,
      trackStock: product.trackStock,
      tracksExpiry: product.tracksExpiry,
      expiryDate: existing?.expiryDate,
      expiryDateKnown: existing?.expiryDateKnown ?? false,
    );
  });

  Future<void> _submit(dynamic business) async {
    if (_supplierId == null || _items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a supplier and add products.')),
      );
      return;
    }
    final supplier = ref
        .read(suppliersListProvider(business.businessId))
        .asData
        ?.value
        .where((supplier) => supplier.id == _supplierId)
        .firstOrNull;
    if (supplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The selected supplier is unavailable.')),
      );
      return;
    }
    setState(() => _submitting = true);
    _purchaseId ??= const Uuid().v4();
    try {
      final result = await ref
          .read(purchasesRepositoryProvider)
          .completePurchase(
            CompletePurchaseRequest(
              purchaseId: _purchaseId!,
              businessId: business.businessId,
              supplierId: _supplierId!,
              supplierName: supplier.name,
              items: _items.values.toList(),
              taxPercentage: double.tryParse(_taxController.text) ?? 0,
              deliveryMinor: moneyToMinor(_deliveryController.text),
              amountPaidMinor: moneyToMinor(_paidController.text),
              paymentMethod: 'cash',
            ),
          );
      if (mounted) {
        context.goNamed(
          AppRouteNames.purchaseDetails,
          pathParameters: <String, String>{'purchaseId': result.purchaseId},
        );
      }
    } on PurchaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.friendlyMessage)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class PurchaseDetailsScreen extends ConsumerWidget {
  const PurchaseDetailsScreen({required this.purchaseId, super.key});
  final String purchaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) {
      return const Scaffold(body: Center(child: Text('Business required.')));
    }
    final purchase = ref.watch(
      purchaseProvider((active.business.businessId, purchaseId)),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Purchase details')),
      body: purchase.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: AppListSkeleton(),
        ),
        error: (_, _) => const Center(child: Text('Could not load purchase.')),
        data: (value) {
          if (value == null) {
            return const Center(child: Text('Purchase not found.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(
                value.purchaseNumber,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(value.supplierName),
              const SizedBox(height: 16),
              ...value.items.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.quantity} ${item.unit} × ${formatCurrency(minorToMoney(item.unitCostMinor))}',
                  ),
                  trailing: Text(
                    formatCurrency(
                      minorToMoney(PurchaseCalculator.lineSubtotal(item)),
                    ),
                  ),
                ),
              ),
              const Divider(),
              _PurchaseTotals(
                totals: PurchaseTotals(
                  subtotalMinor: value.subtotalMinor,
                  itemDiscountMinor: value.discountMinor,
                  orderDiscountMinor: 0,
                  taxMinor: value.taxMinor,
                  deliveryMinor: value.deliveryMinor,
                  totalMinor: value.totalMinor,
                  amountPaidMinor: value.amountPaidMinor,
                  balanceDueMinor: value.balanceDueMinor,
                ),
                business: active.business,
              ),
              const SizedBox(height: 20),
              if (value.balanceDueMinor > 0)
                FilledButton.icon(
                  onPressed: () => context.pushNamed(
                    AppRouteNames.supplierPayment,
                    pathParameters: <String, String>{
                      'supplierId': value.supplierId,
                    },
                  ),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Record payment'),
                ),
              if (value.status == PurchaseStatus.completed)
                OutlinedButton.icon(
                  onPressed: () => context.pushNamed(
                    AppRouteNames.purchaseReturn,
                    pathParameters: <String, String>{
                      'purchaseId': value.purchaseId,
                    },
                  ),
                  icon: const Icon(Icons.assignment_return_outlined),
                  label: const Text('Create return'),
                ),
              OutlinedButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Purchase download will be available soon.'),
                  ),
                ),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PurchaseReturnScreen extends ConsumerStatefulWidget {
  const PurchaseReturnScreen({required this.purchaseId, super.key});
  final String purchaseId;
  @override
  ConsumerState<PurchaseReturnScreen> createState() =>
      _PurchaseReturnScreenState();
}

class _PurchaseReturnScreenState extends ConsumerState<PurchaseReturnScreen> {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  bool _submitting = false;
  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) {
      return const Scaffold(body: Center(child: Text('Business required.')));
    }
    final purchase = ref.watch(
      purchaseProvider((active.business.businessId, widget.purchaseId)),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Return purchase items')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _submitting
                ? null
                : () => _submit(active.business.businessId),
            child: Text(_submitting ? 'Creating return...' : 'Create return'),
          ),
        ),
      ),
      body: purchase.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: AppListSkeleton(),
        ),
        error: (_, _) => const Center(child: Text('Could not load purchase.')),
        data: (value) {
          if (value == null) {
            return const Center(child: Text('Purchase not found.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: value.items.map((item) {
              final controller = _controllers.putIfAbsent(
                item.purchaseItemId,
                () => TextEditingController(),
              );
              return TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '${item.name} (max ${item.quantity})',
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Future<void> _submit(String businessId) async {
    final quantities = <String, double>{};
    for (final entry in _controllers.entries) {
      final value = double.tryParse(entry.value.text) ?? 0;
      if (value > 0) quantities[entry.key] = value;
    }
    if (quantities.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a return quantity.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(purchasesRepositoryProvider)
          .createPurchaseReturn(
            CreatePurchaseReturnRequest(
              returnId: const Uuid().v4(),
              businessId: businessId,
              purchaseId: widget.purchaseId,
              quantities: quantities,
            ),
          );
      if (mounted) context.pop();
    } on PurchaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.friendlyMessage)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _ProductPicker extends StatelessWidget {
  const _ProductPicker({
    required this.products,
    required this.selected,
    required this.onAdd,
  });
  final List<Product> products;
  final Map<String, PurchaseItem> selected;
  final ValueChanged<Product> onAdd;
  @override
  Widget build(BuildContext context) => Column(
    children: products
        .map(
          (product) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(product.name),
            subtitle: Text(
              'Cost: ${formatCurrency(minorToMoney(product.costPriceMinor))}',
            ),
            trailing: IconButton(
              onPressed: () => onAdd(product),
              icon: Icon(
                selected.containsKey(product.id)
                    ? Icons.add_circle
                    : Icons.add_circle_outline,
              ),
            ),
          ),
        )
        .toList(),
  );
}

class _PurchaseLineEditor extends StatefulWidget {
  const _PurchaseLineEditor({
    required this.item,
    required this.onChanged,
    required this.onRemove,
  });
  final PurchaseItem item;
  final ValueChanged<PurchaseItem> onChanged;
  final VoidCallback onRemove;
  @override
  State<_PurchaseLineEditor> createState() => _PurchaseLineEditorState();
}

class _PurchaseLineEditorState extends State<_PurchaseLineEditor> {
  late final TextEditingController _quantity;
  late final TextEditingController _cost;
  late final TextEditingController _discount;
  @override
  void initState() {
    super.initState();
    _quantity = TextEditingController(text: '${widget.item.quantity}');
    _cost = TextEditingController(
      text: '${minorToMoney(widget.item.unitCostMinor)}',
    );
    _discount = TextEditingController(text: '${widget.item.discountValue}');
  }

  @override
  void dispose() {
    _quantity.dispose();
    _cost.dispose();
    _discount.dispose();
    super.dispose();
  }

  void _change() => widget.onChanged(
    PurchaseItem(
      purchaseItemId: widget.item.purchaseItemId,
      productId: widget.item.productId,
      name: widget.item.name,
      sku: widget.item.sku,
      unit: widget.item.unit,
      trackStock: widget.item.trackStock,
      quantity: double.tryParse(_quantity.text) ?? 0,
      unitCostMinor: moneyToMinor(_cost.text),
      discountType: widget.item.discountType,
      discountValue: double.tryParse(_discount.text) ?? 0,
      tracksExpiry: widget.item.tracksExpiry,
      expiryDate: widget.item.expiryDate,
      expiryDateKnown: widget.item.expiryDateKnown,
      inventoryBatchId: widget.item.inventoryBatchId,
    ),
  );
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.item.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _quantity,
                  onChanged: (_) => _change(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Qty'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _cost,
                  onChanged: (_) => _change(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Unit cost'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _discount,
                  onChanged: (_) => _change(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Discount'),
                ),
              ),
            ],
          ),
          if (widget.item.tracksExpiry) ...<Widget>[
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Batch expiry date'),
              subtitle: Text(
                widget.item.expiryDateKnown && widget.item.expiryDate != null
                    ? DateFormat.yMMMd().format(widget.item.expiryDate!)
                    : 'Expiry date unknown',
              ),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: _selectExpiryDate,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Expiry date unknown'),
              value: !widget.item.expiryDateKnown,
              onChanged: (unknown) {
                if (unknown == false) {
                  _selectExpiryDate();
                } else {
                  widget.onChanged(
                    _copyItem(expiryDate: null, expiryDateKnown: false),
                  );
                }
              },
            ),
          ],
        ],
      ),
    ),
  );

  PurchaseItem _copyItem({
    DateTime? expiryDate,
    required bool expiryDateKnown,
  }) {
    return PurchaseItem(
      purchaseItemId: widget.item.purchaseItemId,
      productId: widget.item.productId,
      name: widget.item.name,
      sku: widget.item.sku,
      unit: widget.item.unit,
      trackStock: widget.item.trackStock,
      quantity: double.tryParse(_quantity.text) ?? 0,
      unitCostMinor: moneyToMinor(_cost.text),
      discountType: widget.item.discountType,
      discountValue: double.tryParse(_discount.text) ?? 0,
      tracksExpiry: widget.item.tracksExpiry,
      expiryDate: expiryDate,
      expiryDateKnown: expiryDateKnown,
      inventoryBatchId: widget.item.inventoryBatchId,
    );
  }

  Future<void> _selectExpiryDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: widget.item.expiryDate ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 20, 12, 31),
    );
    if (selected == null || !mounted) return;
    widget.onChanged(_copyItem(expiryDate: selected, expiryDateKnown: true));
  }
}

class _PurchaseTotals extends StatelessWidget {
  const _PurchaseTotals({required this.totals, required this.business});
  final PurchaseTotals totals;
  final dynamic business;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          _row('Subtotal', totals.subtotalMinor),
          if (totals.itemDiscountMinor + totals.orderDiscountMinor > 0)
            _row(
              'Discount',
              -(totals.itemDiscountMinor + totals.orderDiscountMinor),
            ),
          if (totals.taxMinor > 0) _row('Tax', totals.taxMinor),
          if (totals.deliveryMinor > 0) _row('Delivery', totals.deliveryMinor),
          const Divider(),
          _row('Total', totals.totalMinor, bold: true),
          _row('Amount paid', totals.amountPaidMinor),
          if (totals.balanceDueMinor > 0)
            _row('Balance due', totals.balanceDueMinor, bold: true),
        ],
      ),
    ),
  );
  Widget _row(String label, int amount, {bool bold = false}) => Builder(
    builder: (context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontWeight: bold ? FontWeight.w700 : null),
            ),
          ),
          Text(
            formatCurrency(
              minorToMoney(amount),
              code: business.currency.code,
              symbol: business.currency.symbol,
            ),
            style: TextStyle(fontWeight: bold ? FontWeight.w700 : null),
          ),
        ],
      ),
    ),
  );
}
