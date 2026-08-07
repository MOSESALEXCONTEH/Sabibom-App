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
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../branches/application/current_branch_providers.dart';
import '../../business_setup/domain/business.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../products/application/products_providers.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product.dart';
import '../../sales/domain/sale_models.dart';
import '../../team/application/team_providers.dart';
import '../../team/domain/app_permission.dart';
import '../../team/presentation/team_widgets.dart';
import '../application/reports_providers.dart';
import '../domain/product_intelligence_report_models.dart';
import '../services/csv_export_service.dart';
import '../services/report_pdf_service.dart';

class ProductProfitReportScreen extends ConsumerStatefulWidget {
  const ProductProfitReportScreen({super.key});

  @override
  ConsumerState<ProductProfitReportScreen> createState() =>
      _ProductProfitReportScreenState();
}

class _ProductProfitReportScreenState
    extends ConsumerState<ProductProfitReportScreen> {
  _PiPeriod _period = _PiPeriod.thisMonth;
  ProductProfitSort _sort = ProductProfitSort.realizedProfitDesc;
  var _inStockOnly = false;
  var _exporting = false;

  ({DateTime start, DateTime end}) get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      _PiPeriod.today => (
        start: today,
        end: today.add(const Duration(days: 1)),
      ),
      _PiPeriod.thisWeek => (
        start: today.subtract(Duration(days: today.weekday - 1)),
        end: today
            .subtract(Duration(days: today.weekday - 1))
            .add(const Duration(days: 7)),
      ),
      _PiPeriod.thisMonth => (
        start: DateTime(now.year, now.month),
        end: DateTime(now.year, now.month + 1),
      ),
      _PiPeriod.thisYear => (
        start: DateTime(now.year),
        end: DateTime(now.year + 1),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final canView =
        ref.watch(hasPermissionProvider(AppPermission.viewProductProfit)) ||
        ref.watch(hasPermissionProvider(AppPermission.viewProfit));
    if (!canView) {
      return const AccessDeniedScreen(
        message: 'You need permission to view product profit.',
      );
    }

    final business = _activeBusiness(ref);
    if (business == null) {
      return const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: AppCardSkeleton(height: 200),
        ),
      );
    }

    final range = _range;
    final request = ProductProfitReportRequest(
      businessId: business.businessId,
      start: range.start,
      end: range.end,
      inStockOnly: _inStockOnly,
      sort: _sort,
    );
    final report = ref.watch(productProfitReportProvider(request));
    final canExport =
        ref.watch(
          hasPermissionProvider(AppPermission.exportProductProfitReport),
        ) ||
        ref.watch(hasPermissionProvider(AppPermission.exportReports));
    final symbol = business.currency.symbol;

    return Scaffold(
      appBar: AppBar(title: const Text('Product Profit')),
      body: report.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: AppCardSkeleton(height: 220),
        ),
        error: (_, _) => AppErrorState(
          message: 'Could not load product profit.',
          onRetry: () => ref.invalidate(productProfitReportProvider(request)),
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              children: _PiPeriod.values
                  .map(
                    (period) => ChoiceChip(
                      label: Text(period.label),
                      selected: _period == period,
                      onSelected: (_) => setState(() => _period = period),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${DateFormat.yMMMd().format(range.start)} – '
              '${DateFormat.yMMMd().format(range.end.subtract(const Duration(days: 1)))}',
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilterChip(
                  label: const Text('In stock only'),
                  selected: _inStockOnly,
                  onSelected: (value) => setState(() => _inStockOnly = value),
                ),
                DropdownButton<ProductProfitSort>(
                  value: _sort,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                      value: ProductProfitSort.realizedProfitDesc,
                      child: Text('Sort: realized'),
                    ),
                    DropdownMenuItem(
                      value: ProductProfitSort.potentialProfitDesc,
                      child: Text('Sort: potential'),
                    ),
                    DropdownMenuItem(
                      value: ProductProfitSort.projectedProfitDesc,
                      child: Text('Sort: projected'),
                    ),
                    DropdownMenuItem(
                      value: ProductProfitSort.quantitySoldDesc,
                      child: Text('Sort: qty sold'),
                    ),
                    DropdownMenuItem(
                      value: ProductProfitSort.nameAsc,
                      child: Text('Sort: name'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sort = value);
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (data.anyEstimated)
              const _Banner(
                message:
                    'Some realized profit rows are estimated because cost snapshots were incomplete.',
                warning: true,
              ),
            _MetricPair(
              leftLabel: 'Realized profit',
              leftValue: formatCurrency(
                minorToMoney(data.totalRealizedGrossProfitMinor),
                symbol: symbol,
              ),
              rightLabel: 'Potential remaining',
              rightValue: formatCurrency(
                minorToMoney(data.totalPotentialProfitRemainingMinor),
                symbol: symbol,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _MetricPair(
              leftLabel: 'Projected profit',
              leftValue: formatCurrency(
                minorToMoney(data.totalProjectedGrossProfitMinor),
                symbol: symbol,
              ),
              rightLabel: 'Units sold',
              rightValue: data.totalQuantitySold.toString(),
            ),
            if (canExport) ...[
              const SizedBox(height: AppSpacing.md),
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
            const SizedBox(height: AppSpacing.md),
            if (data.rows.isEmpty)
              const Text('No product profit data for this period.')
            else
              ...data.rows.map(
                (row) => Card(
                  child: ListTile(
                    title: Text(row.name),
                    subtitle: Text(
                      [
                        if (row.sku.isNotEmpty) row.sku,
                        if (row.categoryName != null) row.categoryName!,
                        'Sold ${row.quantitySold}',
                        'On hand ${row.quantityOnHand}',
                        if (row.profitIsEstimated) 'Estimated',
                      ].join(' · '),
                    ),
                    isThreeLine: true,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatCurrency(
                            minorToMoney(row.realizedGrossProfitMinor),
                            symbol: symbol,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Rem ${formatCurrency(minorToMoney(row.potentialProfitRemainingMinor), symbol: symbol)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    onTap: () => context.pushNamed(
                      AppRouteNames.productDetails,
                      pathParameters: {'productId': row.productId},
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadPdf(
    Business business,
    ({DateTime start, DateTime end}) range,
    ProductProfitReport data,
  ) async {
    setState(() => _exporting = true);
    try {
      final bytes = await ReportPdfService().buildProductProfitPdf(
        businessName: business.name,
        currencyCode: business.currency.code,
        currencySymbol: business.currency.symbol,
        start: range.start,
        end: range.end,
        report: data,
      );
      final directory = await getApplicationDocumentsDirectory();
      final file = File(
        path.join(directory.path, 'SabiBom_Product_Profit.pdf'),
      );
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: 'SabiBom Product Profit',
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportCsv(ProductProfitReport data) async {
    setState(() => _exporting = true);
    try {
      final csv = const CsvExportService().productProfitCsv(data);
      await _shareCsv(csv, 'SabiBom_Product_Profit.csv');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

class ProductExpiryReportScreen extends ConsumerStatefulWidget {
  const ProductExpiryReportScreen({super.key});

  @override
  ConsumerState<ProductExpiryReportScreen> createState() =>
      _ProductExpiryReportScreenState();
}

class _ProductExpiryReportScreenState
    extends ConsumerState<ProductExpiryReportScreen> {
  ProductExpiryStatus? _statusFilter;
  ExpiryReportSort _sort = ExpiryReportSort.expiryDateAsc;
  var _exporting = false;

  @override
  Widget build(BuildContext context) {
    final canView = ref.watch(
      hasPermissionProvider(AppPermission.viewProductExpiry),
    );
    if (!canView) {
      return const AccessDeniedScreen(
        message: 'You need permission to view product expiry.',
      );
    }

    final business = _activeBusiness(ref);
    if (business == null) {
      return const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: AppCardSkeleton(height: 200),
        ),
      );
    }

    final request = ProductExpiryReportRequest(
      businessId: business.businessId,
      businessTimezone: 'Africa/Freetown',
      statusFilter: _statusFilter,
      sort: _sort,
    );
    final report = ref.watch(productExpiryReportProvider(request));
    final canExport =
        ref.watch(hasPermissionProvider(AppPermission.exportExpiryReport)) ||
        ref.watch(hasPermissionProvider(AppPermission.exportReports));
    final canViewCost = ref.watch(
      hasPermissionProvider(AppPermission.viewCostPrice),
    );
    final canDispose = ref.watch(
      hasPermissionProvider(AppPermission.disposeExpiredStock),
    );
    final symbol = business.currency.symbol;

    return Scaffold(
      appBar: AppBar(title: const Text('Product Expiry')),
      body: report.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: AppListSkeleton(),
        ),
        error: (_, _) => AppErrorState(
          message: 'Could not load product expiry.',
          onRetry: () => ref.invalidate(productExpiryReportProvider(request)),
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _statusFilter == null,
                  onSelected: (_) => setState(() => _statusFilter = null),
                ),
                FilterChip(
                  label: const Text('Expired'),
                  selected: _statusFilter == ProductExpiryStatus.expired,
                  onSelected: (_) => setState(
                    () => _statusFilter = ProductExpiryStatus.expired,
                  ),
                ),
                FilterChip(
                  label: const Text('Today'),
                  selected: _statusFilter == ProductExpiryStatus.expiresToday,
                  onSelected: (_) => setState(
                    () => _statusFilter = ProductExpiryStatus.expiresToday,
                  ),
                ),
                FilterChip(
                  label: const Text('Soon'),
                  selected: _statusFilter == ProductExpiryStatus.expiringSoon,
                  onSelected: (_) => setState(
                    () => _statusFilter = ProductExpiryStatus.expiringSoon,
                  ),
                ),
                FilterChip(
                  label: const Text('Unknown'),
                  selected: _statusFilter == ProductExpiryStatus.notTracked,
                  onSelected: (_) => setState(
                    () => _statusFilter = ProductExpiryStatus.notTracked,
                  ),
                ),
                DropdownButton<ExpiryReportSort>(
                  value: _sort,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                      value: ExpiryReportSort.expiryDateAsc,
                      child: Text('Sort: expiry'),
                    ),
                    DropdownMenuItem(
                      value: ExpiryReportSort.quantityDesc,
                      child: Text('Sort: quantity'),
                    ),
                    DropdownMenuItem(
                      value: ExpiryReportSort.nameAsc,
                      child: Text('Sort: name'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sort = value);
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _MetricPair(
              leftLabel: 'Expired qty',
              leftValue: '${data.totalExpiredQuantity}',
              rightLabel: 'Expiring qty',
              rightValue: '${data.totalExpiringQuantity}',
            ),
            if (canViewCost) ...[
              const SizedBox(height: AppSpacing.sm),
              _MetricPair(
                leftLabel: 'Expired cost',
                leftValue: formatCurrency(
                  minorToMoney(data.totalExpiredCostMinor),
                  symbol: symbol,
                ),
                rightLabel: 'Unknown qty',
                rightValue: '${data.totalUnknownQuantity}',
              ),
            ],
            if (canExport) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: _exporting
                    ? null
                    : () => _downloadPdf(business, data),
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
            const SizedBox(height: AppSpacing.md),
            if (data.sections.isEmpty)
              const Text('No expiry-tracked batches need attention.')
            else
              ...data.sections.expand((section) {
                return [
                  Text(
                    section.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ...section.rows.map(
                    (row) => Card(
                      child: ListTile(
                        title: Text(row.productName),
                        subtitle: Text(
                          [
                            if (row.sku.isNotEmpty) row.sku,
                            'Qty ${row.quantityRemaining}',
                            if (row.expiryDate != null)
                              DateFormat.yMMMd().format(row.expiryDate!)
                            else
                              'Unknown expiry',
                            if (row.daysRemaining != null)
                              '${row.daysRemaining}d',
                            if (row.sourceNumber != null) row.sourceNumber!,
                          ].join(' · '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (canViewCost)
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 92),
                                child: Text(
                                  formatCurrency(
                                    minorToMoney(row.costValueMinor),
                                    symbol: symbol,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            if (canDispose &&
                                row.status == ProductExpiryStatus.expired &&
                                row.quantityRemaining > 0)
                              IconButton(
                                tooltip: 'Dispose expired stock',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _disposeExpiredBatch(
                                  business: business,
                                  row: row,
                                  request: request,
                                ),
                              ),
                          ],
                        ),
                        onTap: () => context.goNamed(
                          AppRouteNames.productDetails,
                          pathParameters: {'productId': row.productId},
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ];
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadPdf(Business business, ProductExpiryReport data) async {
    setState(() => _exporting = true);
    try {
      final bytes = await ReportPdfService().buildProductExpiryPdf(
        businessName: business.name,
        currencyCode: business.currency.code,
        currencySymbol: business.currency.symbol,
        report: data,
      );
      final directory = await getApplicationDocumentsDirectory();
      final file = File(
        path.join(directory.path, 'SabiBom_Product_Expiry.pdf'),
      );
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: 'SabiBom Product Expiry',
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportCsv(ProductExpiryReport data) async {
    setState(() => _exporting = true);
    try {
      final csv = const CsvExportService().productExpiryCsv(data);
      await _shareCsv(csv, 'SabiBom_Product_Expiry.csv');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _disposeExpiredBatch({
    required Business business,
    required ExpiryReportRow row,
    required ProductExpiryReportRequest request,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dispose expired stock?'),
        content: Text(
          'Remove ${row.quantityRemaining} of ${row.productName} from the '
          'selected branch inventory. The disposal remains in stock history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Dispose'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final branchId = ref.read(currentWritableBranchIdProvider);
    if (branchId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(branchWriteBlockedMessage)));
      return;
    }

    try {
      await ref
          .read(productsRepositoryProvider)
          .disposeExpiredStock(
            business.businessId,
            batchId: row.batchId,
            quantity: row.quantityRemaining,
            reason: 'Expired stock disposed from product expiry report',
            branchId: branchId,
          );
      ref.invalidate(productExpiryReportProvider(request));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expired stock disposed.')),
        );
      }
    } on ProductException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.friendlyMessage)));
      }
    }
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
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, this.warning = false});
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

enum _PiPeriod {
  today('Today'),
  thisWeek('This week'),
  thisMonth('This month'),
  thisYear('This year');

  const _PiPeriod(this.label);
  final String label;
}
