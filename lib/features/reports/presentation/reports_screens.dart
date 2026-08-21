import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/router.dart';
import '../../../core/formatting/currency_formatter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_list_primitives.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../../core/widgets/app_scroll_padding.dart';
import '../../business_setup/domain/business.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../sales/domain/sale_models.dart';
import '../application/reports_providers.dart';
import '../data/reports_repository.dart';
import '../domain/balance_report_models.dart';
import '../domain/profit_models.dart';
import '../services/csv_export_service.dart';
import '../services/report_pdf_service.dart';
import '../../team/application/team_providers.dart';
import '../../team/domain/app_permission.dart';
import '../../billing/domain/billing_entitlements.dart';
import '../../billing/presentation/billing_gate.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canProfit =
        ref.watch(hasPermissionProvider(AppPermission.viewProductProfit)) ||
        ref.watch(hasPermissionProvider(AppPermission.viewProfit));
    final canExpiry = ref.watch(
      hasPermissionProvider(AppPermission.viewProductExpiry),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Business Reports')),
      body: ListView(
        padding: appSafeScrollPadding(context),
        children: [
          const AppSectionHeader('Insights'),
          AppSectionCard(
            children: [
              _ReportTile(
                icon: Icons.trending_up_outlined,
                title: 'Profit & Loss',
                subtitle: 'Sales, costs, expenses and profit',
                onTap: () => context.pushNamed(AppRouteNames.reportProfitLoss),
                showDivider: true,
              ),
              if (canProfit)
                _ReportTile(
                  icon: Icons.analytics_outlined,
                  title: 'Product Profit',
                  subtitle: 'Realized and remaining product profit',
                  onTap: () =>
                      context.pushNamed(AppRouteNames.reportProductProfit),
                  showDivider: true,
                ),
              if (canExpiry)
                _ReportTile(
                  icon: Icons.event_busy_outlined,
                  title: 'Product Expiry',
                  subtitle: 'Expired and soon-to-expire batches',
                  onTap: () =>
                      context.pushNamed(AppRouteNames.reportProductExpiry),
                  showDivider: true,
                ),
              _ReportTile(
                icon: Icons.today_outlined,
                title: 'Daily summary',
                subtitle: 'Sales and expenses for one business day',
                onTap: () => context.pushNamed(
                  AppRouteNames.dailySummary,
                  pathParameters: {
                    'dateKey': DateTime.now().toIso8601String().substring(
                      0,
                      10,
                    ),
                  },
                ),
                showDivider: true,
              ),
              _ReportTile(
                icon: Icons.date_range_outlined,
                title: 'Weekly report',
                subtitle: 'Week sales, expenses and stock alerts',
                onTap: () {
                  final now = DateTime.now();
                  final thursday = now.add(Duration(days: 4 - now.weekday));
                  final firstDay = DateTime(thursday.year, 1, 1);
                  final week =
                      1 + ((thursday.difference(firstDay).inDays) / 7).floor();
                  final weekKey =
                      '${thursday.year}-W${week.toString().padLeft(2, '0')}';
                  context.pushNamed(
                    AppRouteNames.weeklyReport,
                    pathParameters: {'weekKey': weekKey},
                  );
                },
                showDivider: true,
              ),
              _ReportTile(
                icon: Icons.nightlight_round,
                title: 'End of Day',
                subtitle: 'Count cash and close the business day',
                onTap: () => context.pushNamed(
                  AppRouteNames.endOfDay,
                  pathParameters: {
                    'dateKey': DateTime.now().toIso8601String().substring(
                      0,
                      10,
                    ),
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const AppSectionHeader('Balances & stock'),
          AppSectionCard(
            children: [
              _ReportTile(
                icon: Icons.inventory_2_outlined,
                title: 'Inventory valuation',
                subtitle: 'Stock value by product cost',
                onTap: () => context.pushNamed(AppRouteNames.reportInventory),
                showDivider: true,
              ),
              _ReportTile(
                icon: Icons.people_outline,
                title: 'Customer balances',
                subtitle: 'Who owes your business',
                onTap: () =>
                    context.pushNamed(AppRouteNames.reportCustomerBalances),
                showDivider: true,
              ),
              _ReportTile(
                icon: Icons.local_shipping_outlined,
                title: 'Supplier balances',
                subtitle: 'What you owe suppliers',
                onTap: () =>
                    context.pushNamed(AppRouteNames.reportSupplierBalances),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ProfitLossReportScreen extends ConsumerStatefulWidget {
  const ProfitLossReportScreen({super.key});

  @override
  ConsumerState<ProfitLossReportScreen> createState() =>
      _ProfitLossReportScreenState();
}

class _ProfitLossReportScreenState
    extends ConsumerState<ProfitLossReportScreen> {
  _ReportPeriod _period = _ReportPeriod.thisMonth;
  bool _exporting = false;

  ({DateTime start, DateTime end}) get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      _ReportPeriod.today => (
        start: today,
        end: today.add(const Duration(days: 1)),
      ),
      _ReportPeriod.thisWeek => (
        start: today.subtract(Duration(days: today.weekday - 1)),
        end: today
            .subtract(Duration(days: today.weekday - 1))
            .add(const Duration(days: 7)),
      ),
      _ReportPeriod.thisMonth => (
        start: DateTime(now.year, now.month),
        end: DateTime(now.year, now.month + 1),
      ),
      _ReportPeriod.thisYear => (
        start: DateTime(now.year),
        end: DateTime(now.year + 1),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBusinessProvider).asData?.value;
    final business = switch (active) {
      ActiveBusinessData(:final business) => business,
      _ => null,
    };
    if (business == null) {
      return const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: AppCardSkeleton(height: 200),
        ),
      );
    }
    final range = _range;
    final request = ProfitReportRequest(
      businessId: business.businessId,
      start: range.start,
      end: range.end,
    );
    final report = ref.watch(profitReportProvider(request));

    return Scaffold(
      appBar: AppBar(title: const Text('Profit & Loss')),
      body: report.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: AppCardSkeleton(height: 220),
        ),
        error: (_, _) => AppErrorState(
          message: 'Could not load this report.',
          onRetry: () => ref.invalidate(profitReportProvider(request)),
        ),
        data: (data) => ListView(
          padding: appSafeScrollPadding(context),
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              children: _ReportPeriod.values
                  .map(
                    (period) => ChoiceChip(
                      label: Text(period.label),
                      selected: _period == period,
                      onSelected: (_) => setState(() => _period = period),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '${DateFormat.yMMMd().format(range.start)} – ${DateFormat.yMMMd().format(range.end.subtract(const Duration(days: 1)))}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            if (data.summary.unavailableReason != null)
              _MessageBanner(message: data.summary.unavailableReason!)
            else ...[
              if (data.summary.cogsEstimated)
                const _MessageBanner(
                  message:
                      'COGS is estimated because one or more sales did not include a cost snapshot.',
                  warning: true,
                ),
              _SummaryGrid(
                summary: data.summary,
                symbol: business.currency.symbol,
              ),
              const SizedBox(height: AppSpacing.lg),
              _SummaryRows(
                summary: data.summary,
                symbol: business.currency.symbol,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _exporting
                    ? null
                    : () => _downloadPdf(business, range, data),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Download PDF'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _exporting ? null : () => _exportCsv(data),
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Export CSV'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _downloadPdf(
    Business business,
    ({DateTime start, DateTime end}) range,
    ReportPeriodData data,
  ) async {
    if (!await requireEntitlement(
      context,
      ref,
      key: BillingEntitlementKeys.reportsExport,
      featureName: 'Report export',
    )) {
      return;
    }
    setState(() => _exporting = true);
    try {
      final bytes = await ReportPdfService().buildProfitLossPdf(
        businessName: business.name,
        currencyCode: business.currency.code,
        currencySymbol: business.currency.symbol,
        start: range.start,
        end: range.end,
        summary: data.summary,
      );
      final directory = await getApplicationDocumentsDirectory();
      final file = File(path.join(directory.path, 'SabiBom_Profit_Loss.pdf'));
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: 'SabiBom Profit & Loss',
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportCsv(ReportPeriodData data) async {
    if (!await requireEntitlement(
      context,
      ref,
      key: BillingEntitlementKeys.reportsExport,
      featureName: 'Report export',
    )) {
      return;
    }
    setState(() => _exporting = true);
    try {
      final csv = const CsvExportService().salesCsv(data.sales);
      final directory = await getApplicationDocumentsDirectory();
      final file = File(path.join(directory.path, 'SabiBom_Sales_Report.csv'));
      await file.writeAsString(csv, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'SabiBom sales report',
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

class InventoryValuationReportScreen extends ConsumerStatefulWidget {
  const InventoryValuationReportScreen({super.key});

  @override
  ConsumerState<InventoryValuationReportScreen> createState() =>
      _InventoryValuationReportScreenState();
}

class _InventoryValuationReportScreenState
    extends ConsumerState<InventoryValuationReportScreen> {
  var _exporting = false;

  @override
  Widget build(BuildContext context) {
    final business = _activeBusiness(ref);
    if (business == null) {
      return const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: AppCardSkeleton(height: 200),
        ),
      );
    }
    final report = ref.watch(inventoryValuationProvider(business.businessId));
    final symbol = business.currency.symbol;

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory valuation')),
      body: report.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: AppListSkeleton(),
        ),
        error: (_, _) =>
            const Center(child: Text('Could not load inventory valuation.')),
        data: (data) {
          if (data.rows.isEmpty) {
            return const _EmptyReport(
              title: 'No tracked stock yet',
              subtitle:
                  'Add products with stock tracking to see inventory value.',
            );
          }
          return ListView(
            padding: appSafeScrollPadding(context),
            children: [
              _MetricPair(
                leftLabel: 'Total stock value',
                leftValue: formatCurrency(
                  minorToMoney(data.totalValueMinor),
                  symbol: symbol,
                ),
                rightLabel: 'Tracked products',
                rightValue: '${data.trackedProductCount}',
              ),
              const SizedBox(height: AppSpacing.sm),
              _MetricPair(
                leftLabel: 'Low stock',
                leftValue: '${data.lowStockCount}',
                rightLabel: 'Out of stock',
                rightValue: '${data.outOfStockCount}',
              ),
              const SizedBox(height: AppSpacing.sm),
              Card(
                child: ListTile(
                  title: const Text('Low / out-of-stock value'),
                  trailing: Text(
                    formatCurrency(
                      minorToMoney(data.lowStockValueMinor),
                      symbol: symbol,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _exporting ? null : () => _exportInventoryCsv(data),
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Export CSV'),
              ),
              const SizedBox(height: AppSpacing.md),
              ...data.rows.map((row) {
                final status = row.isOutOfStock
                    ? 'Out of stock'
                    : row.isLowStock
                    ? 'Low stock'
                    : null;
                return Card(
                  child: ListTile(
                    title: Text(row.name),
                    subtitle: Text(
                      [
                        if (row.sku.isNotEmpty) row.sku,
                        if (row.categoryName != null) row.categoryName!,
                        'Qty ${row.quantity}',
                        formatCurrency(
                          minorToMoney(row.unitCostMinor),
                          symbol: symbol,
                        ),
                        ?status,
                      ].join(' · '),
                    ),
                    trailing: Text(
                      formatCurrency(
                        minorToMoney(row.lineValueMinor),
                        symbol: symbol,
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportInventoryCsv(InventoryValuationReport data) async {
    if (!await requireEntitlement(
      context,
      ref,
      key: BillingEntitlementKeys.reportsExport,
      featureName: 'Report export',
    )) {
      return;
    }
    setState(() => _exporting = true);
    try {
      final csv = const CsvExportService().inventoryCsv(data);
      await _shareCsv(csv, 'SabiBom_Inventory_Valuation.csv');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

class CustomerBalancesReportScreen extends ConsumerStatefulWidget {
  const CustomerBalancesReportScreen({super.key});

  @override
  ConsumerState<CustomerBalancesReportScreen> createState() =>
      _CustomerBalancesReportScreenState();
}

class _CustomerBalancesReportScreenState
    extends ConsumerState<CustomerBalancesReportScreen> {
  var _exporting = false;

  @override
  Widget build(BuildContext context) {
    final business = _activeBusiness(ref);
    if (business == null) {
      return const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: AppCardSkeleton(height: 200),
        ),
      );
    }
    final report = ref.watch(
      customerBalancesReportProvider(business.businessId),
    );
    final symbol = business.currency.symbol;

    return Scaffold(
      appBar: AppBar(title: const Text('Customer balances')),
      body: report.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: AppListSkeleton(),
        ),
        error: (_, _) =>
            const Center(child: Text('Could not load customer balances.')),
        data: (data) {
          if (data.customers.isEmpty) {
            return const _EmptyReport(
              title: 'No customer debts',
              subtitle: 'Customers with outstanding balances will appear here.',
            );
          }
          return ListView(
            padding: appSafeScrollPadding(context),
            children: [
              _MetricPair(
                leftLabel: 'Total owed to you',
                leftValue: formatCurrency(
                  minorToMoney(data.totalDebtMinor),
                  symbol: symbol,
                ),
                rightLabel: 'Customers owing',
                rightValue: '${data.owingCount}',
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _exporting
                    ? null
                    : () async {
                        if (!await requireEntitlement(
                          context,
                          ref,
                          key: BillingEntitlementKeys.reportsExport,
                          featureName: 'Report export',
                        )) {
                          return;
                        }
                        setState(() => _exporting = true);
                        try {
                          final csv = const CsvExportService().customersCsv(
                            data.customers,
                          );
                          await _shareCsv(csv, 'SabiBom_Customer_Balances.csv');
                        } finally {
                          if (mounted) setState(() => _exporting = false);
                        }
                      },
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Export CSV'),
              ),
              const SizedBox(height: AppSpacing.md),
              ...data.customers.map(
                (customer) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        customer.name.isEmpty
                            ? '?'
                            : customer.name[0].toUpperCase(),
                      ),
                    ),
                    title: Text(customer.name),
                    subtitle: Text(
                      [
                        if (customer.phone != null) customer.phone!,
                        if (customer.email != null) customer.email!,
                      ].join(' · '),
                    ),
                    trailing: Text(
                      formatCurrency(
                        minorToMoney(customer.balanceMinor),
                        symbol: symbol,
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFB42318),
                      ),
                    ),
                    onTap: () => context.pushNamed(
                      AppRouteNames.customerDetails,
                      pathParameters: {'customerId': customer.id},
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SupplierBalancesReportScreen extends ConsumerStatefulWidget {
  const SupplierBalancesReportScreen({super.key});

  @override
  ConsumerState<SupplierBalancesReportScreen> createState() =>
      _SupplierBalancesReportScreenState();
}

class _SupplierBalancesReportScreenState
    extends ConsumerState<SupplierBalancesReportScreen> {
  var _exporting = false;

  @override
  Widget build(BuildContext context) {
    final business = _activeBusiness(ref);
    if (business == null) {
      return const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: AppCardSkeleton(height: 200),
        ),
      );
    }
    final report = ref.watch(
      supplierBalancesReportProvider(business.businessId),
    );
    final symbol = business.currency.symbol;

    return Scaffold(
      appBar: AppBar(title: const Text('Supplier balances')),
      body: report.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: AppListSkeleton(),
        ),
        error: (_, _) =>
            const Center(child: Text('Could not load supplier balances.')),
        data: (data) {
          if (data.suppliers.isEmpty) {
            return const _EmptyReport(
              title: 'No supplier debts',
              subtitle:
                  'Suppliers you owe after unpaid purchases will appear here.',
            );
          }
          return ListView(
            padding: appSafeScrollPadding(context),
            children: [
              _MetricPair(
                leftLabel: 'Total you owe',
                leftValue: formatCurrency(
                  minorToMoney(data.totalDebtMinor),
                  symbol: symbol,
                ),
                rightLabel: 'Suppliers owed',
                rightValue: '${data.owingCount}',
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _exporting
                    ? null
                    : () async {
                        if (!await requireEntitlement(
                          context,
                          ref,
                          key: BillingEntitlementKeys.reportsExport,
                          featureName: 'Report export',
                        )) {
                          return;
                        }
                        setState(() => _exporting = true);
                        try {
                          final csv = const CsvExportService().suppliersCsv(
                            data.suppliers,
                          );
                          await _shareCsv(csv, 'SabiBom_Supplier_Balances.csv');
                        } finally {
                          if (mounted) setState(() => _exporting = false);
                        }
                      },
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Export CSV'),
              ),
              const SizedBox(height: AppSpacing.md),
              ...data.suppliers.map(
                (supplier) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(
                        0xFF5B3DF5,
                      ).withValues(alpha: 0.12),
                      child: Text(
                        supplier.name.isEmpty
                            ? '?'
                            : supplier.name[0].toUpperCase(),
                        style: const TextStyle(color: Color(0xFF5B3DF5)),
                      ),
                    ),
                    title: Text(supplier.name),
                    subtitle: Text(
                      [
                        if (supplier.phone != null) supplier.phone!,
                        '${supplier.purchaseCount} purchases',
                      ].join(' · '),
                    ),
                    trailing: Text(
                      formatCurrency(
                        minorToMoney(supplier.balanceMinor),
                        symbol: symbol,
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFB42318),
                      ),
                    ),
                    onTap: () => context.pushNamed(
                      AppRouteNames.supplierDetails,
                      pathParameters: {'supplierId': supplier.id},
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Business? _activeBusiness(WidgetRef ref) {
  final active = ref.watch(activeBusinessProvider).asData?.value;
  return switch (active) {
    ActiveBusinessData(:final business) => business,
    _ => null,
  };
}

Future<void> _shareCsv(String csv, String filename) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File(path.join(directory.path, filename));
  await file.writeAsString(csv, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      subject: filename,
    ),
  );
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary, required this.symbol});
  final ProfitPeriodSummary summary;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    String money(int value) =>
        formatCurrency(minorToMoney(value), symbol: symbol);
    final profitable = summary.netProfitMinor >= 0;
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: profitable ? context.successTint : context.dangerTint,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(
              color: (profitable ? AppColors.secondary : AppColors.danger)
                  .withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    profitable
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    color: profitable ? AppColors.secondary : AppColors.danger,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    profitable ? 'Net profit' : 'Net loss',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  money(summary.netProfitMinor),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Net margin ${(summary.netMargin * 100).toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: _MetricCard('Net sales', money(summary.netSalesMinor)),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetricCard(
                'Gross profit',
                money(summary.grossProfitMinor),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryRows extends StatelessWidget {
  const _SummaryRows({required this.summary, required this.symbol});
  final ProfitPeriodSummary summary;
  final String symbol;
  @override
  Widget build(BuildContext context) {
    String money(int value) =>
        formatCurrency(minorToMoney(value), symbol: symbol);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Income statement',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: <Widget>[
                _StatementRow('Gross sales', money(summary.grossSalesMinor)),
                _StatementRow(
                  'Less: sales discounts',
                  money(-summary.salesDiscountMinor),
                  muted: true,
                ),
                const Divider(),
                _StatementRow(
                  'Net sales',
                  money(summary.netSalesMinor),
                  emphasized: true,
                ),
                _StatementRow(
                  'Less: cost of goods sold',
                  money(-summary.cogsMinor),
                  muted: true,
                ),
                const Divider(),
                _StatementRow(
                  'Gross profit',
                  money(summary.grossProfitMinor),
                  emphasized: true,
                ),
                _StatementRow(
                  'Less: operating expenses',
                  money(-summary.expenseMinor),
                  muted: true,
                ),
                const Divider(thickness: 2),
                _StatementRow(
                  summary.netProfitMinor >= 0 ? 'Net profit' : 'Net loss',
                  money(summary.netProfitMinor),
                  emphasized: true,
                  color: summary.netProfitMinor >= 0
                      ? AppColors.secondary
                      : AppColors.danger,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Margin analysis',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: <Widget>[
                _MarginBar(label: 'Gross margin', value: summary.grossMargin),
                const SizedBox(height: AppSpacing.md),
                _MarginBar(label: 'Net margin', value: summary.netMargin),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Business position',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        _MetricPair(
          leftLabel: 'Stock value',
          leftValue: money(summary.stockValueMinor),
          rightLabel: 'Customer debt',
          rightValue: money(summary.customerDebtMinor),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: ListTile(
            leading: const Icon(Icons.local_shipping_outlined),
            title: const Text('Supplier debt'),
            trailing: Text(
              money(summary.supplierDebtMinor),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatementRow extends StatelessWidget {
  const _StatementRow(
    this.label,
    this.value, {
    this.emphasized = false,
    this.muted = false,
    this.color,
  });

  final String label;
  final String value;
  final bool emphasized;
  final bool muted;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w500,
              color: muted ? context.mutedTextColor : null,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          value,
          style: TextStyle(
            fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class _MarginBar extends StatelessWidget {
  const _MarginBar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final positive = value >= 0;
    final color = positive ? AppColors.secondary : AppColors.danger;
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(label)),
            Text(
              '${(value * 100).toStringAsFixed(1)}%',
              style: TextStyle(fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: value.abs().clamp(0, 1),
            color: color,
            backgroundColor: color.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    ),
  );
}

class _MetricPair extends StatelessWidget {
  const _MetricPair({
    required this.leftLabel,
    required this.leftValue,
    required this.rightLabel,
    required this.rightValue,
  });

  final String leftLabel;
  final String leftValue;
  final String rightLabel;
  final String rightValue;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _MetricCard(leftLabel, leftValue)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _MetricCard(rightLabel, rightValue)),
      ],
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, this.warning = false});
  final String message;
  final bool warning;
  @override
  Widget build(BuildContext context) {
    final bg = warning ? context.warningTint : context.dangerTint;
    final fg = warning
        ? (context.isDarkTheme
              ? const Color(0xFFFBBF24)
              : const Color(0xFF92400E))
        : (context.isDarkTheme
              ? const Color(0xFFFCA5A5)
              : const Color(0xFF991B1B));
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}

class _EmptyReport extends StatelessWidget {
  const _EmptyReport({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showDivider = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        leading: DecoratedBox(
          decoration: BoxDecoration(
            color: context.brandTint,
            borderRadius: BorderRadius.circular(AppRadii.chip),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Icon(
              icon,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.chevron_right, color: context.mutedTextColor),
        onTap: onTap,
      ),
      if (showDivider)
        Divider(height: 1, indent: 72, color: context.borderColor),
    ],
  );
}

enum _ReportPeriod {
  today('Today'),
  thisWeek('This week'),
  thisMonth('This month'),
  thisYear('This year');

  const _ReportPeriod(this.label);
  final String label;
}
