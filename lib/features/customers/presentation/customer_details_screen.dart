import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/formatting/currency_formatter.dart';
import '../../../core/sync/record_sync_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_scroll_padding.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../messaging/customer_messaging_service.dart';
import '../../sales/application/sale_cart_controller.dart';
import '../../sales/domain/sale_models.dart';
import '../../sales/presentation/sales_navigation.dart';
import '../application/customers_providers.dart';
import '../data/customers_repository.dart';
import '../domain/customer.dart';

class CustomerDetailsScreen extends ConsumerWidget {
  const CustomerDetailsScreen({required this.customerId, super.key});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trimmed = customerId.trim();
    if (trimmed.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer Details')),
        body: const Center(child: Text('This customer could not be found.')),
      );
    }
    final active = ref.watch(activeBusinessProvider);
    return active.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => Scaffold(
        appBar: AppBar(title: const Text('Customer Details')),
        body: const Center(
          child: Text('Something went wrong. Please try again.'),
        ),
      ),
      data: (state) => switch (state) {
        ActiveBusinessData(:final business) => _Body(
          businessId: business.businessId,
          customerId: trimmed,
          currencySymbol: business.currency.symbol,
        ),
        _ => Scaffold(
          appBar: AppBar(title: const Text('Customer Details')),
          body: const Center(
            child: Text('Set up or select a business to continue.'),
          ),
        ),
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.businessId,
    required this.customerId,
    required this.currencySymbol,
  });

  final String businessId;
  final String customerId;
  final String currencySymbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(customerDetailProvider((businessId, customerId)));
    final sales = ref.watch(customerSalesProvider((businessId, customerId)));
    final ledger = ref.watch(customerLedgerProvider((businessId, customerId)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Details'),
        actions: <Widget>[
          RecordSyncStatusIcon(
            request: RecordSyncRequest(
              businessId: businessId,
              collection: 'customers',
              recordId: customerId,
            ),
          ),
          IconButton(
            onPressed: () => context.pushNamed(
              AppRouteNames.editCustomer,
              pathParameters: <String, String>{'customerId': customerId},
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(
              customerDetailProvider((businessId, customerId)),
            ),
            child: const Text('Retry'),
          ),
        ),
        data: (customer) {
          if (customer == null) {
            return const Center(
              child: Text(
                'This record could not be found. It may have been removed or archived.',
              ),
            );
          }
          return ListView(
            padding: appSafeScrollPadding(
              context,
              left: 20,
              top: 12,
              right: 20,
              bottom: 40,
            ),
            children: <Widget>[
              if ((customer.photoUrl ?? '').trim().isNotEmpty) ...<Widget>[
                Center(
                  child: AppNetworkImage(
                    url: customer.photoUrl!,
                    width: 104,
                    height: 104,
                    borderRadius: BorderRadius.circular(52),
                    fallbackIcon: Icons.person_outline,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                customer.name,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (customer.phone?.isNotEmpty == true) Text(customer.phone!),
              if (customer.email?.isNotEmpty == true) Text(customer.email!),
              if (customer.address?.isNotEmpty == true) Text(customer.address!),
              if (customer.hasPhone) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (customer.showWhatsAppBadge)
                      FilledButton.tonalIcon(
                        onPressed: () => _messageCustomer(
                          context,
                          ref,
                          customer,
                          preferWhatsApp: true,
                        ),
                        icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
                        label: const Text('WhatsApp'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _messageCustomer(
                        context,
                        ref,
                        customer,
                        preferWhatsApp: false,
                      ),
                      icon: const Icon(Icons.sms_outlined),
                      label: const Text('SMS'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.pushNamed(
                        AppRouteNames.customerMessageCampaign,
                        queryParameters: <String, String>{
                          'customerId': customer.id,
                        },
                      ),
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Sabi message'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: <Widget>[
                      _row(
                        'Outstanding balance',
                        formatCurrency(
                          minorToMoney(customer.balanceMinor),
                          symbol: currencySymbol,
                        ),
                      ),
                      _row(
                        'Total sales',
                        formatCurrency(
                          minorToMoney(customer.totalSalesMinor),
                          symbol: currencySymbol,
                        ),
                      ),
                      _row(
                        'Total paid',
                        formatCurrency(
                          minorToMoney(customer.totalPaidMinor),
                          symbol: currencySymbol,
                        ),
                      ),
                      _row('Purchases', '${customer.purchaseCount}'),
                      _row(
                        'Last purchase',
                        customer.lastPurchaseAt == null
                            ? '—'
                            : DateFormat.yMMMd().format(
                                customer.lastPurchaseAt!,
                              ),
                      ),
                      if (customer.notes?.isNotEmpty == true)
                        _row('Notes', customer.notes!),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.pushNamed(
                  AppRouteNames.editCustomer,
                  pathParameters: <String, String>{'customerId': customerId},
                ),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit Customer'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: customer.balanceMinor > 0
                    ? () => context.pushNamed(
                        AppRouteNames.customerPayment,
                        pathParameters: <String, String>{
                          'customerId': customerId,
                        },
                      )
                    : null,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Record Payment'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  ref
                      .read(saleCartProvider.notifier)
                      .selectCustomer(
                        SaleCustomer(
                          customerId: customer.id,
                          name: customer.name,
                          phone: customer.phone,
                          balanceMinor: customer.balanceMinor,
                        ),
                      );
                  context.pushNamed(AppRouteNames.newSale);
                },
                icon: const Icon(Icons.point_of_sale_outlined),
                label: const Text('New Sale for Customer'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _toggleArchive(context, ref, customer),
                icon: Icon(
                  customer.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                label: Text(
                  customer.isArchived ? 'Restore Customer' : 'Archive Customer',
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Sales history',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              sales.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) =>
                    const Text('Could not load customer sales history.'),
                data: (items) {
                  if (items.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No sales for this customer yet.'),
                      ),
                    );
                  }
                  return Card(
                    child: Column(
                      children: items
                          .map(
                            (sale) => ListTile(
                              onTap: () => SalesNavigation.openSaleDetails(
                                context,
                                sale.saleId,
                              ),
                              title: Text(sale.receiptNumber),
                              subtitle: Text(
                                '${sale.paymentStatus.name} · ${sale.saleStatus.name}',
                              ),
                              trailing: Text(
                                formatCurrency(
                                  minorToMoney(sale.totalMinor),
                                  symbol: currencySymbol,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Ledger history',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ledger.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const Text('Could not load ledger history.'),
                data: (entries) {
                  if (entries.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No ledger entries yet.'),
                      ),
                    );
                  }
                  return Card(
                    child: Column(
                      children: entries
                          .map(
                            (entry) => ListTile(
                              title: Text(entry.type.label),
                              subtitle: Text(
                                entry.createdAt == null
                                    ? 'Balance ${formatCurrency(minorToMoney(entry.balanceAfterMinor), symbol: currencySymbol)}'
                                    : DateFormat.MMMd().add_jm().format(
                                        entry.createdAt!,
                                      ),
                              ),
                              trailing: Text(
                                entry.creditMinor > 0
                                    ? '-${formatCurrency(minorToMoney(entry.creditMinor), symbol: currencySymbol)}'
                                    : formatCurrency(
                                        minorToMoney(entry.debitMinor),
                                        symbol: currencySymbol,
                                      ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _messageCustomer(
    BuildContext context,
    WidgetRef ref,
    Customer customer, {
    required bool preferWhatsApp,
  }) async {
    try {
      final messaging = ref.read(customerMessagingServiceProvider);
      if (preferWhatsApp && customer.usesWhatsApp) {
        await messaging.openWhatsApp(phone: customer.phone!);
      } else {
        await messaging.openSms(phone: customer.phone!);
      }
    } on MessagingException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _toggleArchive(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
  ) async {
    try {
      await ref
          .read(customersRepositoryProvider)
          .setCustomerStatus(
            businessId,
            customer.id,
            customer.isArchived
                ? CustomerStatus.active
                : CustomerStatus.archived,
          );
      ref.invalidate(customerDetailProvider((businessId, customerId)));
      ref.invalidate(customersListProvider(businessId));
    } on CustomerException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.friendlyMessage)));
      }
    }
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.mutedText),
          ),
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
