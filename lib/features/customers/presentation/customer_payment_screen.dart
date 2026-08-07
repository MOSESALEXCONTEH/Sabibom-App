import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/currency_formatter.dart';
import '../../branches/application/current_branch_providers.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../sales/domain/sale_models.dart';
import '../application/customers_providers.dart';
import '../data/customers_repository.dart';

class CustomerPaymentScreen extends ConsumerStatefulWidget {
  const CustomerPaymentScreen({required this.customerId, super.key});

  final String customerId;

  @override
  ConsumerState<CustomerPaymentScreen> createState() =>
      _CustomerPaymentScreenState();
}

class _CustomerPaymentScreenState extends ConsumerState<CustomerPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  var _method = 'cash';
  var _submitting = false;

  static const _methods = <(String, String)>[
    ('cash', 'Cash'),
    ('mobile_money', 'Mobile Money'),
    ('bank_transfer', 'Bank Transfer'),
    ('card', 'Card'),
    ('other', 'Other'),
  ];

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
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
      customerDetailProvider((businessId, widget.customerId)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Record Payment')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not load customer.')),
        data: (customer) {
          if (customer == null) {
            return const Center(child: Text('Customer not found.'));
          }
          return SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: <Widget>[
                  Text(
                    customer.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Outstanding: ${formatCurrency(minorToMoney(customer.balanceMinor), symbol: active.business.currency.symbol)}',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amount,
                    decoration: const InputDecoration(
                      labelText: 'Amount (Le) *',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) {
                      final amount = double.tryParse((value ?? '').trim());
                      if (amount == null || amount <= 0) {
                        return 'Enter a valid amount';
                      }
                      if (moneyToMinor(amount) > customer.balanceMinor) {
                        return 'Amount cannot exceed the outstanding balance';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _method,
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                    ),
                    items: _methods
                        .map(
                          (method) => DropdownMenuItem<String>(
                            value: method.$1,
                            child: Text(method.$2),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _method = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _reference,
                    decoration: const InputDecoration(
                      labelText: 'Reference (optional)',
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
                    onPressed: _submitting ? null : () => _submit(businessId),
                    child: Text(_submitting ? 'Saving...' : 'Record payment'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _submit(String businessId) async {
    if (!_formKey.currentState!.validate()) return;
    final branchId = ref.read(currentWritableBranchIdProvider);
    if (branchId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(branchWriteBlockedMessage)),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(customersRepositoryProvider)
          .recordPayment(
            businessId,
            CustomerPaymentRequest(
              customerId: widget.customerId,
              amountMinor: moneyToMinor(_amount.text.trim()),
              paymentMethod: _method,
              reference: _reference.text.trim(),
              note: _note.text.trim(),
            ),
            branchId: branchId,
          );
      ref.invalidate(customerDetailProvider((businessId, widget.customerId)));
      ref.invalidate(customerLedgerProvider((businessId, widget.customerId)));
      ref.invalidate(customersListProvider(businessId));
      if (!mounted) return;
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment recorded successfully.')),
      );
    } on CustomerException catch (error) {
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
}
