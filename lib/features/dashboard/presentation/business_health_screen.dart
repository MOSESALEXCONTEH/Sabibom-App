import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/formatting/date_range_utils.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_status_views.dart';
import '../../branches/presentation/branch_selector.dart';
import '../application/dashboard_providers.dart';
import 'widgets/dashboard_analytics_panel.dart';

class BusinessHealthScreen extends ConsumerWidget {
  const BusinessHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeBusiness = ref.watch(activeBusinessProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Business Health AI Score')),
      body: activeBusiness.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const AppErrorState(
          title: 'Could not load business health',
          message: 'Check your connection and try again.',
        ),
        data: (state) => switch (state) {
          ActiveBusinessData(:final business) => _BusinessHealthBody(
            businessId: business.businessId,
            currencyCode: business.currency.code,
            currencySymbol: business.currency.symbol,
          ),
          ActiveBusinessLoading() => const Center(
            child: CircularProgressIndicator(),
          ),
          ActiveBusinessNone() => const AppEmptyState(
            title: 'Set up your business first',
            description:
                'Business health becomes available after business setup.',
            icon: Icons.monitor_heart_outlined,
          ),
          ActiveBusinessFailure(:final message) => AppErrorState(
            title: 'Could not load business health',
            message: message,
          ),
        },
      ),
    );
  }
}

class _BusinessHealthBody extends ConsumerWidget {
  const _BusinessHealthBody({
    required this.businessId,
    required this.currencyCode,
    required this.currencySymbol,
  });

  final String businessId;
  final String currencyCode;
  final String currencySymbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(dashboardPeriodProvider);
    final request = DashboardRequest(
      businessId: businessId,
      period: period,
      currencyCode: currencyCode,
      currencySymbol: currencySymbol,
    );
    final summary = ref.watch(dashboardSummaryProvider(request));
    final periodField = DropdownButtonFormField<DashboardPeriod>(
      initialValue: period,
      decoration: const InputDecoration(
        labelText: 'Analysis period',
        prefixIcon: Icon(Icons.calendar_month_outlined),
      ),
      items: DashboardPeriod.values
          .map(
            (value) => DropdownMenuItem<DashboardPeriod>(
              value: value,
              child: Text(value.label),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        if (value != null) {
          ref.read(dashboardPeriodProvider.notifier).select(value);
        }
      },
    );
    final branchSelector = BranchSelector(
      compact: true,
      onManageBranches: () => context.pushNamed(AppRouteNames.settingsBranches),
    );
    return RefreshIndicator(
      onRefresh: () => refreshDashboard(ref, request),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: <Widget>[
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 380) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    periodField,
                    const SizedBox(height: AppSpacing.sm),
                    branchSelector,
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(child: periodField),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(width: 148, child: branchSelector),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          summary.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, _) => AppErrorState(
              title: 'Could not calculate business health',
              message: 'Check your connection and pull down to retry.',
              onRetry: () => ref.invalidate(dashboardSummaryProvider(request)),
            ),
            data: (data) => BusinessHealthPanel(summary: data),
          ),
        ],
      ),
    );
  }
}
