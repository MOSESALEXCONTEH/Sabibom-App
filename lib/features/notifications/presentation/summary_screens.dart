import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/formatting/currency_formatter.dart';
import '../../../core/theme/app_spacing.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../team/application/team_providers.dart';
import '../../team/domain/app_permission.dart';
import '../../team/presentation/team_widgets.dart';
import '../application/business_summary_service.dart';
import '../domain/business_summaries.dart';

final dailySummaryProvider =
    FutureProvider.family<DailyBusinessSummary?, String>((ref, dateKey) async {
  final active = ref.watch(activeBusinessProvider).asData?.value;
  if (active is! ActiveBusinessData) return null;
  final businessId = active.business.businessId;
  final existing =
      await BusinessSummaryService().getDaily(businessId, dateKey);
  if (existing != null) return existing;
  return BusinessSummaryService().generateDaily(
    businessId: businessId,
    day: DateTime.tryParse(dateKey) ?? DateTime.now(),
    notify: false,
  );
});

final weeklySummaryProvider =
    FutureProvider.family<WeeklyBusinessSummary?, String>((ref, weekKey) async {
  final active = ref.watch(activeBusinessProvider).asData?.value;
  if (active is! ActiveBusinessData) return null;
  final businessId = active.business.businessId;
  final existing =
      await BusinessSummaryService().getWeekly(businessId, weekKey);
  if (existing != null) return existing;
  return BusinessSummaryService().generateWeekly(
    businessId: businessId,
    weekKey: weekKey,
    notify: false,
  );
});

class DailySummaryScreen extends ConsumerWidget {
  const DailySummaryScreen({required this.dateKey, super.key});

  final String dateKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView = ref.watch(hasPermissionProvider(AppPermission.viewDailySummary)) ||
        ref.watch(hasPermissionProvider(AppPermission.viewSalesReports));
    if (!canView) {
      return const AccessDeniedScreen(
        message: 'You do not have permission to view this alert.',
      );
    }
    final canProfit = ref.watch(hasPermissionProvider(AppPermission.viewProfit));
    final async = ref.watch(dailySummaryProvider(dateKey));

    return Scaffold(
      appBar: AppBar(
        title: Text('Daily summary · $dateKey'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () async {
              final active = ref.read(activeBusinessProvider).asData?.value;
              if (active is! ActiveBusinessData) return;
              await BusinessSummaryService().generateDaily(
                businessId: active.business.businessId,
                day: DateTime.tryParse(dateKey) ?? DateTime.now(),
                notify: true,
              );
              ref.invalidate(dailySummaryProvider(dateKey));
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('The business summary is not available yet.'),
        ),
        data: (summary) {
          if (summary == null) {
            return const Center(
              child: Text('The business summary is not available yet.'),
            );
          }
          String money(int minor) => formatCurrency(minor / 100);
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(
                'Business date $dateKey',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (summary.generatedAt != null)
                Text(
                  'Generated ${DateFormat.yMMMd().add_jm().format(summary.generatedAt!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: AppSpacing.md),
              _row('Sales', money(summary.netSalesMinor)),
              _row('Transactions', '${summary.salesCount}'),
              _row('Cash', money(summary.cashSalesMinor)),
              _row('Mobile money', money(summary.mobileMoneySalesMinor)),
              _row('Bank transfer', money(summary.bankTransferSalesMinor)),
              _row('Card', money(summary.cardSalesMinor)),
              _row('Credit', money(summary.creditSalesMinor)),
              _row('Expenses', money(summary.expenseMinor)),
              if (canProfit) ...[
                _row(
                  summary.profitIsEstimated
                      ? 'Gross profit (estimated)'
                      : 'Gross profit',
                  money(summary.grossProfitMinor),
                ),
                _row(
                  summary.profitIsEstimated
                      ? 'Net profit (estimated)'
                      : 'Net profit',
                  money(summary.netProfitMinor),
                ),
              ],
              _row('Customer outstanding', money(summary.customerOutstandingMinor)),
              _row('Supplier outstanding', money(summary.supplierOutstandingMinor)),
              _row('Low stock', '${summary.lowStockCount}'),
              _row('Out of stock', '${summary.outOfStockCount}'),
              if (summary.importantEvents.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Important events',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                ...summary.importantEvents.map((e) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.circle, size: 8),
                      title: Text(e),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class WeeklyReportScreen extends ConsumerWidget {
  const WeeklyReportScreen({required this.weekKey, super.key});

  final String weekKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView = ref.watch(hasPermissionProvider(AppPermission.viewWeeklyReport)) ||
        ref.watch(hasPermissionProvider(AppPermission.viewSalesReports));
    if (!canView) {
      return const AccessDeniedScreen(
        message: 'You do not have permission to view this alert.',
      );
    }
    final canProfit = ref.watch(hasPermissionProvider(AppPermission.viewProfit));
    final async = ref.watch(weeklySummaryProvider(weekKey));
    final range = BusinessSummaryService.weekRangeFor(weekKey);
    final periodLabel =
        '${DateFormat.MMMd().format(range.start)} – ${DateFormat.MMMd().format(range.end.subtract(const Duration(days: 1)))}';

    return Scaffold(
      appBar: AppBar(
        title: Text('Weekly report · $weekKey'),
        actions: [
          IconButton(
            tooltip: 'Refresh weekly report',
            onPressed: () async {
              final active = ref.read(activeBusinessProvider).asData?.value;
              if (active is! ActiveBusinessData) return;
              await BusinessSummaryService().generateWeekly(
                businessId: active.business.businessId,
                weekKey: weekKey,
                notify: true,
              );
              ref.invalidate(weeklySummaryProvider(weekKey));
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('The business summary is not available yet.'),
        ),
        data: (summary) {
          if (summary == null) {
            return const Center(
              child: Text('The business summary is not available yet.'),
            );
          }
          String money(int minor) => formatCurrency(minor / 100);
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(
                'Week $weekKey',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Text(periodLabel, style: Theme.of(context).textTheme.bodySmall),
              if (summary.generatedAt != null)
                Text(
                  'Generated ${DateFormat.yMMMd().add_jm().format(summary.generatedAt!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: AppSpacing.md),
              _metric('Sales', money(summary.netSalesMinor)),
              _metric('Transactions', '${summary.salesCount}'),
              _metric(
                'Sales change vs prior week',
                '${summary.salesChangePercentage.toStringAsFixed(1)}%',
              ),
              _metric('Expenses', money(summary.expenseMinor)),
              _metric(
                'Expense change vs prior week',
                '${summary.expenseChangePercentage.toStringAsFixed(1)}%',
              ),
              if (canProfit) ...[
                _metric(
                  summary.profitIsEstimated
                      ? 'Gross profit (estimated)'
                      : 'Gross profit',
                  money(summary.grossProfitMinor),
                ),
                _metric(
                  summary.profitIsEstimated
                      ? 'Net profit (estimated)'
                      : 'Net profit',
                  money(summary.netProfitMinor),
                ),
              ],
              _metric('New customers', '${summary.newCustomers}'),
              _metric(
                'Customer outstanding',
                money(summary.customerOutstandingMinor),
              ),
              _metric(
                'Supplier outstanding',
                money(summary.supplierOutstandingMinor),
              ),
              _metric(
                'End of Day completed',
                '${summary.endOfDayCompletedCount}',
              ),
              _metric(
                'End of Day missing',
                '${summary.endOfDayMissingCount}',
              ),
              if (summary.cashShortageMinor > 0)
                _metric('Cash shortage total', money(summary.cashShortageMinor)),
              if (summary.cashSurplusMinor > 0)
                _metric('Cash surplus total', money(summary.cashSurplusMinor)),
              if (summary.topProducts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Top products',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                ...summary.topProducts.map((p) {
                  final name = '${p['name'] ?? 'Item'}';
                  final amount =
                      money((p['amountMinor'] as num?)?.toInt() ?? 0);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(name),
                    trailing: Text(
                      amount,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  );
                }),
              ],
              if (summary.lowStockProducts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Low stock',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                ...summary.lowStockProducts.map(
                  (p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.warning_amber_outlined, size: 18),
                    title: Text('${p['name'] ?? 'Product'}'),
                  ),
                ),
              ],
              if (summary.outOfStockProducts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Out of stock',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                ...summary.outOfStockProducts.map(
                  (p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.error_outline, size: 18),
                    title: Text('${p['name'] ?? 'Product'}'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _metric(String label, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
