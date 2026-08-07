/// Totals used by the profit and loss report. All monetary values are minor
/// currency units, so calculations remain precise.
class ProfitPeriodSummary {
  const ProfitPeriodSummary({
    required this.grossSalesMinor,
    required this.salesDiscountMinor,
    required this.netSalesMinor,
    required this.cogsMinor,
    required this.cogsEstimated,
    required this.grossProfitMinor,
    required this.expenseMinor,
    required this.netProfitMinor,
    required this.stockValueMinor,
    required this.supplierDebtMinor,
    required this.customerDebtMinor,
    this.unavailableReason,
  });

  final int grossSalesMinor;
  final int salesDiscountMinor;
  final int netSalesMinor;
  final int cogsMinor;
  final bool cogsEstimated;
  final int grossProfitMinor;
  final int expenseMinor;
  final int netProfitMinor;
  final int stockValueMinor;
  final int supplierDebtMinor;
  final int customerDebtMinor;
  final String? unavailableReason;

  bool get isUnavailable => unavailableReason != null;
  double get grossMargin =>
      netSalesMinor == 0 ? 0 : grossProfitMinor / netSalesMinor;
  double get netMargin =>
      netSalesMinor == 0 ? 0 : netProfitMinor / netSalesMinor;

  factory ProfitPeriodSummary.unavailable(String reason) => ProfitPeriodSummary(
    grossSalesMinor: 0,
    salesDiscountMinor: 0,
    netSalesMinor: 0,
    cogsMinor: 0,
    cogsEstimated: false,
    grossProfitMinor: 0,
    expenseMinor: 0,
    netProfitMinor: 0,
    stockValueMinor: 0,
    supplierDebtMinor: 0,
    customerDebtMinor: 0,
    unavailableReason: reason,
  );
}
