import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/formatting/currency_formatter.dart';
import '../../../core/theme/app_colors.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../application/sale_cart_controller.dart';
import '../application/sales_providers.dart' as sales;
import '../data/firestore_sales_repository.dart';
import '../data/sales_repository.dart';
import '../domain/sale_models.dart';

class SalesScreen extends ConsumerWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeBusiness = ref.watch(activeBusinessProvider);
    return Scaffold(
      floatingActionButton: activeBusiness.asData?.value is ActiveBusinessData
          ? FloatingActionButton.extended(
              onPressed: () => context.push(AppRoutes.newSale),
              icon: const Icon(Icons.add),
              label: const Text('New Sale'),
            )
          : null,
      body: SafeArea(
        child: activeBusiness.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const _SalesBusinessRequired(),
          data: (state) => switch (state) {
            ActiveBusinessData(:final business) => _SalesHistory(
              businessId: business.businessId,
              currencySymbol: business.currency.symbol,
            ),
            _ => const _SalesBusinessRequired(),
          },
        ),
      ),
    );
  }
}

class _SalesBusinessRequired extends StatelessWidget {
  const _SalesBusinessRequired();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.storefront_outlined,
                size: 42,
                color: AppColors.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Set up your business first',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Create your business profile before recording sales and printing receipts.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.push(AppRoutes.businessSetup),
                child: const Text('Set Up Business'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SalesHistory extends ConsumerWidget {
  const _SalesHistory({required this.businessId, required this.currencySymbol});
  final String businessId;
  final String currencySymbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(sales.salesHistoryProvider(businessId));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Sales',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text('Recent transactions and receipts'),
          const SizedBox(height: 20),
          Expanded(
            child: history.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _HistoryError(
                onRetry: () =>
                    ref.invalidate(sales.salesHistoryProvider(businessId)),
              ),
              data: (saleItems) => saleItems.isEmpty
                  ? _EmptySales(
                      onNewSale: () => context.push(AppRoutes.newSale),
                    )
                  : RefreshIndicator(
                      onRefresh: () async => ref.invalidate(
                        sales.salesHistoryProvider(businessId),
                      ),
                      child: ListView.separated(
                        itemCount: saleItems.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final sale = saleItems[index];
                          return Card(
                            child: ListTile(
                              onTap: () => context.push(
                                '${AppRoutes.sales}/${sale.saleId}',
                              ),
                              leading: const CircleAvatar(
                                child: Icon(Icons.receipt_long_outlined),
                              ),
                              title: Text(sale.receiptNumber),
                              subtitle: Text(
                                '${sale.customerName} - ${sale.paymentMethod.label}',
                              ),
                              trailing: Text(
                                formatCurrency(
                                  minorToMoney(sale.totalMinor),
                                  code: sale.currencyCode,
                                  symbol: sale.currencySymbol,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
  );
}

class _EmptySales extends StatelessWidget {
  const _EmptySales({required this.onNewSale});
  final VoidCallback onNewSale;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(
          Icons.receipt_long_outlined,
          size: 48,
          color: AppColors.primary,
        ),
        const SizedBox(height: 12),
        Text('No sales yet', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text(
          'Complete your first sale and it will appear here.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onNewSale,
          icon: const Icon(Icons.add),
          label: const Text('New Sale'),
        ),
      ],
    ),
  );
}

class NewSaleScreen extends ConsumerStatefulWidget {
  const NewSaleScreen({super.key});
  @override
  ConsumerState<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends ConsumerState<NewSaleScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
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
        title: const Text('New Sale'),
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
          child: FilledButton(
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
                hintText: 'Search products, SKU or barcode',
                suffixIcon: IconButton(
                  tooltip: 'Add custom item',
                  onPressed: () => _showCustomItemSheet(context),
                  icon: const Icon(Icons.add_box_outlined),
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
                    return const Center(
                      child: Text(
                        'No active products found. Add a custom item to continue.',
                      ),
                    );
                  }
                  return GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 156,
                        ),
                    itemCount: filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = filteredProducts[index];
                      return Card(
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
                                CircleAvatar(
                                  backgroundColor: const Color(0xFFF0ECFF),
                                  child: Icon(
                                    product.isOutOfStock
                                        ? Icons.block
                                        : Icons.inventory_2_outlined,
                                    color: AppColors.primary,
                                  ),
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
                                        : AppColors.mutedText,
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
          onSubmit: (name, quantity, unitPrice) {
            return ref
                .read(saleCartProvider.notifier)
                .addCustomItem(
                  name: name,
                  quantity: quantity,
                  unitPrice: unitPrice,
                );
          },
        );
      },
    );
  }
}

class _AddCustomItemSheet extends StatefulWidget {
  const _AddCustomItemSheet({required this.onSubmit});

  final String? Function(String name, double quantity, double unitPrice)
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
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Unit price'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              final error = widget.onSubmit(
                _nameController.text,
                double.tryParse(_quantityController.text) ?? 0,
                double.tryParse(_priceController.text) ?? -1,
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
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      bottomNavigationBar: SafeArea(
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
                cart.isSubmitting ? 'Completing sale...' : 'Complete Sale',
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
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
            data: (items) => DropdownButtonFormField<SaleCustomer>(
              initialValue: cart.customer,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: requiresCustomer
                    ? 'Customer (required)'
                    : 'Customer (optional)',
              ),
              items: <DropdownMenuItem<SaleCustomer>>[
                const DropdownMenuItem(
                  value: null,
                  child: Text('Walk-in customer'),
                ),
                ...items.map(
                  (customer) => DropdownMenuItem(
                    value: customer,
                    child: Text(customer.name),
                  ),
                ),
              ],
              onChanged: (customer) =>
                  ref.read(saleCartProvider.notifier).selectCustomer(customer),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('Could not load customers.'),
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

class SaleCompleteScreen extends StatelessWidget {
  const SaleCompleteScreen({required this.saleId, this.completed, super.key});
  final String saleId;
  final CompletedSale? completed;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.check_circle,
                size: 72,
                color: Color(0xFF12B76A),
              ),
              const SizedBox(height: 16),
              Text(
                'Sale completed',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(completed?.receiptNumber ?? 'Receipt ready'),
              if (completed != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(formatCurrency(minorToMoney(completed!.totalMinor))),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () =>
                    context.push('${AppRoutes.sales}/$saleId/receipt'),
                child: const Text('View Receipt'),
              ),
              TextButton(
                onPressed: () => context.go(AppRoutes.sales),
                child: const Text('Back to Sales'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
      sales.saleDetailProvider((active.business.businessId, saleId)),
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
          final items = sale['items'] as List<dynamic>? ?? const <dynamic>[];
          return ListView(
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              Text(
                active.business.name,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (active.business.address.isNotEmpty)
                Text(active.business.address, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Text(
                sale['receiptNumber'] as String? ?? saleId,
                textAlign: TextAlign.center,
              ),
              const Divider(height: 32),
              ...items.map((raw) {
                final item = Map<String, dynamic>.from(raw as Map);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text('${item['name']} x${item['quantity']}'),
                      ),
                      Text(
                        formatCurrency(
                          minorToMoney(
                            (item['lineTotalMinor'] as num?)?.toInt() ?? 0,
                          ),
                          symbol: active.business.currency.symbol,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const Divider(height: 32),
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'Total',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    formatCurrency(
                      minorToMoney((sale['totalMinor'] as num?)?.toInt() ?? 0),
                      symbol: active.business.currency.symbol,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Receipt sharing and Bluetooth printing will be connected in the next printer integration.',
              ),
            ],
          );
        },
      ),
    );
  }
}
