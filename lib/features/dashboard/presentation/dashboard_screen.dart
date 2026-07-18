import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/formatting/currency_formatter.dart';
import '../../../core/formatting/date_range_utils.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/application/user_profile_provider.dart';
import '../../business_setup/domain/business.dart';
import '../../sabi/presentation/sabi_assistant_sheet.dart';
import '../../sabi/presentation/widgets/sabi_assistant_button.dart';
import '../application/dashboard_providers.dart';
import '../domain/dashboard_models.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeBusiness = ref.watch(activeBusinessProvider);
    final name = ref.watch(currentUserProfileProvider).asData?.value?.fullName;

    return Scaffold(
      floatingActionButton: SabiAssistantButton(
        onPressed: () => showSabiAssistantSheet(context),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        child: activeBusiness.when(
          loading: () => _BusinessDashboardSkeleton(name: name),
          error: (error, stackTrace) => _DashboardError(
            message: 'Something went wrong while loading your dashboard.',
            onRetry: () => ref.invalidate(activeBusinessProvider),
          ),
          data: (state) => switch (state) {
            ActiveBusinessLoading() => _BusinessDashboardSkeleton(name: name),
            ActiveBusinessNone() => _NoBusinessDashboard(name: name),
            ActiveBusinessFailure(:final message) => _DashboardError(
                message: message,
                onRetry: () => ref.invalidate(activeBusinessProvider),
              ),
            ActiveBusinessData(:final business) =>
              _BusinessDashboard(business: business, name: name),
          },
        ),
      ),
    );
  }
}

class _NoBusinessDashboard extends StatelessWidget {
  const _NoBusinessDashboard({this.name});
  final String? name;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        104,
      ),
      children: <Widget>[
        DashboardHeader(name: name),
        const SizedBox(height: AppSpacing.lg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.storefront_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 36,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Set up your business',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Create your business profile to start recording sales, managing stock, tracking customers and printing receipts.',
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: () => context.push(AppRoutes.businessSetup),
                  child: const Text('Set Up Business'),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'You can also set this up later from Settings.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Quick actions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.md),
        const Text('Set up a business to use these actions.'),
        const SizedBox(height: AppSpacing.sm),
        const _QuickActionGrid(enabled: false),
      ],
    );
  }
}

class _BusinessDashboard extends ConsumerWidget {
  const _BusinessDashboard({required this.business, this.name});
  final Business business;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(dashboardPeriodProvider);
    final request = DashboardRequest(
      businessId: business.businessId,
      period: period,
      currencyCode: business.currency.code,
      currencySymbol: business.currency.symbol,
    );
    final summary = ref.watch(dashboardSummaryProvider(request));
    return RefreshIndicator(
      onRefresh: () => refreshDashboard(ref, request),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          124,
        ),
        children: <Widget>[
          DashboardHeader(name: name, business: business),
          const SizedBox(height: AppSpacing.lg),
          _PeriodSelector(selected: period),
          const SizedBox(height: AppSpacing.md),
          summary.when(
            loading: () => const _SalesSummarySkeleton(),
            error: (error, stackTrace) => _SectionError(
              label: 'sales summary',
              onRetry: () => ref.invalidate(dashboardSummaryProvider(request)),
            ),
            data: (data) => _SalesSummaryCard(summary: data, period: period),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionHeader(title: 'Quick actions'),
          const SizedBox(height: AppSpacing.md),
          const _QuickActionGrid(enabled: true),
          const SizedBox(height: AppSpacing.lg),
          const _SectionHeader(title: 'Business overview'),
          const SizedBox(height: AppSpacing.md),
          summary.when(
            loading: () => const _MetricSkeleton(),
            error: (error, stackTrace) => _SectionError(
              label: 'business overview',
              onRetry: () => ref.invalidate(dashboardSummaryProvider(request)),
            ),
            data: (data) => DashboardMetricGrid(summary: data),
          ),
          const SizedBox(height: AppSpacing.lg),
          _RecentActivitySection(
            businessId: business.businessId,
            currencySymbol: business.currency.symbol,
          ),
          const SizedBox(height: AppSpacing.lg),
          _LowStockSection(businessId: business.businessId),
          const SizedBox(height: AppSpacing.lg),
          _CustomerBalancesSection(
            businessId: business.businessId,
            currencySymbol: business.currency.symbol,
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({required this.name, this.business, super.key});
  final String? name;
  final Business? business;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final greetingSize = constraints.maxWidth < 380
          ? 22.0
          : constraints.maxWidth <= 450
          ? 24.0
          : 26.0;
      final businessNameStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: constraints.maxWidth < 380 ? 14 : 15,
        color: AppColors.mutedText,
        fontWeight: FontWeight.w600,
      );

      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 48,
          height: 48,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: const Color(0xFFF0ECFF),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.45)),
          ),
          child: ClipOval(
            child: business?.logoUrl?.isNotEmpty == true
                ? Image.network(business!.logoUrl!, fit: BoxFit.cover)
                : Center(
                    child: Text(
                      _businessInitials(business?.name),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                dashboardGreeting(DateTime.now(), name),
                key: const Key('dashboard-greeting'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: greetingSize,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (business != null)
                InkWell(
                  onTap: () => context.push(AppRoutes.businessProfile),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          business!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: businessNameStyle,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.unfold_more, size: 16, color: AppColors.mutedText),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          label: 'Notifications',
          button: true,
          child: IconButton.filledTonal(
            constraints: const BoxConstraints.tightFor(width: 42, height: 42),
            padding: EdgeInsets.zero,
            tooltip: 'Notifications',
            onPressed: () => context.push(AppRoutes.notifications),
            icon: const Icon(Icons.notifications_none, size: 22),
          ),
        ),
        const SizedBox(width: 6),
        Semantics(
          label: 'Settings',
          button: true,
          child: IconButton.filledTonal(
            constraints: const BoxConstraints.tightFor(width: 42, height: 42),
            padding: EdgeInsets.zero,
            tooltip: 'Settings',
            onPressed: () => context.push(AppRoutes.settings),
            icon: const Icon(Icons.settings_outlined, size: 22),
          ),
        ),
      ],
      );
    },
  );
}

class _PeriodSelector extends ConsumerWidget {
  const _PeriodSelector({required this.selected});
  final DashboardPeriod selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
    label: 'Dashboard period selector',
    child: Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: DashboardPeriod.values.map((period) {
          final isSelected = period == selected;
          return Expanded(
            child: Semantics(
              selected: isSelected,
              button: true,
              label: period.label,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => ref.read(dashboardPeriodProvider.notifier).select(period),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    period.label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ),
  );
}

class _SalesSummaryCard extends StatelessWidget {
  const _SalesSummaryCard({required this.summary, required this.period});
  final DashboardSummary summary;
  final DashboardPeriod period;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 242,
    child: DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[Color(0xFF5B3DF5), Color(0xFF7448F7)],
      ),
      borderRadius: BorderRadius.circular(AppRadii.card),
      boxShadow: const <BoxShadow>[
        BoxShadow(
          color: Color(0x335B3DF5),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Stack(
        children: <Widget>[
          const Positioned(right: -18, bottom: -10, child: _SalesChartDecoration()),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(color: Color(0x33FFFFFF), shape: BoxShape.circle),
                child: const Icon(Icons.trending_up_rounded, color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(period.salesLabel, style: const TextStyle(color: Color(0xDDFFFFFF), fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(formatCurrency(summary.totalSales, code: summary.currencyCode, symbol: summary.currencySymbol), style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
              Text('${summary.orderCount} ${summary.orderCount == 1 ? 'order' : 'orders'}', style: const TextStyle(color: Color(0xEEFFFFFF), fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(summary.orderCount == 0 ? 'Start recording sales to see your progress.' : 'Sales activity for this period.', style: const TextStyle(color: Color(0xCCFFFFFF))),
            ],
          ),
        ],
      ),
    ),
    ),
  );
}

class _SalesChartDecoration extends StatelessWidget {
  const _SalesChartDecoration();

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: 0.22,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: const <Widget>[
        _ChartBar(height: 62),
        _ChartBar(height: 96),
        _ChartBar(height: 132),
      ],
    ),
  );
}

class _ChartBar extends StatelessWidget {
  const _ChartBar({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: 25,
    height: height,
    margin: const EdgeInsets.only(left: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
  );
}

class DashboardMetricGrid extends StatelessWidget {
  const DashboardMetricGrid({required this.summary, super.key});
  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 600 ? 4 : 2;
      final width = MediaQuery.sizeOf(context).width;
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      final metricCardHeight = textScale > 1.15
          ? 194.0
          : width < 370
          ? 180.0
          : 176.0;
      return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: columns,
        mainAxisExtent: metricCardHeight,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        children: <Widget>[
          _MetricCard(
            label: 'Orders',
            value: '${summary.orderCount}',
            icon: Icons.receipt_long_outlined,
            accent: AppColors.primary,
            detail: summary.orderCount == 0 ? 'No orders yet' : 'Recorded this period',
            isCurrency: false,
            onTap: () => context.go(AppRoutes.sales),
          ),
          _MetricCard(
            label: 'Customers',
            value: '${summary.customerCount}',
            icon: Icons.people_outline,
            accent: const Color(0xFF12B76A),
            detail: summary.customerCount == 0 ? 'No customers yet' : 'Saved customers',
            isCurrency: false,
            onTap: () => context.go(AppRoutes.customers),
          ),
          _MetricCard(
            label: 'Low Stock',
            value: '${summary.lowStockCount}',
            icon: Icons.warning_amber_outlined,
            accent: const Color(0xFFF79009),
            detail: summary.lowStockCount == 0 ? 'Stock looks good' : 'Needs attention',
            isCurrency: false,
            onTap: () => context.go(AppRoutes.products),
          ),
          _MetricCard(
            label: 'Expenses',
            value: formatCurrency(
              summary.totalExpenses,
              code: summary.currencyCode,
              symbol: summary.currencySymbol,
            ),
            icon: Icons.payments_outlined,
            accent: const Color(0xFF2E90FA),
            detail: summary.totalExpenses == 0 ? 'No expenses yet' : 'This period',
            isCurrency: true,
            onTap: () => context.push(AppRoutes.expenses),
          ),
        ],
      );
    },
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.detail,
    required this.isCurrency,
    required this.onTap,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final String detail;
  final bool isCurrency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$label: $value',
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth < 170 ? 14.0 : 16.0;
            return Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(icon, size: 22, color: accent),
              ),
              const SizedBox(height: 12),
              if (isCurrency)
                SizedBox(
                  height: 30,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontSize: 27,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              else
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: 28,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 15,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.mutedText,
                  fontSize: 12,
                  height: 1.1,
                ),
              ),
            ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        mainAxisExtent: MediaQuery.sizeOf(context).width < 360 ? 136 : 128,
        children: <Widget>[
          _QuickAction(Icons.add_shopping_cart_outlined, 'New Sale', 'Create a new transaction', enabled, () => context.go(AppRoutes.sales)),
          _QuickAction(Icons.add_box_outlined, 'Add Product', 'Update your inventory', enabled, () => context.go(AppRoutes.products)),
          _QuickAction(Icons.person_add_alt_outlined, 'Add Customer', 'Save customer details', enabled, () => context.go(AppRoutes.customers)),
          _QuickAction(Icons.add_card_outlined, 'Record Expense', 'Track business spending', enabled, () => context.push(AppRoutes.expenses)),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      _SabiQuickAction(enabled: enabled),
    ],
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(this.icon, this.label, this.subtitle, this.enabled, this.onTap);
  final IconData icon;
  final String label;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0ECFF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 17, color: AppColors.primary),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, size: 18, color: AppColors.mutedText),
                ],
              ),
              const Spacer(),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 15,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.mutedText,
                  fontSize: 11,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SabiQuickAction extends StatelessWidget {
  const _SabiQuickAction({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFF0ECFF),
      borderRadius: BorderRadius.circular(AppRadii.card),
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: enabled ? () => showSabiAssistantSheet(context) : null,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              const CircleAvatar(
                backgroundColor: Color(0xFFDCD2FF),
                child: Icon(Icons.auto_awesome, color: Color(0xFF5B3DF5)),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Ask Sabi', style: TextStyle(fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('Get quick answers about your business'),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF5B3DF5)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RecentActivitySection extends ConsumerWidget {
  const _RecentActivitySection({required this.businessId, required this.currencySymbol});
  final String businessId;
  final String currencySymbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(recentActivityProvider(businessId));
    return _Section(
      title: 'Recent Activity',
      action: 'View All',
      onAction: () => context.push(AppRoutes.activity),
      child: activity.when(
        loading: () => const _SectionLoading(),
        error: (error, stackTrace) => _SectionError(
          label: 'recent activity',
          onRetry: () => ref.invalidate(recentActivityProvider(businessId)),
        ),
        data: (items) => items.isEmpty
            ? const _EmptySection(
                message: 'No activity yet',
                description: 'Your latest sales, expenses and stock updates will appear here.',
              )
            : Column(
                children: items
                    .map(
                      (item) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history),
                        title: Text(item.title),
                        subtitle: Text(item.subtitle),
                        trailing: item.amount == null
                            ? null
                            : Text(formatCurrency(item.amount, symbol: currencySymbol)),
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }
}

class _LowStockSection extends ConsumerWidget {
  const _LowStockSection({required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(lowStockProvider(businessId));
    return _Section(
      title: 'Low Stock',
      action: 'View products',
      onAction: () => context.go(AppRoutes.products),
      child: products.when(
        loading: () => const _SectionLoading(),
        error: (error, stackTrace) => _SectionError(
          label: 'low stock',
          onRetry: () => ref.invalidate(lowStockProvider(businessId)),
        ),
        data: (items) => items.isEmpty
            ? const _EmptySection(message: 'Stock levels look good')
            : Column(
                children: items
                    .map(
                      (product) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.warning_amber_outlined, color: Color(0xFFF79009)),
                        title: Text(product.name),
                        trailing: Text('${product.quantity} ${product.unit}'),
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }
}

class _CustomerBalancesSection extends ConsumerWidget {
  const _CustomerBalancesSection({required this.businessId, required this.currencySymbol});
  final String businessId;
  final String currencySymbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customerBalancesProvider(businessId));
    return _Section(
      title: 'Customer Balances',
      action: 'View customers',
      onAction: () => context.go(AppRoutes.customers),
      child: customers.when(
        loading: () => const _SectionLoading(),
        error: (error, stackTrace) => _SectionError(
          label: 'customer balances',
          onRetry: () => ref.invalidate(customerBalancesProvider(businessId)),
        ),
        data: (items) => items.isEmpty
            ? const _EmptySection(message: 'No outstanding balances')
            : Column(
                children: items
                    .map(
                      (customer) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: Text(customer.name),
                        trailing: Text(
                          formatCurrency(
                            customer.balance,
                            code: customer.currencyCode,
                            symbol: currencySymbol,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.action, this.onAction});
  final String title;
  final Widget child;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Row(children: <Widget>[
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
      ]),
      Card(child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: child)),
    ],
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
  );
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message, this.description});
  final String message;
  final String? description;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Text(message, style: Theme.of(context).textTheme.titleSmall),
      if (description != null) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        Text(description!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ],
    ],
  );
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.label, required this.onRetry});
  final String label;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(child: Text('Could not load $label.')),
      TextButton(onPressed: onRetry, child: const Text('Retry')),
    ],
  );
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Card(
      margin: const EdgeInsets.all(AppSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    ),
  );
}

class _BusinessDashboardSkeleton extends StatelessWidget {
  const _BusinessDashboardSkeleton({this.name});
  final String? name;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: <Widget>[
        DashboardHeader(name: name),
        const SizedBox(height: AppSpacing.lg),
        const _Block(height: 40),
        const SizedBox(height: AppSpacing.md),
        const _SalesSummarySkeleton(),
        const SizedBox(height: AppSpacing.lg),
        const _Block(height: 40),
        const SizedBox(height: AppSpacing.md),
        const _Block(height: 80),
        const SizedBox(height: AppSpacing.lg),
        const _Block(height: 40),
        const SizedBox(height: AppSpacing.md),
        const _MetricSkeleton(),
      ],
    );
  }
}

class _SalesSummarySkeleton extends StatelessWidget {
  const _SalesSummarySkeleton();
  @override
  Widget build(BuildContext context) => const _Block(height: 180);
}

class _MetricSkeleton extends StatelessWidget {
  const _MetricSkeleton();
  @override
  Widget build(BuildContext context) => const _Block(height: 180);
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();
  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 56,
    child: Center(child: CircularProgressIndicator()),
  );
}

class _Block extends StatelessWidget {
  const _Block({required this.height});
  final double height;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.border,
      borderRadius: BorderRadius.circular(AppRadii.card),
    ),
    child: SizedBox(height: height),
  );
}

String dashboardGreeting(DateTime now, String? fullName) {
  final prefix = now.hour < 12
      ? 'Good morning'
      : now.hour < 17
      ? 'Good afternoon'
      : 'Good evening';
  final firstName = fullName?.trim().split(RegExp(r'\s+')).first;
  return firstName == null || firstName.isEmpty ? prefix : '$prefix, $firstName';
}

String _businessInitials(String? businessName) {
  final words = businessName
      ?.trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words == null || words.isEmpty) return 'SB';
  return words.take(2).map((word) => word[0].toUpperCase()).join();
}
