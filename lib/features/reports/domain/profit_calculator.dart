import '../../customers/domain/customer.dart';
import '../../expenses/domain/expense.dart';
import '../../products/domain/product.dart';
import '../../sales/domain/sale.dart';
import '../../sales/domain/sale_models.dart';
import '../../suppliers/domain/supplier.dart';
import 'profit_models.dart';

class ProfitCalculator {
  const ProfitCalculator._();

  static ProfitPeriodSummary calculate({
    required Iterable<Sale> sales,
    required Iterable<Expense> expenses,
    required Iterable<Product> products,
    required Iterable<Supplier> suppliers,
    required Iterable<Customer> customers,
  }) {
    var grossSalesMinor = 0;
    var salesDiscountMinor = 0;
    var cogsMinor = 0;
    var cogsEstimated = false;

    for (final sale in sales) {
      if (sale.saleStatus != SaleStatus.completed || sale.isVoided) continue;
      grossSalesMinor += sale.subtotalMinor;
      salesDiscountMinor += sale.discountMinor;
      for (final item in sale.items) {
        final cost = item.costPriceMinor;
        if (cost == null) {
          cogsEstimated = true;
          continue;
        }
        cogsMinor += (item.quantity * cost).round();
      }
    }

    final netSalesMinor = grossSalesMinor - salesDiscountMinor;
    final expenseMinor = expenses
        .where((expense) => !expense.isVoided)
        .fold<int>(0, (total, expense) => total + expense.amountMinor);
    final stockValueMinor = products
        .where((product) => product.trackStock)
        .fold<int>(
          0,
          (total, product) =>
              total + (product.quantity * product.costPriceMinor).round(),
        );
    final supplierDebtMinor = suppliers.fold<int>(
      0,
      (total, supplier) =>
          total + (supplier.balanceMinor > 0 ? supplier.balanceMinor : 0),
    );
    final customerDebtMinor = customers.fold<int>(
      0,
      (total, customer) =>
          total + (customer.balanceMinor > 0 ? customer.balanceMinor : 0),
    );
    final grossProfitMinor = netSalesMinor - cogsMinor;

    return ProfitPeriodSummary(
      grossSalesMinor: grossSalesMinor,
      salesDiscountMinor: salesDiscountMinor,
      netSalesMinor: netSalesMinor,
      cogsMinor: cogsMinor,
      cogsEstimated: cogsEstimated,
      grossProfitMinor: grossProfitMinor,
      expenseMinor: expenseMinor,
      netProfitMinor: grossProfitMinor - expenseMinor,
      stockValueMinor: stockValueMinor,
      supplierDebtMinor: supplierDebtMinor,
      customerDebtMinor: customerDebtMinor,
    );
  }
}
