import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../branches/application/current_branch_providers.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../application/customers_providers.dart';
import '../data/customers_repository.dart';
import '../domain/customer.dart';

class AddCustomerScreen extends ConsumerWidget {
  const AddCustomerScreen({super.key, this.returnToCheckout = false});

  final bool returnToCheckout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CustomerFormScaffold(
      mode: _Mode.create,
      returnToCheckout: returnToCheckout,
    );
  }
}

class EditCustomerScreen extends ConsumerWidget {
  const EditCustomerScreen({required this.customerId, super.key});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CustomerFormScaffold(mode: _Mode.edit, customerId: customerId);
  }
}

enum _Mode { create, edit }

class _CustomerFormScaffold extends ConsumerStatefulWidget {
  const _CustomerFormScaffold({
    required this.mode,
    this.customerId,
    this.returnToCheckout = false,
  });

  final _Mode mode;
  final String? customerId;
  final bool returnToCheckout;

  @override
  ConsumerState<_CustomerFormScaffold> createState() =>
      _CustomerFormScaffoldState();
}

class _CustomerFormScaffoldState extends ConsumerState<_CustomerFormScaffold> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  var _submitting = false;
  var _hydrated = false;
  var _usesWhatsApp = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _hydrate(Customer customer) {
    if (_hydrated) return;
    _hydrated = true;
    _name.text = customer.name;
    _phone.text = customer.phone ?? '';
    _email.text = customer.email ?? '';
    _address.text = customer.address ?? '';
    _notes.text = customer.notes ?? '';
    _usesWhatsApp = customer.usesWhatsApp;
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

    if (widget.mode == _Mode.edit) {
      final detail = ref.watch(
        customerDetailProvider((businessId, widget.customerId!)),
      );
      return detail.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => Scaffold(
          appBar: AppBar(title: const Text('Edit Customer')),
          body: const Center(child: Text('Could not load customer.')),
        ),
        data: (customer) {
          if (customer == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Edit Customer')),
              body: const Center(child: Text('Customer not found.')),
            );
          }
          _hydrate(customer);
          return _form(businessId);
        },
      );
    }
    return _form(businessId);
  }

  Widget _form(String businessId) {
    final isEdit = widget.mode == _Mode.edit;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Customer' : 'Add Customer')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: <Widget>[
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name *'),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if ((value ?? '').trim().length < 2) {
                    return 'Enter at least 2 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  final raw = (value ?? '').trim();
                  if (raw.isEmpty) return null;
                  if (raw.replaceAll(RegExp(r'\D'), '').length < 7) {
                    return 'Enter a valid phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  final raw = (value ?? '').trim();
                  if (raw.isEmpty) return null;
                  if (!raw.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Uses WhatsApp'),
                subtitle: const Text(
                  'Show the WhatsApp logo for this customer when messaging.',
                ),
                value: _usesWhatsApp,
                onChanged: (value) => setState(() => _usesWhatsApp = value),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : () => _submit(businessId),
                child: Text(
                  _submitting
                      ? 'Saving...'
                      : (isEdit ? 'Save changes' : 'Create customer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit(String businessId, {bool allowDuplicate = false}) async {
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
    final draft = CustomerDraft(
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      address: _address.text.trim(),
      notes: _notes.text.trim(),
      usesWhatsApp: _usesWhatsApp,
    );
    try {
      final repo = ref.read(customersRepositoryProvider);
      if (widget.mode == _Mode.create) {
        final id = await repo.createCustomer(
          businessId,
          draft,
          allowDuplicatePhone: allowDuplicate,
          branchId: branchId,
        );
        if (!mounted) return;
        if (widget.returnToCheckout) {
          context.pop(id);
        } else {
          context.goNamed(
            AppRouteNames.customerDetails,
            pathParameters: <String, String>{'customerId': id},
          );
        }
      } else {
        await repo.updateCustomer(
          businessId,
          widget.customerId!,
          draft,
          branchId: branchId,
        );
        if (!mounted) return;
        context.pop();
      }
    } on DuplicateCustomerException catch (error) {
      if (!mounted) return;
      final openExisting = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Customer already exists'),
          content: Text(
            'Another customer already uses this phone number: ${error.existing.name}.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open existing'),
            ),
          ],
        ),
      );
      if (openExisting == true && mounted) {
        context.goNamed(
          AppRouteNames.customerDetails,
          pathParameters: <String, String>{'customerId': error.existing.id},
        );
      }
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
