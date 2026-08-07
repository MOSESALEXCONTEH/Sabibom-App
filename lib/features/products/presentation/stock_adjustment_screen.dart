import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../branches/application/current_branch_providers.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../inventory/domain/stock_quantity_rules.dart';
import '../../sales/domain/sale_models.dart';
import '../application/products_providers.dart';
import '../data/products_repository.dart';
import '../domain/inventory_movement.dart';
import '../domain/product.dart';

class StockAdjustmentScreen extends ConsumerStatefulWidget {
  const StockAdjustmentScreen({required this.productId, super.key});

  final String productId;

  @override
  ConsumerState<StockAdjustmentScreen> createState() =>
      _StockAdjustmentScreenState();
}

class _StockAdjustmentScreenState extends ConsumerState<StockAdjustmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _reason = TextEditingController();
  final _note = TextEditingController();
  final _unitCost = TextEditingController();
  final _reference = TextEditingController();
  var _type = InventoryAdjustmentType.stockIn;
  var _submitting = false;
  var _costHydrated = false;
  var _expiryDateKnown = false;
  DateTime? _expiryDate;

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    _note.dispose();
    _unitCost.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) {
      return const Scaffold(
        body: Center(child: Text('Set up or select a business to continue.')),
      );
    }
    final businessId = active.business.businessId;
    final detail = ref.watch(
      productDetailProvider((businessId, widget.productId)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Adjust Stock')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not load product.')),
        data: (product) {
          if (product == null) {
            return const Center(child: Text('Product not found.'));
          }
          if (!_costHydrated) {
            _costHydrated = true;
            _unitCost.text = minorToMoney(
              product.costPriceMinor,
            ).toStringAsFixed(2);
          }
          return SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: <Widget>[
                  Text(
                    product.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Current stock: ${product.quantity} ${product.unit}'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<InventoryAdjustmentType>(
                    initialValue: _type,
                    decoration: const InputDecoration(
                      labelText: 'Adjustment type',
                    ),
                    items: InventoryAdjustmentType.values
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(type.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _type = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _quantity,
                    decoration: InputDecoration(
                      labelText: _type == InventoryAdjustmentType.correction
                          ? 'Quantity change (+/-) *'
                          : 'Quantity *',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    validator: (value) {
                      final amount = double.tryParse((value ?? '').trim());
                      if (amount == null || amount == 0) {
                        return 'Enter a non-zero quantity';
                      }
                      if (_type != InventoryAdjustmentType.correction &&
                          amount < 0) {
                        return 'Quantity must be positive for this type';
                      }
                      return StockQuantityRules.validate(
                        quantity: amount.abs(),
                        unit: product.unit,
                        allowZero: false,
                      );
                    },
                  ),
                  if (_type == InventoryAdjustmentType.stockIn) ...<Widget>[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _unitCost,
                      decoration: const InputDecoration(
                        labelText: 'Cost price per unit (Le) *',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) {
                        final amount = double.tryParse((value ?? '').trim());
                        if (amount == null) return 'Enter a valid cost price';
                        if (amount < 0) return 'Cost price cannot be negative';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _reference,
                      decoration: const InputDecoration(
                        labelText: 'Reference (optional)',
                      ),
                    ),
                    if (product.tracksExpiry) ...<Widget>[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Batch expiry date'),
                        subtitle: Text(
                          _expiryDateKnown && _expiryDate != null
                              ? DateFormat.yMMMd().format(_expiryDate!)
                              : 'Expiry date unknown',
                        ),
                        trailing: const Icon(Icons.calendar_month_outlined),
                        onTap: _selectExpiryDate,
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Expiry date unknown'),
                        value: !_expiryDateKnown,
                        onChanged: (unknown) {
                          if (unknown == false) {
                            _selectExpiryDate();
                          } else {
                            setState(() {
                              _expiryDateKnown = false;
                              _expiryDate = null;
                            });
                          }
                        },
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _reason,
                    decoration: const InputDecoration(
                      labelText: 'Reason (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _note,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submitting
                        ? null
                        : () => _submit(businessId, product),
                    child: Text(_submitting ? 'Saving...' : 'Save adjustment'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _submit(String businessId, Product product) async {
    if (!_formKey.currentState!.validate()) return;
    final branchId = ref.read(currentWritableBranchIdProvider);
    if (branchId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(branchWriteBlockedMessage)));
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(productsRepositoryProvider)
          .adjustStock(
            businessId,
            StockAdjustmentRequest(
              productId: widget.productId,
              type: _type,
              quantity: double.parse(_quantity.text.trim()),
              reason: _reason.text.trim(),
              note: _note.text.trim(),
              unitCostMinor: _type == InventoryAdjustmentType.stockIn
                  ? moneyToMinor(_unitCost.text.trim())
                  : null,
              expiryDate: product.tracksExpiry ? _expiryDate : null,
              expiryDateKnown: product.tracksExpiry && _expiryDateKnown,
              reference: _reference.text.trim(),
            ),
            branchId: branchId,
          );
      ref.invalidate(productDetailProvider((businessId, widget.productId)));
      ref.invalidate(productMovementsProvider((businessId, widget.productId)));
      ref.invalidate(productsListProvider(businessId));
      if (!mounted) return;
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock adjusted successfully.')),
      );
    } on ProductException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.friendlyMessage)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _selectExpiryDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 20, 12, 31),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _expiryDate = selected;
      _expiryDateKnown = true;
    });
  }
}
