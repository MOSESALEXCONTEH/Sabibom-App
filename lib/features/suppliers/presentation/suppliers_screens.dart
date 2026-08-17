import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/formatting/currency_formatter.dart';
import '../../../core/sync/record_sync_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/widgets/app_list_primitives.dart';
import '../../../core/widgets/app_scroll_padding.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../../core/widgets/app_tab_page_scaffold.dart';
import '../../../core/widgets/list_bulk_actions.dart';
import '../../branches/application/current_branch_providers.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../sales/domain/sale_models.dart';
import '../application/suppliers_providers.dart';
import '../data/suppliers_repository.dart';
import '../domain/supplier.dart';

class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  var _query = '';
  var _filter = SupplierListFilter.all;
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
      title: _selectionMode ? '${_selected.length} selected' : 'Suppliers',
      subtitle: _selectionMode
          ? 'Swipe left or select suppliers to archive'
          : 'Vendors, balances and purchase history',
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
              onPressed: () => context.pushNamed(AppRouteNames.newSupplier),
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Add Supplier'),
            )
          : null,
      body: active.when(
        loading: () => const AppListSkeleton(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        ),
        error: (_, _) => const AppErrorState(
          title: 'Unable to load suppliers',
          message: 'Something went wrong. Please try again.',
        ),
        data: (state) => switch (state) {
          ActiveBusinessData(:final business) => _SuppliersBody(
            businessId: business.businessId,
            currencySymbol: business.currency.symbol,
            query: _query,
            filter: _filter,
            selectionMode: _selectionMode,
            selectedIds: _selected,
            onQueryChanged: (value) => setState(() => _query = value),
            onFilterChanged: (value) => setState(() => _filter = value),
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
          ActiveBusinessNone() => AppEmptyState(
            title: 'Set up your business',
            description: 'Create a business profile before adding suppliers.',
            icon: Icons.storefront_outlined,
            actionLabel: 'Set Up Business',
            onAction: () => context.push(AppRoutes.businessSetup),
          ),
          ActiveBusinessFailure(:final message) => AppErrorState(
            title: 'Unable to load suppliers',
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
      title: 'Archive ${_selected.length} suppliers?',
      message: 'Selected suppliers will be archived.',
      confirmLabel: 'Archive',
    );
    if (!ok) return;
    final repo = ref.read(suppliersRepositoryProvider);
    var count = 0;
    for (final id in _selected.toList()) {
      try {
        await repo.archiveSupplier(businessId, id);
        count++;
      } catch (_) {}
    }
    ref.invalidate(suppliersListProvider(businessId));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Archived $count suppliers.')));
    _clearSelection();
  }
}

class _SuppliersBody extends ConsumerWidget {
  const _SuppliersBody({
    required this.businessId,
    required this.currencySymbol,
    required this.query,
    required this.filter,
    required this.selectionMode,
    required this.selectedIds,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onVisibleIds,
    required this.onToggleSelected,
    required this.onEnterSelection,
  });

  final String businessId;
  final String currencySymbol;
  final String query;
  final SupplierListFilter filter;
  final bool selectionMode;
  final Set<String> selectedIds;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<SupplierListFilter> onFilterChanged;
  final ValueChanged<List<String>> onVisibleIds;
  final ValueChanged<String> onToggleSelected;
  final ValueChanged<String> onEnterSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersListProvider(businessId));
    return suppliers.when(
      loading: () => const AppListSkeleton(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      ),
      error: (_, _) => AppErrorState(
        message: 'Could not load suppliers.',
        onRetry: () => ref.invalidate(suppliersListProvider(businessId)),
      ),
      data: (items) {
        final visible = filterSuppliers(
          suppliers: items,
          query: query,
          filter: filter,
        );
        onVisibleIds(
          visible
              .where((s) => s.isActive)
              .map((s) => s.id)
              .toList(growable: false),
        );
        final active = items.where((supplier) => supplier.isActive).toList();
        final owing = active.fold<int>(
          0,
          (sum, supplier) => sum + supplier.balanceMinor,
        );
        final withBalance = active
            .where((supplier) => supplier.hasBalance)
            .length;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${active.length} active · $withBalance with balance · ${formatCurrency(minorToMoney(owing), symbol: currencySymbol)} owed',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              if (items.isEmpty)
                Expanded(
                  child: AppEmptyState(
                    title: 'No suppliers yet',
                    description:
                        'Save supplier details to track purchases, debts and payments.',
                    icon: Icons.local_shipping_outlined,
                    actionLabel: 'Add Supplier',
                    actionIcon: Icons.add_business_outlined,
                    onAction: () =>
                        context.pushNamed(AppRouteNames.newSupplier),
                  ),
                )
              else ...<Widget>[
                TextField(
                  onChanged: onQueryChanged,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search name, contact or phone',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm + 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: SupplierListFilter.values
                        .map(
                          (value) => Padding(
                            padding: const EdgeInsets.only(
                              right: AppSpacing.sm,
                            ),
                            child: ChoiceChip(
                              label: Text(_filterLabel(value)),
                              selected: value == filter,
                              onSelected: (_) => onFilterChanged(value),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm + 4),
                Expanded(
                  child: visible.isEmpty
                      ? const AppEmptyState(
                          title: 'No matches',
                          description: 'No suppliers match your filters.',
                          icon: Icons.filter_alt_off_outlined,
                        )
                      : RefreshIndicator(
                          onRefresh: () async =>
                              ref.invalidate(suppliersListProvider(businessId)),
                          child: ListView.separated(
                            padding: const EdgeInsets.only(
                              bottom: AppTabChrome.bottomInset,
                            ),
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              final supplier = visible[index];
                              final tile = AppListRow(
                                onTap: () => context.pushNamed(
                                  AppRouteNames.supplierDetails,
                                  pathParameters: <String, String>{
                                    'supplierId': supplier.id,
                                  },
                                ),
                                leading: AppListAvatar(
                                  label: supplier.initials,
                                ),
                                title: supplier.name,
                                subtitle: <String>[
                                  if (supplier.contactPerson?.isNotEmpty ==
                                      true)
                                    supplier.contactPerson!,
                                  if (supplier.phone?.isNotEmpty == true)
                                    supplier.phone!,
                                  '${supplier.purchaseCount} purchases',
                                ].join(' · '),
                                trailing: SizedBox(
                                  width: 104,
                                  child: Text(
                                    formatCurrency(
                                      minorToMoney(supplier.balanceMinor),
                                      symbol: currencySymbol,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                      color: supplier.hasBalance
                                          ? AppColors.warning
                                          : null,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              );
                              return SelectableDismissibleTile(
                                id: supplier.id,
                                selectionMode: selectionMode,
                                selected: selectedIds.contains(supplier.id),
                                onToggleSelected: onToggleSelected,
                                enabled: supplier.isActive,
                                dismissLabel: 'Archive',
                                confirmTitle: 'Archive supplier?',
                                confirmMessage:
                                    '“${supplier.name}” will be archived.',
                                confirmLabel: 'Archive',
                                onDismissed: (id) async {
                                  try {
                                    await ref
                                        .read(suppliersRepositoryProvider)
                                        .archiveSupplier(businessId, id);
                                    ref.invalidate(
                                      suppliersListProvider(businessId),
                                    );
                                    return true;
                                  } catch (_) {
                                    return false;
                                  }
                                },
                                child: GestureDetector(
                                  onLongPress: supplier.isActive
                                      ? () => onEnterSelection(supplier.id)
                                      : null,
                                  child: tile,
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _filterLabel(SupplierListFilter filter) => switch (filter) {
    SupplierListFilter.all => 'All',
    SupplierListFilter.active => 'Active',
    SupplierListFilter.hasBalance => 'Has Balance',
    SupplierListFilter.archived => 'Archived',
  };
}

class SupplierFormScreen extends ConsumerStatefulWidget {
  const SupplierFormScreen({
    super.key,
    this.supplierId,
    this.initialName,
    this.initialPhone,
  });

  final String? supplierId;
  final String? initialName;
  final String? initialPhone;

  @override
  ConsumerState<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends ConsumerState<SupplierFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _products = TextEditingController();
  final _notes = TextEditingController();
  var _hydrated = false;
  var _saving = false;

  bool get _editing => widget.supplierId?.trim().isNotEmpty == true;

  @override
  void initState() {
    super.initState();
    if (!_editing) {
      if (widget.initialName?.trim().isNotEmpty == true) {
        _name.text = widget.initialName!.trim();
      }
      if (widget.initialPhone?.trim().isNotEmpty == true) {
        _phone.text = widget.initialPhone!.trim();
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _products.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _hydrate(Supplier supplier) {
    if (_hydrated) return;
    _hydrated = true;
    _name.text = supplier.name;
    _contact.text = supplier.contactPerson ?? '';
    _phone.text = supplier.phone ?? '';
    _email.text = supplier.email ?? '';
    _address.text = supplier.address ?? '';
    _products.text = supplier.productsSupplied.join(', ');
    _notes.text = supplier.notes ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final business = ref.watch(activeBusinessProvider).asData?.value;
    if (business is! ActiveBusinessData) {
      return const Scaffold(
        body: Center(child: Text('Set up or select a business to continue.')),
      );
    }
    if (!_editing) return _form(business.business.businessId);
    final detail = ref.watch(
      supplierDetailProvider((
        business.business.businessId,
        widget.supplierId!,
      )),
    );
    return detail.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('Edit Supplier')),
        body: const Center(child: Text('Could not load supplier.')),
      ),
      data: (supplier) {
        if (supplier == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Edit Supplier')),
            body: const Center(child: Text('Supplier not found.')),
          );
        }
        _hydrate(supplier);
        return _form(business.business.businessId);
      },
    );
  }

  Widget _form(String businessId) => Scaffold(
    appBar: AppBar(title: Text(_editing ? 'Edit Supplier' : 'Add Supplier')),
    body: SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: appSafeScrollPadding(context, left: 20, top: 12, right: 20),
          children: <Widget>[
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Supplier name *'),
              textCapitalization: TextCapitalization.words,
              validator: (value) => (value ?? '').trim().length < 2
                  ? 'Enter at least 2 characters'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contact,
              decoration: const InputDecoration(labelText: 'Contact person'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                final raw = (value ?? '').trim();
                return raw.isNotEmpty && !raw.contains('@')
                    ? 'Enter a valid email'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _products,
              decoration: const InputDecoration(
                labelText: 'Products supplied',
                hintText: 'Rice, drinks, packaging',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : () => _save(businessId),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text(
                _saving
                    ? 'Saving...'
                    : (_editing ? 'Save changes' : 'Create supplier'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  SupplierDraft get _draft => SupplierDraft(
    name: _name.text,
    contactPerson: _contact.text,
    phone: _phone.text,
    email: _email.text,
    address: _address.text,
    productsSupplied: _products.text.split(','),
    notes: _notes.text,
  );

  Future<void> _save(String businessId) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(suppliersRepositoryProvider);
      if (_editing) {
        await repo.updateSupplier(businessId, widget.supplierId!, _draft);
        ref.invalidate(
          supplierDetailProvider((businessId, widget.supplierId!)),
        );
        ref.invalidate(suppliersListProvider(businessId));
        if (mounted) context.pop();
      } else {
        final isOnline = ref.read(isOnlineProvider).asData?.value ?? true;
        final id = await repo.createSupplier(
          businessId,
          _draft,
          queueWhenOffline: !isOnline,
        );
        if (mounted) {
          if (!isOnline) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Supplier saved. Waiting to sync.')),
            );
          }
          context.goNamed(
            AppRouteNames.supplierDetails,
            pathParameters: <String, String>{'supplierId': id},
          );
        }
      }
    } on DuplicateSupplierException catch (error) {
      if (!mounted) return;
      final openExisting = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Supplier already exists'),
          content: Text(
            '${error.existing.name} already uses this phone number.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open supplier'),
            ),
          ],
        ),
      );
      if (openExisting == true && mounted) {
        context.goNamed(
          AppRouteNames.supplierDetails,
          pathParameters: <String, String>{'supplierId': error.existing.id},
        );
      }
    } on SupplierException catch (error) {
      _show(error.userMessage);
    } catch (_) {
      final requestId =
          'supplier-form-${DateTime.now().microsecondsSinceEpoch}';
      debugPrint('Supplier form failed: requestId=$requestId');
      _show('The supplier could not be saved. Ref: $requestId');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _show(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class SupplierDetailsScreen extends ConsumerWidget {
  const SupplierDetailsScreen({required this.supplierId, super.key});

  final String supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) {
      return const Scaffold(
        body: Center(child: Text('Set up or select a business to continue.')),
      );
    }
    final businessId = active.business.businessId;
    final detail = ref.watch(supplierDetailProvider((businessId, supplierId)));
    final ledger = ref.watch(supplierLedgerProvider((businessId, supplierId)));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supplier Details'),
        actions: <Widget>[
          RecordSyncStatusIcon(
            request: RecordSyncRequest(
              businessId: businessId,
              collection: 'suppliers',
              recordId: supplierId,
            ),
          ),
          IconButton(
            onPressed: () => context.pushNamed(
              AppRouteNames.editSupplier,
              pathParameters: <String, String>{'supplierId': supplierId},
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not load supplier.')),
        data: (supplier) {
          if (supplier == null) {
            return const Center(child: Text('Supplier not found.'));
          }
          final symbol = active.business.currency.symbol;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              20,
              12,
              20,
              AppTabChrome.bottomInset,
            ),
            children: <Widget>[
              Text(
                supplier.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (supplier.contactPerson?.isNotEmpty == true)
                Text('Contact: ${supplier.contactPerson}'),
              if (supplier.phone?.isNotEmpty == true) Text(supplier.phone!),
              if (supplier.email?.isNotEmpty == true) Text(supplier.email!),
              if (supplier.address?.isNotEmpty == true) Text(supplier.address!),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: <Widget>[
                      _DetailRow(
                        'Outstanding balance',
                        _currency(supplier.balanceMinor, symbol),
                      ),
                      _DetailRow(
                        'Total purchases',
                        _currency(supplier.totalPurchasesMinor, symbol),
                      ),
                      _DetailRow(
                        'Total paid',
                        _currency(supplier.totalPaidMinor, symbol),
                      ),
                      _DetailRow('Purchases', '${supplier.purchaseCount}'),
                      _DetailRow(
                        'Last purchase',
                        supplier.lastPurchaseAt == null
                            ? '—'
                            : DateFormat.yMMMd().format(
                                supplier.lastPurchaseAt!,
                              ),
                      ),
                      if (supplier.productsSupplied.isNotEmpty)
                        _DetailRow(
                          'Products',
                          supplier.productsSupplied.join(', '),
                        ),
                      if (supplier.notes?.isNotEmpty == true)
                        _DetailRow('Notes', supplier.notes!),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.pushNamed(
                  AppRouteNames.editSupplier,
                  pathParameters: <String, String>{'supplierId': supplier.id},
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit Supplier'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: supplier.isArchived
                    ? null
                    : () => context.pushNamed(
                        AppRouteNames.newPurchase,
                        queryParameters: <String, String>{
                          'supplierId': supplier.id,
                        },
                      ),
                icon: const Icon(Icons.add_shopping_cart_outlined),
                label: const Text('New Purchase'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: supplier.hasBalance
                    ? () => context.pushNamed(
                        AppRouteNames.supplierPayment,
                        pathParameters: <String, String>{
                          'supplierId': supplier.id,
                        },
                      )
                    : null,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Record Payment'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: supplier.isArchived
                    ? null
                    : () => _archive(context, ref, businessId, supplier),
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archive Supplier'),
              ),
              const SizedBox(height: 20),
              Text(
                'Payment history',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ledger.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const Text('Could not load payment history.'),
                data: (entries) => entries.isEmpty
                    ? const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No ledger entries yet.'),
                        ),
                      )
                    : Card(
                        child: Column(
                          children: entries
                              .map(
                                (entry) => ListTile(
                                  title: Text(entry.type.label),
                                  subtitle: Text(
                                    entry.paymentDate == null
                                        ? 'Balance ${_currency(entry.balanceAfterMinor, symbol)}'
                                        : DateFormat.yMMMd().format(
                                            entry.paymentDate!,
                                          ),
                                  ),
                                  trailing: Text(
                                    entry.creditMinor > 0
                                        ? '-${_currency(entry.creditMinor, symbol)}'
                                        : _currency(entry.debitMinor, symbol),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    String businessId,
    Supplier supplier,
  ) async {
    try {
      await ref
          .read(suppliersRepositoryProvider)
          .archiveSupplier(businessId, supplier.id);
      ref.invalidate(supplierDetailProvider((businessId, supplier.id)));
      ref.invalidate(suppliersListProvider(businessId));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Supplier archived.')));
      }
    } on SupplierException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.userMessage)));
      }
    }
  }
}

class SupplierPaymentScreen extends ConsumerStatefulWidget {
  const SupplierPaymentScreen({required this.supplierId, super.key});

  final String supplierId;

  @override
  ConsumerState<SupplierPaymentScreen> createState() =>
      _SupplierPaymentScreenState();
}

class _SupplierPaymentScreenState extends ConsumerState<SupplierPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  var _method = 'cash';
  var _paymentDate = DateTime.now();
  var _saving = false;

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
      supplierDetailProvider((businessId, widget.supplierId)),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Record Supplier Payment')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not load supplier.')),
        data: (supplier) {
          if (supplier == null) {
            return const Center(child: Text('Supplier not found.'));
          }
          final amountMinor = moneyToMinor(_amount.text);
          final newBalance = (supplier.balanceMinor - amountMinor)
              .clamp(0, supplier.balanceMinor)
              .toInt();
          final symbol = active.business.currency.symbol;
          return Form(
            key: _formKey,
            child: ListView(
              padding: appSafeScrollPadding(
                context,
                left: 20,
                top: 12,
                right: 20,
              ),
              children: <Widget>[
                Text(
                  supplier.name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Current balance: ${_currency(supplier.balanceMinor, symbol)}',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amount,
                  decoration: const InputDecoration(labelText: 'Amount (Le) *'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final amount = moneyToMinor(value);
                    if (amount <= 0) return 'Enter a valid amount';
                    if (amount > supplier.balanceMinor) {
                      return 'Amount cannot exceed the outstanding balance';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'New balance: ${_currency(newBalance, symbol)}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _method,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                  ),
                  items: _methods
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.$1,
                          child: Text(item.$2),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _method = value);
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Payment date'),
                  subtitle: Text(DateFormat.yMMMd().format(_paymentDate)),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: _pickDate,
                ),
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
                  onPressed: _saving
                      ? null
                      : () => _submit(businessId, supplier, symbol),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: Text(_saving ? 'Saving...' : 'Confirm payment'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null && mounted) setState(() => _paymentDate = date);
  }

  Future<void> _submit(
    String businessId,
    Supplier supplier,
    String currencySymbol,
  ) async {
    if (!_formKey.currentState!.validate()) return;
    final branchId = ref.read(currentWritableBranchIdProvider);
    if (branchId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(branchWriteBlockedMessage)));
      return;
    }
    final amountMinor = moneyToMinor(_amount.text);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm payment'),
        content: Text(
          'Record ${_currency(amountMinor, currencySymbol)} for ${supplier.name}?\n\nNew balance: ${_currency(supplier.balanceMinor - amountMinor, currencySymbol)}',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(suppliersRepositoryProvider)
          .recordPayment(
            businessId,
            widget.supplierId,
            amountMinor,
            _method,
            _paymentDate,
            _reference.text,
            _note.text,
            branchId: branchId,
          );
      ref.invalidate(supplierDetailProvider((businessId, widget.supplierId)));
      ref.invalidate(supplierLedgerProvider((businessId, widget.supplierId)));
      ref.invalidate(suppliersListProvider(businessId));
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supplier payment recorded.')),
        );
      }
    } on SupplierException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.userMessage)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 130,
          child: Text(label, style: TextStyle(color: context.mutedTextColor)),
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

String _currency(int amountMinor, String symbol) =>
    formatCurrency(minorToMoney(amountMinor), symbol: symbol);
