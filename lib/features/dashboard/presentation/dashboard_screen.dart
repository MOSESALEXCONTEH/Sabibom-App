import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/formatting/currency_formatter.dart';
import '../../../core/formatting/date_range_utils.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../../core/widgets/app_tab_page_scaffold.dart';
import '../../auth/application/user_profile_provider.dart';
import '../../business_setup/domain/business.dart';
import '../../business_setup/domain/business_operating_model.dart';
import '../../business_setup/application/business_experience_providers.dart';
import '../../notifications/presentation/attention_section.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../branches/presentation/branch_selector.dart';
import '../../products/application/products_providers.dart';
import '../../products/domain/product.dart';
import '../../setup/presentation/setup_checklist_card.dart';
import '../../sabi/presentation/sabi_navigation.dart';
import '../../sabi/presentation/widgets/sabi_assistant_button.dart';
import '../../sales/domain/sale_models.dart';
import '../../sales/presentation/sales_navigation.dart';
import '../../team/application/team_providers.dart';
import '../../team/domain/app_permission.dart';
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
            ActiveBusinessData(:final business) => _BusinessDashboard(
              business: business,
              name: name,
            ),
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
        AppTabChrome.bottomInset,
      ),
      children: <Widget>[
        DashboardHeader(name: name),
        const SizedBox(height: AppSpacing.lg),
        AppEmptyState(
          title: 'Set up your business',
          description:
              'Create your business profile to start recording sales, managing stock, tracking customers and printing receipts.',
          icon: Icons.storefront_outlined,
          actionLabel: 'Set Up Business',
          onAction: () => context.push(AppRoutes.businessSetup),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Quick actions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Set up a business to use these actions.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.mutedTextColor),
        ),
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
    final terminology = BusinessTerminology.forModel(business.operatingModel);
    final capabilities = BusinessCapabilities(business.operatingModel);
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
          AppTabChrome.bottomInset + 24,
        ),
        children: <Widget>[
          DashboardHeader(name: name, business: business),
          if (business.isDemo) ...[
            const SizedBox(height: AppSpacing.sm),
            Material(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text(
                  'Demo Business — Sample data only. Not real customer or sales records.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const SetupChecklistCard(),
          const SizedBox(height: AppSpacing.lg),
          _PeriodSelector(selected: period),
          const SizedBox(height: AppSpacing.md),
          summary.when(
            loading: () => const _SalesSummarySkeleton(),
            error: (error, stackTrace) => _SectionError(
              label: 'sales summary',
              onRetry: () => ref.invalidate(dashboardSummaryProvider(request)),
            ),
            data: (data) => _SalesSummaryCard(
              summary: data,
              period: period,
              terminology: terminology,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          summary.when(
            loading: () => const AppCardSkeleton(height: 190),
            error: (_, _) => const SizedBox.shrink(),
            data: (data) => _BusinessAnalyticsPanel(
              summary: data,
              period: period,
              terminology: terminology,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          NeedsAttentionSection(businessId: business.businessId),
          const SizedBox(height: AppSpacing.lg),
          const _SectionHeader(title: 'Quick actions'),
          const SizedBox(height: AppSpacing.md),
          _QuickActionGrid(
            enabled: true,
            terminology: terminology,
            capabilities: capabilities,
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionHeader(title: 'Business overview'),
          const SizedBox(height: AppSpacing.md),
          summary.when(
            loading: () => const _MetricSkeleton(),
            error: (error, stackTrace) => _SectionError(
              label: 'business overview',
              onRetry: () => ref.invalidate(dashboardSummaryProvider(request)),
            ),
            data: (data) => DashboardMetricGrid(
              summary: data,
              terminology: terminology,
              capabilities: capabilities,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionHeader(title: 'Finance'),
          const SizedBox(height: AppSpacing.md),
          _FinanceShortcuts(capabilities: capabilities),
          const SizedBox(height: AppSpacing.lg),
          _RecentActivitySection(
            businessId: business.businessId,
            currencySymbol: business.currency.symbol,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (capabilities.managesInventory) ...<Widget>[
            _LowStockSection(businessId: business.businessId),
            const SizedBox(height: AppSpacing.lg),
          ],
          _CustomerBalancesSection(
            businessId: business.businessId,
            currencySymbol: business.currency.symbol,
            terminology: terminology,
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
      final greetingSize = 20.0;
      final businessNameStyle = Theme.of(context).textTheme.bodyMedium
          ?.copyWith(
            fontSize: constraints.maxWidth < 380 ? 14 : 15,
            color: context.mutedTextColor,
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
              color: context.brandTint,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.45),
              ),
            ),
            child: ClipOval(
              child:
                  (business?.logoUrl?.isNotEmpty == true ||
                      business?.logoCid?.isNotEmpty == true)
                  ? AppNetworkImage(
                      url: business?.logoUrl ?? '',
                      cid: business?.logoCid,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.circular(22),
                      fallbackIcon: Icons.storefront_outlined,
                    )
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: greetingSize,
                    height: 1.2,
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
                        const Icon(
                          Icons.unfold_more,
                          size: 16,
                          color: AppColors.mutedText,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const _NotificationBellButton(),
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

class _NotificationBellButton extends ConsumerWidget {
  const _NotificationBellButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(branchUnreadNotificationsCountProvider);
    final badge = count <= 0 ? null : (count > 99 ? '99+' : '$count');

    return Semantics(
      label: badge == null ? 'Notifications' : 'Notifications, $badge unread',
      button: true,
      child: IconButton.filledTonal(
        constraints: const BoxConstraints.tightFor(width: 42, height: 42),
        padding: EdgeInsets.zero,
        tooltip: 'Notifications',
        onPressed: () => context.push(AppRoutes.notifications),
        icon: Badge(
          isLabelVisible: badge != null,
          label: badge == null
              ? null
              : Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
          child: const Icon(Icons.notifications_none, size: 22),
        ),
      ),
    );
  }
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
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: context.borderColor),
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
                onTap: () =>
                    ref.read(dashboardPeriodProvider.notifier).select(period),
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
                      color: isSelected ? Colors.white : context.textColor,
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
  const _SalesSummaryCard({
    required this.summary,
    required this.period,
    required this.terminology,
  });
  final DashboardSummary summary;
  final DashboardPeriod period;
  final BusinessTerminology terminology;

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
            const Positioned(
              right: -18,
              bottom: -10,
              child: _SalesChartDecoration(),
            ),
            Positioned(
              right: -8,
              top: -8,
              width: 164,
              child: Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.white24,
                  colorScheme: Theme.of(context).colorScheme.copyWith(
                    onSurface: Colors.white,
                    onSurfaceVariant: Colors.white70,
                  ),
                ),
                child: IconTheme(
                  data: const IconThemeData(color: Colors.white),
                  child: BranchSelector(
                    compact: true,
                    transparent: true,
                    onManageBranches: () =>
                        context.pushNamed(AppRouteNames.settingsBranches),
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Color(0x33FFFFFF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.trending_up_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  period.salesLabel.replaceFirst('Sales', terminology.sales),
                  style: const TextStyle(
                    color: Color(0xDDFFFFFF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatCurrency(
                          summary.totalSales,
                          code: summary.currencyCode,
                          symbol: summary.currencySymbol,
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 52,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  '${summary.orderCount} ${summary.orderCount == 1 ? 'order' : 'orders'}',
                  style: const TextStyle(
                    color: Color(0xEEFFFFFF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary.orderCount == 0
                      ? 'Start recording ${terminology.sales.toLowerCase()} to see your progress.'
                      : '${terminology.sales} activity for this period.',
                  style: const TextStyle(color: Color(0xCCFFFFFF)),
                ),
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

class _BusinessAnalyticsPanel extends StatelessWidget {
  const _BusinessAnalyticsPanel({
    required this.summary,
    required this.period,
    required this.terminology,
  });

  final DashboardSummary summary;
  final DashboardPeriod period;
  final BusinessTerminology terminology;

  @override
  Widget build(BuildContext context) {
    final sales = summary.totalSales;
    final expenses = summary.totalExpenses;
    final operatingResult = sales - expenses;
    final averageOrder = summary.orderCount == 0
        ? 0.0
        : sales / summary.orderCount;
    final scale = <double>[
      sales.abs(),
      expenses.abs(),
      1,
    ].reduce((largest, value) => value > largest ? value : largest);
    String money(double value) => formatCurrency(
      value,
      code: summary.currencyCode,
      symbol: summary.currencySymbol,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${period.label} performance',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(
                  Icons.analytics_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _AnalyticsBar(
              label: terminology.sales,
              value: money(sales),
              fraction: sales.abs() / scale,
              color: AppColors.primary,
            ),
            const SizedBox(height: AppSpacing.sm),
            _AnalyticsBar(
              label: 'Expenses',
              value: money(expenses),
              fraction: expenses.abs() / scale,
              color: AppColors.warning,
            ),
            const Divider(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                Expanded(
                  child: _AnalyticsValue(
                    label: 'Operating result',
                    value: money(operatingResult),
                    positive: operatingResult >= 0,
                  ),
                ),
                Expanded(
                  child: _AnalyticsValue(
                    label: 'Average order',
                    value: money(averageOrder),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsBar extends StatelessWidget {
  const _AnalyticsBar({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
  });

  final String label;
  final String value;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: fraction.clamp(0, 1),
          minHeight: 8,
          color: color,
          backgroundColor: color.withValues(alpha: 0.12),
        ),
      ),
    ],
  );
}

class _AnalyticsValue extends StatelessWidget {
  const _AnalyticsValue({
    required this.label,
    required this.value,
    this.positive,
  });

  final String label;
  final String value;
  final bool? positive;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: positive == null
                ? null
                : positive!
                ? AppColors.secondary
                : AppColors.danger,
          ),
        ),
      ),
    ],
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
  const DashboardMetricGrid({
    required this.summary,
    this.terminology = const BusinessTerminology.product(),
    this.capabilities = const BusinessCapabilities(
      BusinessOperatingModel.product,
    ),
    super.key,
  });
  final DashboardSummary summary;
  final BusinessTerminology terminology;
  final BusinessCapabilities capabilities;

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
            detail: summary.orderCount == 0
                ? 'No orders yet'
                : 'Recorded this period',
            isCurrency: false,
            onTap: () => context.go(AppRoutes.sales),
          ),
          _MetricCard(
            label: terminology.customers,
            value: '${summary.customerCount}',
            icon: Icons.people_outline,
            accent: const Color(0xFF12B76A),
            detail: summary.customerCount == 0
                ? 'No ${terminology.customers.toLowerCase()} yet'
                : 'Saved ${terminology.customers.toLowerCase()}',
            isCurrency: false,
            onTap: () => context.go(AppRoutes.customers),
          ),
          if (capabilities.managesInventory)
            _MetricCard(
              label: 'Low Stock',
              value: '${summary.lowStockCount}',
              icon: Icons.warning_amber_outlined,
              accent: const Color(0xFFF79009),
              detail: summary.lowStockCount == 0
                  ? 'Stock looks good'
                  : 'Needs attention',
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
            detail: summary.totalExpenses == 0
                ? 'No expenses yet'
                : 'This period',
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
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 22, color: accent),
                  ),
                  const SizedBox(height: 12),
                  if (isCurrency)
                    SizedBox(
                      height: 30,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: _AnimatedMetricValue(value: value, fontSize: 27),
                      ),
                    )
                  else
                    _AnimatedMetricValue(value: value, fontSize: 28),
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

class _AnimatedMetricValue extends StatelessWidget {
  const _AnimatedMetricValue({required this.value, required this.fontSize});

  final String value;
  final double fontSize;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: AppMotion.resolve(context, AppMotion.standard),
    switchInCurve: AppMotion.entranceCurve,
    switchOutCurve: Curves.easeIn,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: Text(
      value,
      key: ValueKey<String>(value),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        fontSize: fontSize,
        height: 1,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _FinanceShortcuts extends ConsumerWidget {
  const _FinanceShortcuts({required this.capabilities});

  final BusinessCapabilities capabilities;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canViewExpiry = ref.watch(
      hasPermissionProvider(AppPermission.viewProductExpiry),
    );
    final canViewProfit =
        ref.watch(hasPermissionProvider(AppPermission.viewProductProfit)) ||
        ref.watch(hasPermissionProvider(AppPermission.viewProfit));
    final canViewPotential = ref.watch(
      hasPermissionProvider(AppPermission.viewProductPotentialProfit),
    );
    final canViewCost = ref.watch(
      hasPermissionProvider(AppPermission.viewCostPrice),
    );
    final active = ref.watch(activeBusinessProvider).asData?.value;
    final businessId = active is ActiveBusinessData
        ? active.business.businessId
        : '';
    final products = businessId.isEmpty || !capabilities.managesInventory
        ? const AsyncValue<List<Product>>.data(<Product>[])
        : ref.watch(productsListProvider(businessId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (capabilities.managesInventory)
          products.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (items) {
              final expiring = items
                  .where(
                    (p) =>
                        p.tracksExpiry &&
                        (p.expiryStatus == ProductExpiryStatus.expiringSoon ||
                            p.expiryStatus ==
                                ProductExpiryStatus.expiresToday ||
                            p.expiringQuantity > 0),
                  )
                  .length;
              final expired = items
                  .where(
                    (p) =>
                        p.tracksExpiry &&
                        (p.expiredQuantity > 0 ||
                            p.expiryStatus == ProductExpiryStatus.expired),
                  )
                  .length;
              final lowStock = items.where((p) => p.isLowStock).length;
              final stockValue = items.fold<int>(
                0,
                (sum, p) => sum + p.stockCostValueMinor,
              );
              final expectedRevenue = items.fold<int>(
                0,
                (sum, p) => sum + p.expectedStockRevenueMinor,
              );
              final potential = items.fold<int>(
                0,
                (sum, p) => sum + p.potentialProfitRemainingMinor,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (canViewExpiry || canViewLowStock(ref))
                    Card(
                      child: ListTile(
                        title: const Text('Inventory attention'),
                        subtitle: Text(
                          [
                            if (canViewExpiry) '$expiring expiring soon',
                            if (canViewExpiry) '$expired expired',
                            '$lowStock low stock',
                          ].join(' · '),
                        ),
                        trailing: canViewExpiry
                            ? TextButton(
                                onPressed: () => context.pushNamed(
                                  AppRouteNames.reportProductExpiry,
                                ),
                                child: const Text('Expiry'),
                              )
                            : null,
                      ),
                    ),
                  if ((canViewProfit || canViewPotential) && canViewCost)
                    Card(
                      child: ListTile(
                        title: const Text('Profit opportunity'),
                        subtitle: Text(
                          'Stock ${formatCurrency(minorToMoney(stockValue))} · '
                          'Expected ${formatCurrency(minorToMoney(expectedRevenue))} · '
                          'Est. remaining ${formatCurrency(minorToMoney(potential))}',
                        ),
                        trailing: TextButton(
                          onPressed: () => context.pushNamed(
                            AppRouteNames.reportProductProfit,
                          ),
                          child: const Text('Profit'),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            ActionChip(
              avatar: const Icon(Icons.trending_up, size: 18),
              label: const Text('Profit & Loss'),
              onPressed: () =>
                  context.pushNamed(AppRouteNames.reportProfitLoss),
            ),
            if (capabilities.managesInventory &&
                (canViewProfit || canViewPotential))
              ActionChip(
                avatar: const Icon(Icons.insights_outlined, size: 18),
                label: const Text('Product Profit'),
                onPressed: () =>
                    context.pushNamed(AppRouteNames.reportProductProfit),
              ),
            if (capabilities.managesInventory && canViewExpiry)
              ActionChip(
                avatar: const Icon(Icons.event_busy_outlined, size: 18),
                label: const Text('Expiry Report'),
                onPressed: () =>
                    context.pushNamed(AppRouteNames.reportProductExpiry),
              ),
            if (capabilities.managesPurchases) ...<Widget>[
              ActionChip(
                avatar: const Icon(Icons.local_shipping_outlined, size: 18),
                label: const Text('Suppliers'),
                onPressed: () => context.pushNamed(AppRouteNames.suppliers),
              ),
              ActionChip(
                avatar: const Icon(Icons.shopping_cart_outlined, size: 18),
                label: const Text('Purchases'),
                onPressed: () => context.pushNamed(AppRouteNames.purchases),
              ),
            ],
            ActionChip(
              avatar: const Icon(Icons.bar_chart_outlined, size: 18),
              label: const Text('Reports'),
              onPressed: () => context.pushNamed(AppRouteNames.reports),
            ),
          ],
        ),
      ],
    );
  }

  bool canViewLowStock(WidgetRef ref) =>
      ref.watch(hasPermissionProvider(AppPermission.viewLowStockAlerts));
}

class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid({
    required this.enabled,
    this.terminology = const BusinessTerminology.product(),
    this.capabilities = const BusinessCapabilities(
      BusinessOperatingModel.product,
    ),
  });
  final bool enabled;
  final BusinessTerminology terminology;
  final BusinessCapabilities capabilities;

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
          _QuickAction(
            Icons.add_shopping_cart_outlined,
            'New ${terminology.sale}',
            'Create a new transaction',
            enabled,
            () => context.go(AppRoutes.sales),
          ),
          _QuickAction(
            Icons.add_box_outlined,
            'Add ${terminology.product}',
            capabilities.managesInventory
                ? 'Update your inventory'
                : 'Add to your service list',
            enabled,
            () => context.go(AppRoutes.products),
          ),
          _QuickAction(
            Icons.person_add_alt_outlined,
            'Add ${terminology.customer}',
            'Save ${terminology.customer.toLowerCase()} details',
            enabled,
            () => context.go(AppRoutes.customers),
          ),
          _QuickAction(
            Icons.add_card_outlined,
            'Record Expense',
            'Track business spending',
            enabled,
            () => context.push(AppRoutes.expenses),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      _SabiQuickAction(enabled: enabled),
    ],
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(
    this.icon,
    this.label,
    this.subtitle,
    this.enabled,
    this.onTap,
  );
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
                      color: context.brandTint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      size: 17,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColors.mutedText,
                  ),
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
      color: context.brandTint,
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
              CircleAvatar(
                backgroundColor: context.brandTintStrong,
                child: Icon(
                  Icons.auto_awesome,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Ask Sabi',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
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
  const _RecentActivitySection({
    required this.businessId,
    required this.currencySymbol,
  });
  final String businessId;
  final String currencySymbol;

  void _openActivity(BuildContext context, DashboardActivity item) {
    final referenceId = item.referenceId?.trim();
    if (referenceId == null || referenceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This activity cannot be opened because its reference is missing.',
          ),
        ),
      );
      return;
    }
    switch (item.type) {
      case DashboardActivityType.sale:
        SalesNavigation.openSaleDetails(context, referenceId);
      case DashboardActivityType.customerPayment:
        context.pushNamed(
          AppRouteNames.customerDetails,
          pathParameters: <String, String>{'customerId': referenceId},
        );
      case DashboardActivityType.productAdded:
      case DashboardActivityType.stockAdjustment:
        context.pushNamed(
          AppRouteNames.productDetails,
          pathParameters: <String, String>{'productId': referenceId},
        );
      case DashboardActivityType.expense:
      case DashboardActivityType.other:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This activity cannot be opened yet.')),
        );
    }
  }

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
                description:
                    'Your latest sales, expenses and stock updates will appear here.',
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
                            : Text(
                                formatCurrency(
                                  item.amount,
                                  symbol: currencySymbol,
                                ),
                              ),
                        onTap: () => _openActivity(context, item),
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
                        leading: const Icon(
                          Icons.warning_amber_outlined,
                          color: Color(0xFFF79009),
                        ),
                        title: Text(product.name),
                        trailing: Text('${product.quantity} ${product.unit}'),
                        onTap: () => context.pushNamed(
                          AppRouteNames.productDetails,
                          pathParameters: {'productId': product.id},
                        ),
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }
}

class _CustomerBalancesSection extends ConsumerWidget {
  const _CustomerBalancesSection({
    required this.businessId,
    required this.currencySymbol,
    required this.terminology,
  });
  final String businessId;
  final String currencySymbol;
  final BusinessTerminology terminology;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customerBalancesProvider(businessId));
    return _Section(
      title: '${terminology.customer} Balances',
      action: 'View ${terminology.customers.toLowerCase()}',
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
  const _Section({
    required this.title,
    required this.child,
    this.action,
    this.onAction,
  });
  final String title;
  final Widget child;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: child,
        ),
      ),
    ],
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
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
        Text(
          description!,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
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
  Widget build(BuildContext context) => AppErrorState(
    title: 'Unable to load dashboard',
    message: message,
    onRetry: onRetry,
  );
}

class _BusinessDashboardSkeleton extends StatelessWidget {
  const _BusinessDashboardSkeleton({this.name});
  final String? name;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppTabChrome.bottomInset,
      ),
      children: <Widget>[
        DashboardHeader(name: name),
        const SizedBox(height: AppSpacing.lg),
        const AppCardSkeleton(height: 40),
        const SizedBox(height: AppSpacing.md),
        const AppCardSkeleton(height: 180),
        const SizedBox(height: AppSpacing.lg),
        const AppCardSkeleton(height: 40),
        const SizedBox(height: AppSpacing.md),
        const AppCardSkeleton(height: 80),
        const SizedBox(height: AppSpacing.lg),
        const AppCardSkeleton(height: 40),
        const SizedBox(height: AppSpacing.md),
        const AppCardSkeleton(height: 180),
      ],
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();
  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 72, child: AppCardSkeleton(height: 56));
}

class _SalesSummarySkeleton extends StatelessWidget {
  const _SalesSummarySkeleton();

  @override
  Widget build(BuildContext context) => const AppCardSkeleton(height: 242);
}

class _MetricSkeleton extends StatelessWidget {
  const _MetricSkeleton();

  @override
  Widget build(BuildContext context) => const AppCardSkeleton(height: 180);
}

String dashboardGreeting(DateTime now, String? fullName) {
  final prefix = now.hour < 12
      ? 'Good morning'
      : now.hour < 17
      ? 'Good afternoon'
      : 'Good evening';
  final firstName = fullName?.trim().split(RegExp(r'\s+')).first;
  return firstName == null || firstName.isEmpty
      ? prefix
      : '$prefix, $firstName';
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
