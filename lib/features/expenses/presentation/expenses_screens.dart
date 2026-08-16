import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/router.dart';
import '../../../core/formatting/currency_formatter.dart';
import '../../../core/formatting/record_date_filter.dart';
import '../../../core/sync/record_sync_status.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/image_compression_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../../core/widgets/app_tab_page_scaffold.dart';
import '../../../core/widgets/list_bulk_actions.dart';
import '../../branches/application/current_branch_providers.dart';
import '../../business_profile/services/pinata_upload_service.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../sales/domain/sale_models.dart';
import '../application/expenses_providers.dart';
import '../domain/expense.dart';
import '../domain/expense_category.dart';

IconData expenseCategoryIcon(String name) => switch (name) {
  'home' => Icons.home_outlined,
  'bolt' => Icons.bolt_outlined,
  'water_drop' => Icons.water_drop_outlined,
  'wifi' => Icons.wifi,
  'directions_car' => Icons.directions_car_outlined,
  'badge' => Icons.badge_outlined,
  'build' => Icons.build_outlined,
  'campaign' => Icons.campaign_outlined,
  'account_balance' => Icons.account_balance_outlined,
  'inventory_2' => Icons.inventory_2_outlined,
  'shopping_bag' => Icons.shopping_bag_outlined,
  'more_horiz' => Icons.more_horiz,
  _ => Icons.payments_outlined,
};

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  ExpensePeriod _period = ExpensePeriod.all;
  String? _categoryId;
  ExpensePaymentMethod? _paymentMethod;
  final _search = TextEditingController();
  var _seeded = false;
  var _selectionMode = false;
  final Set<String> _selected = <String>{};
  List<String> _visibleIds = const [];

  void _clearSelection() => setState(() {
    _selectionMode = false;
    _selected.clear();
  });

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _ensureSeed(String businessId) async {
    if (_seeded) return;
    _seeded = true;
    try {
      await ref
          .read(expenseCategoriesRepositoryProvider)
          .ensureDefaults(businessId);
    } catch (_) {}
  }

  Future<void> _bulkVoid(String businessId) async {
    if (_selected.isEmpty) return;
    final branchId = ref.read(currentWritableBranchIdProvider);
    if (branchId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(branchWriteBlockedMessage)));
      return;
    }
    final ok = await confirmListDelete(
      context,
      title: 'Void ${_selected.length} expenses?',
      message: 'Selected expenses will be voided.',
      confirmLabel: 'Void',
    );
    if (!ok) return;
    final repo = ref.read(expensesRepositoryProvider);
    var count = 0;
    for (final id in _selected.toList()) {
      try {
        await repo.voidExpense(
          businessId,
          id,
          reason: 'Removed from expenses list',
          branchId: branchId,
        );
        count++;
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Voided $count expenses.')));
    _clearSelection();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBusinessProvider);
    return active.when(
      data: (state) {
        if (state is ActiveBusinessNone) {
          return Scaffold(
            appBar: AppBar(title: const Text('Expenses')),
            body: _NoBusinessBody(
              onSetup: () => context.push(AppRoutes.businessSetup),
            ),
          );
        }
        if (state is! ActiveBusinessData) {
          return const Scaffold(
            body: AppListSkeleton(padding: EdgeInsets.all(AppSpacing.md)),
          );
        }
        final business = state.business;
        _ensureSeed(business.businessId);
        final range = expensePeriodRange(_period);
        final repo = ref.read(expensesRepositoryProvider);
        final branchId = ref.watch(currentBranchReadScopeProvider);

        return Scaffold(
          appBar: AppBar(
            title: Text(
              _selectionMode ? '${_selected.length} selected' : 'Expenses',
            ),
            actions: <Widget>[
              if (!_selectionMode)
                IconButton(
                  tooltip: 'Categories',
                  onPressed: () =>
                      context.pushNamed(AppRouteNames.expenseCategories),
                  icon: const Icon(Icons.category_outlined),
                ),
              ...bulkSelectActions(
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
                onDeleteSelected: () => _bulkVoid(business.businessId),
                deleteTooltip: 'Void selected',
              ),
            ],
          ),
          floatingActionButton: _selectionMode
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => context.pushNamed(AppRouteNames.newExpense),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Expense'),
                ),
          body: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search expenses',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: ExpensePeriod.values
                      .where((p) => p != ExpensePeriod.custom)
                      .map((p) {
                        final selected = _period == p;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(switch (p) {
                              ExpensePeriod.all => 'All',
                              ExpensePeriod.today => 'Today',
                              ExpensePeriod.yesterday => 'Yesterday',
                              ExpensePeriod.last7Days => 'Last 7 days',
                              ExpensePeriod.last30Days => 'Last 30 days',
                              ExpensePeriod.thisWeek => 'This Week',
                              ExpensePeriod.thisMonth => 'This Month',
                              ExpensePeriod.thisYear => 'This Year',
                              ExpensePeriod.lastYear => 'Last Year',
                              ExpensePeriod.custom => 'Custom',
                            }),
                            selected: selected,
                            onSelected: (_) => setState(() => _period = p),
                          ),
                        );
                      })
                      .toList(),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Expense>>(
                  stream: repo.watchExpenses(
                    business.businessId,
                    start: range.start,
                    end: range.end,
                    branchId: branchId,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('${snapshot.error}'));
                    }
                    if (!snapshot.hasData) {
                      return const AppListSkeleton(
                        padding: EdgeInsets.all(AppSpacing.md),
                      );
                    }
                    final expenses = snapshot.data!;
                    final q = _search.text.trim().toLowerCase();
                    final filtered = expenses.where((e) {
                      if (_categoryId != null && e.categoryId != _categoryId) {
                        return false;
                      }
                      if (_paymentMethod != null &&
                          e.paymentMethod != _paymentMethod) {
                        return false;
                      }
                      if (q.isEmpty) return true;
                      return e.expenseNumber.toLowerCase().contains(q) ||
                          e.description.toLowerCase().contains(q) ||
                          e.categoryName.toLowerCase().contains(q) ||
                          (e.supplierName?.toLowerCase().contains(q) ??
                              false) ||
                          (e.paymentReference?.toLowerCase().contains(q) ??
                              false);
                    }).toList();
                    final totalMinor = filtered
                        .where((e) => !e.isVoided)
                        .fold<int>(0, (s, e) => s + e.amountMinor);
                    final voidableIds = filtered
                        .where((e) => !e.isVoided)
                        .map((e) => e.id)
                        .toList(growable: false);
                    if (voidableIds.length != _visibleIds.length ||
                        !_visibleIds.every(voidableIds.contains)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() => _visibleIds = voidableIds);
                        }
                      });
                    }
                    if (filtered.isEmpty) {
                      return _EmptyExpenses(
                        onAdd: () =>
                            context.pushNamed(AppRouteNames.newExpense),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm + 4,
                        AppSpacing.md,
                        AppTabChrome.bottomInset,
                      ),
                      itemCount: filtered.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Card(
                            child: ListTile(
                              title: const Text('Total expenses'),
                              subtitle: Text(
                                '${filtered.where((e) => !e.isVoided).length} active',
                              ),
                              trailing: SizedBox(
                                width: 120,
                                child: Text(
                                  formatCurrency(
                                    minorToMoney(totalMinor),
                                    symbol: business.currency.symbol,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                        final expense = filtered[index - 1];
                        final tile = Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(
                                0xFF5B3DF5,
                              ).withValues(alpha: 0.12),
                              child: Icon(
                                expenseCategoryIcon('payments'),
                                color: const Color(0xFF5B3DF5),
                              ),
                            ),
                            title: Text(
                              expense.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                expense.expenseNumber,
                                expense.categoryName,
                                formatRecordDateTime(expense.expenseDate),
                                expense.paymentMethod.label,
                                if (expense.supplierName != null)
                                  expense.supplierName!,
                                if (expense.isVoided) 'VOIDED',
                              ].join(' · '),
                              maxLines: 2,
                            ),
                            trailing: SizedBox(
                              width: 104,
                              child: Text(
                                formatCurrency(
                                  expense.amount,
                                  symbol: business.currency.symbol,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  decoration: expense.isVoided
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: expense.isVoided
                                      ? Theme.of(context).disabledColor
                                      : null,
                                ),
                              ),
                            ),
                            onTap: () => context.pushNamed(
                              AppRouteNames.expenseDetails,
                              pathParameters: {'expenseId': expense.id},
                            ),
                          ),
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SelectableDismissibleTile(
                            id: expense.id,
                            selectionMode: _selectionMode,
                            selected: _selected.contains(expense.id),
                            onToggleSelected: (id) => setState(() {
                              if (_selected.contains(id)) {
                                _selected.remove(id);
                              } else {
                                _selected.add(id);
                              }
                            }),
                            enabled: !expense.isVoided,
                            dismissLabel: 'Void',
                            confirmTitle: 'Void expense?',
                            confirmMessage:
                                '“${expense.description}” will be voided.',
                            confirmLabel: 'Void',
                            onDismissed: (id) async {
                              try {
                                await ref
                                    .read(expensesRepositoryProvider)
                                    .voidExpense(
                                      business.businessId,
                                      id,
                                      reason: 'Removed from expenses list',
                                    );
                                return true;
                              } catch (_) {
                                return false;
                              }
                            },
                            child: GestureDetector(
                              onLongPress: expense.isVoided
                                  ? null
                                  : () => setState(() {
                                      _selectionMode = true;
                                      _selected.add(expense.id);
                                    }),
                              child: tile,
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
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => const Scaffold(
        body: AppErrorState(
          message:
              'Could not load expenses. Check your connection and try again.',
        ),
      ),
    );
  }
}

class _EmptyExpenses extends StatelessWidget {
  const _EmptyExpenses({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      title: 'No expenses yet',
      description: 'Record business expenses to understand your true profit.',
      icon: Icons.payments_outlined,
      actionLabel: 'Add Expense',
      actionIcon: Icons.add,
      onAction: onAdd,
    );
  }
}

class _NoBusinessBody extends StatelessWidget {
  const _NoBusinessBody({required this.onSetup});
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      title: 'Set up your business first',
      description:
          'Create or select a business before managing expenses, suppliers and purchases.',
      icon: Icons.storefront_outlined,
      actionLabel: 'Set Up Business',
      onAction: onSetup,
    );
  }
}

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({
    super.key,
    this.expenseId,
    this.initialAmount,
    this.initialDescription,
    this.initialCategoryName,
  });

  final String? expenseId;
  final String? initialAmount;
  final String? initialDescription;
  final String? initialCategoryName;

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  ExpensePaymentMethod _payment = ExpensePaymentMethod.cash;
  ExpenseCategory? _category;
  DateTime _date = DateTime.now();
  String? _attachmentUrl;
  String? _attachmentCid;
  String? _attachmentFileName;
  var _saving = false;
  var _uploading = false;
  var _hydrated = false;

  @override
  void initState() {
    super.initState();
    if (widget.expenseId == null) {
      if (widget.initialAmount != null) {
        _amount.text = widget.initialAmount!;
      }
      if (widget.initialDescription != null) {
        _description.text = widget.initialDescription!;
      }
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment(String businessId) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final compressed = await ImageCompressionService().prepareLogo(
        sourceBytes: bytes,
        fileName: file.name,
      );
      final uploaded = await ref
          .read(pinataUploadServiceProvider)
          .uploadExpenseReceipt(businessId: businessId, image: compressed);
      if (!mounted) return;
      setState(() {
        _attachmentUrl = uploaded.logoUrl;
        _attachmentCid = uploaded.cid;
        _attachmentFileName = uploaded.fileName;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save(String businessId, String currencyCode) async {
    if (_saving) return;
    final branchId = ref.read(currentWritableBranchIdProvider);
    if (branchId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(branchWriteBlockedMessage)));
      return;
    }
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid amount greater than zero.'),
        ),
      );
      return;
    }
    if (_category == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a category.')));
      return;
    }
    if (_description.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Description must be at least 2 characters.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final draft = ExpenseDraft(
      amountMinor: moneyToMinor(amount),
      categoryId: _category!.id,
      categoryName: _category!.name,
      description: _description.text.trim(),
      paymentMethod: _payment,
      expenseDate: _date,
      paymentReference: _reference.text.trim().isEmpty
          ? null
          : _reference.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      attachmentUrl: _attachmentUrl,
      attachmentCid: _attachmentCid,
      attachmentFileName: _attachmentFileName,
      currencyCode: currencyCode,
    );
    try {
      final repo = ref.read(expensesRepositoryProvider);
      if (widget.expenseId == null) {
        final isOnline = ref.read(isOnlineProvider).asData?.value ?? true;
        final id = await repo.createExpense(
          businessId,
          draft,
          branchId: branchId,
          queueWhenOffline: !isOnline,
        );
        if (!mounted) return;
        if (!isOnline) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Expense saved. Waiting to sync.')),
          );
        }
        context.goNamed(
          AppRouteNames.expenseDetails,
          pathParameters: {'expenseId': id},
        );
      } else {
        await repo.updateExpense(
          businessId,
          widget.expenseId!,
          draft,
          branchId: branchId,
        );
        if (!mounted) return;
        context.pop();
      }
    } on ExpenseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.userMessage)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) {
      return const Scaffold(body: Center(child: Text('No business selected.')));
    }
    final businessId = active.business.businessId;
    final categoriesStream = ref
        .read(expenseCategoriesRepositoryProvider)
        .watchCategories(businessId);

    if (widget.expenseId != null && !_hydrated) {
      ref
          .read(expensesRepositoryProvider)
          .getExpense(businessId, widget.expenseId!)
          .then((expense) {
            if (!mounted || expense == null) return;
            setState(() {
              _hydrated = true;
              _amount.text = expense.amount.toStringAsFixed(2);
              _description.text = expense.description;
              _reference.text = expense.paymentReference ?? '';
              _notes.text = expense.notes ?? '';
              _payment = expense.paymentMethod;
              _date = expense.expenseDate;
              _attachmentUrl = expense.attachmentUrl;
              _attachmentCid = expense.attachmentCid;
              _attachmentFileName = expense.attachmentFileName;
              _category = ExpenseCategory(
                id: expense.categoryId,
                businessId: businessId,
                name: expense.categoryName,
              );
            });
          });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.expenseId == null ? 'Add Expense' : 'Edit Expense'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: <Widget>[
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: 'Amount (${active.business.currency.symbol})',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<ExpenseCategory>>(
            stream: categoriesStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final list = snapshot.data!;
              return DropdownButtonFormField<String>(
                initialValue: _category?.id,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: list
                    .map(
                      (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                    )
                    .toList(),
                onChanged: (id) {
                  final match = list.where((c) => c.id == id).firstOrNull;
                  setState(() => _category = match);
                },
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ExpensePaymentMethod>(
            initialValue: _payment,
            decoration: const InputDecoration(
              labelText: 'Payment method',
              border: OutlineInputBorder(),
            ),
            items: ExpensePaymentMethod.values
                .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                .toList(),
            onChanged: (m) => setState(() => _payment = m ?? _payment),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reference,
            decoration: const InputDecoration(
              labelText: 'Payment reference (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Expense date'),
            subtitle: Text(DateFormat.yMMMd().format(_date)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _uploading || _saving
                ? null
                : () => _pickAttachment(businessId),
            icon: _uploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.attach_file),
            label: Text(
              _attachmentUrl == null
                  ? 'Attach receipt image'
                  : 'Receipt attached',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving || _uploading
                ? null
                : () => _save(businessId, active.business.currency.code),
            child: Text(_saving ? 'Saving…' : 'Save Expense'),
          ),
        ],
      ),
    );
  }
}

class ExpenseDetailsScreen extends ConsumerWidget {
  const ExpenseDetailsScreen({super.key, required this.expenseId});

  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) {
      return const Scaffold(body: Center(child: Text('No business selected.')));
    }
    final businessId = active.business.businessId;
    final symbol = active.business.currency.symbol;

    return FutureBuilder<Expense?>(
      future: ref
          .read(expensesRepositoryProvider)
          .getExpense(businessId, expenseId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Text('${snapshot.error}')));
        }
        final expense = snapshot.data;
        if (expense == null) {
          return const Scaffold(
            body: Center(child: Text('Expense not found.')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(expense.expenseNumber),
            actions: <Widget>[
              RecordSyncStatusIcon(
                request: RecordSyncRequest(
                  businessId: businessId,
                  collection: 'expenses',
                  recordId: expense.id,
                ),
              ),
              if (!expense.isVoided)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => context.pushNamed(
                    AppRouteNames.editExpense,
                    pathParameters: {'expenseId': expense.id},
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: () {
                  SharePlus.instance.share(
                    ShareParams(
                      text:
                          '${expense.expenseNumber}\n${expense.description}\n'
                          '${formatCurrency(expense.amount, symbol: symbol)}\n'
                          '${expense.categoryName} · ${expense.paymentMethod.label}',
                    ),
                  );
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppTabChrome.bottomInset,
            ),
            children: <Widget>[
              Text(
                formatCurrency(expense.amount, symbol: symbol),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (expense.isVoided)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Chip(label: Text('VOIDED')),
                ),
              const SizedBox(height: 16),
              _detail('Category', expense.categoryName),
              _detail('Description', expense.description),
              _detail('Date', DateFormat.yMMMd().format(expense.expenseDate)),
              _detail('Payment', expense.paymentMethod.label),
              if (expense.paymentReference != null)
                _detail('Reference', expense.paymentReference!),
              if (expense.supplierName != null)
                _detail('Supplier', expense.supplierName!),
              if (expense.notes != null) _detail('Notes', expense.notes!),
              if (expense.createdByName != null)
                _detail('Recorded by', expense.createdByName!),
              if (expense.attachmentUrl != null) ...<Widget>[
                const SizedBox(height: 12),
                AppNetworkImage(
                  url: expense.attachmentUrl!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(AppRadii.input),
                  fallbackIcon: Icons.broken_image_outlined,
                ),
              ],
              if (!expense.isVoided) ...<Widget>[
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () => _voidExpense(context, ref, businessId),
                  icon: const Icon(Icons.block),
                  label: const Text('Void Expense'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _detail(String label, String value) => Builder(
    builder: (context) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(color: context.mutedTextColor)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    ),
  );

  Future<void> _voidExpense(
    BuildContext context,
    WidgetRef ref,
    String businessId,
  ) async {
    final branchId = ref.read(currentWritableBranchIdProvider);
    if (branchId == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(branchWriteBlockedMessage)));
      return;
    }
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Void expense?'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(
            labelText: 'Reason',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Void'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(expensesRepositoryProvider)
          .voidExpense(
            businessId,
            expenseId,
            reason: reason.text,
            branchId: branchId,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Expense voided.')));
        context.pop();
      }
    } on ExpenseException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.userMessage)));
      }
    }
  }
}

class ExpenseCategoriesScreen extends ConsumerStatefulWidget {
  const ExpenseCategoriesScreen({super.key});

  @override
  ConsumerState<ExpenseCategoriesScreen> createState() =>
      _ExpenseCategoriesScreenState();
}

class _ExpenseCategoriesScreenState
    extends ConsumerState<ExpenseCategoriesScreen> {
  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    if (active is! ActiveBusinessData) {
      return const Scaffold(body: Center(child: Text('No business selected.')));
    }
    final businessId = active.business.businessId;

    return Scaffold(
      appBar: AppBar(title: const Text('Expense Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editCategory(context, businessId),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<ExpenseCategory>>(
        stream: ref
            .read(expenseCategoriesRepositoryProvider)
            .watchCategories(businessId, includeInactive: true),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final cat = list[index];
              return Card(
                child: ListTile(
                  leading: Icon(expenseCategoryIcon(cat.iconName)),
                  title: Text(cat.name),
                  subtitle: Text(cat.isActive ? 'Active' : 'Disabled'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      final repo = ref.read(
                        expenseCategoriesRepositoryProvider,
                      );
                      if (value == 'edit') {
                        await _editCategory(context, businessId, category: cat);
                      } else if (value == 'toggle') {
                        await repo.setActive(
                          businessId,
                          cat.id,
                          isActive: !cat.isActive,
                        );
                      } else if (value == 'delete') {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete category?'),
                            content: Text(
                              '“${cat.name}” will be removed from your expense categories. Past expenses keep their category name.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          try {
                            await repo.deleteCategory(businessId, cat.id);
                          } on ExpenseException catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.userMessage)),
                              );
                            }
                          }
                        }
                      }
                    },
                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(cat.isActive ? 'Disable' : 'Restore'),
                      ),
                      if (!cat.isSystemCategory)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _editCategory(
    BuildContext context,
    String businessId, {
    ExpenseCategory? category,
  }) async {
    final name = TextEditingController(text: category?.name ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(category == null ? 'Add category' : 'Edit category'),
        content: TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(expenseCategoriesRepositoryProvider);
    if (category == null) {
      await repo.createCategory(businessId, name: name.text);
    } else {
      await repo.updateCategory(
        businessId,
        category.id,
        name: name.text,
        iconName: category.iconName,
      );
    }
  }
}
