import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/formatting/currency_formatter.dart';
import '../../../../core/formatting/date_range_utils.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../branches/presentation/branch_selector.dart';
import '../../../business_setup/application/business_experience_providers.dart';
import '../../domain/dashboard_analytics.dart';
import '../../domain/dashboard_models.dart';

class DashboardSalesAnalytics extends StatelessWidget {
  const DashboardSalesAnalytics({
    required this.summary,
    required this.period,
    required this.terminology,
    super.key,
  });

  final DashboardSummary summary;
  final DashboardPeriod period;
  final BusinessTerminology terminology;

  @override
  Widget build(BuildContext context) {
    final change = summary.salesChangePercent;
    final changeColor = (change ?? 0) >= 0
        ? const Color(0xFF22A85A)
        : Theme.of(context).colorScheme.error;
    String money(double value) => formatCurrency(
      value,
      code: summary.currencyCode,
      symbol: summary.currencySymbol,
    );

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${terminology.sales} analytics',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      period.salesLabel.replaceFirst(
                        'Sales',
                        terminology.sales,
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 148,
                child: BranchSelector(
                  compact: true,
                  transparent: true,
                  onManageBranches: () =>
                      context.pushNamed(AppRouteNames.settingsBranches),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Total ${terminology.sales.toLowerCase()}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              money(summary.totalSales),
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Icon(
                (change ?? 0) >= 0
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 16,
                color: changeColor,
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  change == null
                      ? 'First comparable period'
                      : '${change.abs().toStringAsFixed(1)}% vs previous ${period.label.toLowerCase()}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: changeColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${summary.orderCount} ${summary.orderCount == 1 ? 'order' : 'orders'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 160,
            width: double.infinity,
            child: _SalesLineChart(points: summary.salesTrend),
          ),
          const Divider(height: AppSpacing.xl),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Top ${terminology.products.toLowerCase()}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.go(AppRoutes.products),
                child: const Text('View all'),
              ),
            ],
          ),
          if (summary.topProducts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'Top ${terminology.products.toLowerCase()} will appear after sales are recorded.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ...summary.topProducts.map(
              (product) => _TopProductRow(product: product, money: money),
            ),
        ],
      ),
    );
  }
}

class _TopProductRow extends StatelessWidget {
  const _TopProductRow({required this.product, required this.money});

  final DashboardTopProduct product;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final imageUrl = product.imageUrl?.trim();
    final imageCid = product.imageCid?.trim();
    final score = product.scorePercent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          if ((imageUrl != null && imageUrl.isNotEmpty) ||
              (imageCid != null && imageCid.isNotEmpty))
            AppNetworkImage(
              url: imageUrl ?? '',
              cid: imageCid,
              width: 42,
              height: 42,
              borderRadius: BorderRadius.circular(6),
              fallbackIcon: Icons.inventory_2_outlined,
            )
          else
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: AppColors.primary,
              ),
            ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${product.quantity.toStringAsFixed(product.quantity % 1 == 0 ? 0 : 1)} sold',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                money(product.salesTotal),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${score >= 0 ? '+' : ''}${score.toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: score >= 0
                      ? const Color(0xFF22A85A)
                      : Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SalesLineChart extends StatelessWidget {
  const _SalesLineChart({required this.points});

  final List<DashboardSalesPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    return Column(
      children: <Widget>[
        Expanded(
          child: CustomPaint(
            key: const ValueKey<String>('dashboard-sales-line-chart'),
            painter: _SalesLinePainter(
              points.map((point) => point.total).toList(growable: false),
              lineColor: AppColors.primary,
              gridColor: Theme.of(context).dividerColor,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: points
              .map(
                (point) => Text(
                  point.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _SalesLinePainter extends CustomPainter {
  const _SalesLinePainter(
    this.values, {
    required this.lineColor,
    required this.gridColor,
  });

  final List<double> values;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var row = 0; row <= 3; row++) {
      final y = size.height * row / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final maxValue = values.fold<double>(
      1,
      (largest, value) => math.max(largest, value).toDouble(),
    );
    final path = Path();
    final fill = Path();
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? 0.0
          : size.width * index / (values.length - 1);
      final y = size.height - ((values[index] / maxValue) * (size.height - 10));
      if (index == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = lineColor);
    }
    fill
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = lineColor.withValues(alpha: 0.10));
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SalesLinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.lineColor != lineColor;
}

class BusinessHealthPanel extends StatelessWidget {
  const BusinessHealthPanel({required this.summary, super.key});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final health = BusinessHealthScore.fromSummary(summary);
    final scoreColor = switch (health.overall) {
      >= 70 => const Color(0xFF22A85A),
      >= 50 => const Color(0xFFF59E0B),
      _ => Theme.of(context).colorScheme.error,
    };
    final metrics = <(IconData, String, int)>[
      (Icons.trending_up_rounded, 'Sales performance', health.salesPerformance),
      (
        Icons.inventory_2_outlined,
        'Inventory management',
        health.inventoryManagement,
      ),
      (Icons.account_balance_wallet_outlined, 'Cash flow', health.cashFlow),
      (Icons.groups_outlined, 'Customer engagement', health.customerEngagement),
      (Icons.receipt_long_outlined, 'Expense control', health.expenseControl),
      (
        Icons.rocket_launch_outlined,
        'Growth potential',
        health.growthPotential,
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Business Health AI Score',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            'Calculated from current business performance',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: SizedBox(
              width: 156,
              height: 112,
              child: CustomPaint(
                painter: _HealthGaugePainter(
                  score: health.overall,
                  color: scoreColor,
                  trackColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '${health.overall}',
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const Text('/100'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Text(
              health.rating,
              style: TextStyle(color: scoreColor, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - AppSpacing.sm) / 2;
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: metrics
                    .map(
                      (metric) => SizedBox(
                        width: width,
                        child: _HealthMetric(
                          icon: metric.$1,
                          label: metric.$2,
                          score: metric.$3,
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
          const Divider(height: AppSpacing.xl),
          Row(
            children: <Widget>[
              const Icon(
                Icons.auto_awesome,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'AI insight',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(health.insight),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Top recommendations',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          ...health.recommendations.map(
            (recommendation) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.primary,
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(recommendation)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthMetric extends StatelessWidget {
  const _HealthMetric({
    required this.icon,
    required this.label,
    required this.score,
  });

  final IconData icon;
  final String label;
  final int score;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 104),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: AppColors.primary, size: 21),
        const SizedBox(height: 6),
        Text(label, maxLines: 2, overflow: TextOverflow.visible),
        Text('$score/100', style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

class _HealthGaugePainter extends CustomPainter {
  const _HealthGaugePainter({
    required this.score,
    required this.color,
    required this.trackColor,
  });

  final int score;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(12, 8, size.width - 24, size.width - 24);
    const start = math.pi * 0.78;
    const sweep = math.pi * 1.44;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, track);
    canvas.drawArc(
      rect,
      start,
      sweep * (score / 100),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _HealthGaugePainter oldDelegate) =>
      oldDelegate.score != score || oldDelegate.color != color;
}
