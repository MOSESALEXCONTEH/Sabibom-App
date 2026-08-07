import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/formatting/currency_formatter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_list_primitives.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../../core/widgets/app_summary_strip.dart';
import '../../../core/widgets/app_tab_page_scaffold.dart';
import '../../../core/widgets/list_bulk_actions.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../sales/domain/sale_models.dart';
import '../application/customers_providers.dart';
import '../domain/customer.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _query = '';
  CustomerListFilter _filter = CustomerListFilter.all;
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
      title: _selectionMode ? '${_selected.length} selected' : 'Customers',
      subtitle: _selectionMode
          ? 'Swipe left or select customers to archive'
          : 'Balances, purchases and contact details',
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
              heroTag: 'fab-new-customer',
              onPressed: () => context.pushNamed(AppRouteNames.newCustomer),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Add Customer'),
            )
          : null,
      body: active.when(
        loading: () => const AppListSkeleton(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        ),
        error: (_, _) => const AppErrorState(
          title: 'Unable to load customers',
          message: 'Something went wrong. Please try again.',
        ),
        data: (state) => switch (state) {
          ActiveBusinessData(:final business) => _CustomersBody(
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
          ActiveBusinessNone() => const AppEmptyState(
            title: 'No active business',
            description: 'Set up or select a business to continue.',
            icon: Icons.storefront_outlined,
          ),
          ActiveBusinessFailure(:final message) => AppErrorState(
            title: 'Unable to load customers',
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
      title: 'Archive ${_selected.length} customers?',
      message:
          'Selected customers will be archived and hidden from active lists.',
      confirmLabel: 'Archive',
    );
    if (!ok) return;
    final repo = ref.read(customersRepositoryProvider);
    var count = 0;
    for (final id in _selected.toList()) {
      try {
        await repo.setCustomerStatus(businessId, id, CustomerStatus.archived);
        count++;
      } catch (_) {}
    }
    ref.invalidate(customersListProvider(businessId));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Archived $count customers.')));
    _clearSelection();
  }
}

class _CustomersBody extends ConsumerWidget {
  const _CustomersBody({
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
  final CustomerListFilter filter;
  final bool selectionMode;
  final Set<String> selectedIds;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<CustomerListFilter> onFilterChanged;
  final ValueChanged<List<String>> onVisibleIds;
  final ValueChanged<String> onToggleSelected;
  final ValueChanged<String> onEnterSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(customersListProvider(businessId));
    return customersAsync.when(
      loading: () => const AppListSkeleton(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      ),
      error: (_, _) => AppErrorState(
        message: 'Could not load customers.',
        onRetry: () => ref.invalidate(customersListProvider(businessId)),
      ),
      data: (customers) {
        final filtered = filterCustomers(
          customers: customers,
          query: query,
          filter: filter,
        );
        onVisibleIds(
          filtered
              .where((c) => c.isActive)
              .map((c) => c.id)
              .toList(growable: false),
        );
        final active = customers.where((c) => c.isActive).toList();
        final withBalance = active.where((c) => c.hasBalance).length;
        final creditTotal = active.fold<int>(
          0,
          (sum, customer) => sum + customer.balanceMinor,
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppSummaryStrip(
                items: <AppSummaryItem>[
                  AppSummaryItem(
                    icon: Icons.people_alt_outlined,
                    label: '${active.length} customers',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  AppSummaryItem(
                    icon: Icons.circle,
                    label: '$withBalance with balance',
                    color: Colors.orange,
                  ),
                  AppSummaryItem(
                    icon: Icons.circle,
                    label:
                        '${formatCurrency(minorToMoney(creditTotal), symbol: currencySymbol)} credit',
                    color: AppColors.secondary,
                  ),
                ],
              ),
              if (!selectionMode) ...[
                const SizedBox(height: AppSpacing.sm + 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () => context.pushNamed(
                      AppRouteNames.customerMessageCampaign,
                    ),
                    icon: const Icon(Icons.campaign_outlined),
                    label: const Text('Message customers'),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (customers.isEmpty)
                Expanded(
                  child: AppEmptyState(
                    title: 'No customers yet',
                    description:
                        'Save customer details to track purchases, balances and payment history.',
                    icon: Icons.people_outline,
                    actionLabel: 'Add Customer',
                    actionIcon: Icons.person_add_alt_1_outlined,
                    onAction: () =>
                        context.pushNamed(AppRouteNames.newCustomer),
                  ),
                )
              else ...<Widget>[
                TextField(
                  onChanged: onQueryChanged,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search name, phone or email',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm + 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: CustomerListFilter.values.map((value) {
                      return Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: ChoiceChip(
                          label: Text(_label(value)),
                          selected: filter == value,
                          onSelected: (_) => onFilterChanged(value),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm + 4),
                Expanded(
                  child: filtered.isEmpty
                      ? const AppEmptyState(
                          title: 'No matches',
                          description: 'No customers match your filters.',
                          icon: Icons.filter_alt_off_outlined,
                        )
                      : RefreshIndicator(
                          onRefresh: () async =>
                              ref.invalidate(customersListProvider(businessId)),
                          child: ListView.separated(
                            padding: const EdgeInsets.only(
                              bottom: AppTabChrome.bottomInset,
                            ),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              final customer = filtered[index];
                              final tile = AppListRow(
                                onTap: () => context.pushNamed(
                                  AppRouteNames.customerDetails,
                                  pathParameters: <String, String>{
                                    'customerId': customer.id,
                                  },
                                ),
                                leading: AppListAvatar(
                                  label: customer.initials,
                                ),
                                title: customer.name,
                                subtitle: [
                                  if (customer.phone?.isNotEmpty == true)
                                    customer.phone!,
                                  '${customer.purchaseCount} purchases',
                                  if (customer.lastPurchaseAt != null)
                                    DateFormat.MMMd().format(
                                      customer.lastPurchaseAt!,
                                    ),
                                ].join(' · '),
                                trailing: Text(
                                  formatCurrency(
                                    minorToMoney(customer.balanceMinor),
                                    symbol: currencySymbol,
                                  ),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: customer.hasBalance
                                        ? AppColors.warning
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                  ),
                                ),
                              );
                              return SelectableDismissibleTile(
                                    id: customer.id,
                                    selectionMode: selectionMode,
                                    selected: selectedIds.contains(customer.id),
                                    onToggleSelected: onToggleSelected,
                                    enabled: customer.isActive,
                                    dismissLabel: 'Archive',
                                    confirmTitle: 'Archive customer?',
                                    confirmMessage:
                                        '“${customer.name}” will be archived.',
                                    confirmLabel: 'Archive',
                                    onDismissed: (id) async {
                                      try {
                                        await ref
                                            .read(customersRepositoryProvider)
                                            .setCustomerStatus(
                                              businessId,
                                              id,
                                              CustomerStatus.archived,
                                            );
                                        ref.invalidate(
                                          customersListProvider(businessId),
                                        );
                                        return true;
                                      } catch (_) {
                                        return false;
                                      }
                                    },
                                    child: GestureDetector(
                                      onLongPress: customer.isActive
                                          ? () => onEnterSelection(customer.id)
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
            ],
          ),
        );
      },
    );
  }

  static String _label(CustomerListFilter filter) => switch (filter) {
    CustomerListFilter.all => 'All',
    CustomerListFilter.active => 'Active',
    CustomerListFilter.hasBalance => 'Has Balance',
    CustomerListFilter.noBalance => 'No Balance',
    CustomerListFilter.archived => 'Archived',
  };
}
