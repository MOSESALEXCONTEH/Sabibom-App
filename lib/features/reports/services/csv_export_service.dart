import '../../customers/domain/customer.dart';
import '../../expenses/domain/expense.dart';
import '../../sales/domain/sale.dart';
import '../../sales/domain/sale_models.dart';
import '../../suppliers/domain/supplier.dart';
import '../domain/balance_report_models.dart';
import '../domain/product_intelligence_report_models.dart';

class CsvExportService {
  const CsvExportService();

  String expensesCsv(Iterable<Expense> expenses) => _build(
    const ['Number', 'Date', 'Category', 'Description', 'Amount', 'Status'],
    expenses.map(
      (expense) => [
        expense.expenseNumber,
        expense.expenseDate.toIso8601String(),
        expense.categoryName,
        expense.description,
        minorToMoney(expense.amountMinor).toStringAsFixed(2),
        expense.status.name,
      ],
    ),
  );

  String salesCsv(Iterable<Sale> sales) => _build(
    const [
      'Receipt',
      'Date',
      'Customer',
      'Gross Sales',
      'Discount',
      'Net Sales',
      'Status',
    ],
    sales.map(
      (sale) => [
        sale.receiptNumber,
        sale.createdAt?.toIso8601String() ?? '',
        sale.customerName,
        minorToMoney(sale.subtotalMinor).toStringAsFixed(2),
        minorToMoney(sale.discountMinor).toStringAsFixed(2),
        minorToMoney(
          sale.subtotalMinor - sale.discountMinor,
        ).toStringAsFixed(2),
        sale.saleStatus.name,
      ],
    ),
  );

  String suppliersCsv(Iterable<Supplier> suppliers) => _build(
    const [
      'Supplier',
      'Phone',
      'Balance',
      'Total Purchases',
      'Total Paid',
      'Status',
    ],
    suppliers.map(
      (supplier) => [
        supplier.name,
        supplier.phone ?? '',
        minorToMoney(supplier.balanceMinor).toStringAsFixed(2),
        minorToMoney(supplier.totalPurchasesMinor).toStringAsFixed(2),
        minorToMoney(supplier.totalPaidMinor).toStringAsFixed(2),
        supplier.status.name,
      ],
    ),
  );

  String customersCsv(Iterable<Customer> customers) => _build(
    const ['Customer', 'Phone', 'Email', 'Balance', 'Status'],
    customers.map(
      (customer) => [
        customer.name,
        customer.phone ?? '',
        customer.email ?? '',
        minorToMoney(customer.balanceMinor).toStringAsFixed(2),
        customer.status.name,
      ],
    ),
  );

  String inventoryCsv(InventoryValuationReport report) => _build(
    const [
      'Product',
      'SKU',
      'Category',
      'Quantity',
      'Unit Cost',
      'Stock Value',
      'Status',
    ],
    report.rows.map(
      (row) => [
        row.name,
        row.sku,
        row.categoryName ?? '',
        row.quantity.toString(),
        minorToMoney(row.unitCostMinor).toStringAsFixed(2),
        minorToMoney(row.lineValueMinor).toStringAsFixed(2),
        row.isOutOfStock
            ? 'Out of stock'
            : row.isLowStock
            ? 'Low stock'
            : 'OK',
      ],
    ),
  );

  String productProfitCsv(ProductProfitReport report) => _build(
    const [
      'Product',
      'SKU',
      'Category',
      'Qty Sold',
      'Qty On Hand',
      'Net Revenue',
      'COGS',
      'Realized Profit',
      'Potential Profit Remaining',
      'Projected Profit',
      'Exactness',
    ],
    report.rows.map(
      (row) => [
        row.name,
        row.sku,
        row.categoryName ?? '',
        row.quantitySold.toString(),
        row.quantityOnHand.toString(),
        minorToMoney(row.actualNetRevenueMinor).toStringAsFixed(2),
        minorToMoney(row.costOfGoodsSoldMinor).toStringAsFixed(2),
        minorToMoney(row.realizedGrossProfitMinor).toStringAsFixed(2),
        minorToMoney(row.potentialProfitRemainingMinor).toStringAsFixed(2),
        minorToMoney(row.projectedGrossProfitMinor).toStringAsFixed(2),
        row.profitIsEstimated ? 'Estimated' : 'Exact',
      ],
    ),
  );

  String productExpiryCsv(ProductExpiryReport report) => _build(
    const [
      'Section',
      'Product',
      'SKU',
      'Batch',
      'Category',
      'Quantity',
      'Expiry Date',
      'Days Remaining',
      'Unit Cost',
      'Cost Value',
      'Potential Revenue',
      'Potential Profit/Loss',
      'Source',
    ],
    report.sections.expand(
      (section) => section.rows.map(
        (row) => [
          section.title,
          row.productName,
          row.sku,
          row.batchId,
          row.categoryName ?? '',
          row.quantityRemaining.toString(),
          row.expiryDate?.toIso8601String().substring(0, 10) ?? 'Unknown',
          row.daysRemaining?.toString() ?? '',
          minorToMoney(row.unitCostMinor).toStringAsFixed(2),
          minorToMoney(row.costValueMinor).toStringAsFixed(2),
          minorToMoney(row.potentialRevenueMinor).toStringAsFixed(2),
          minorToMoney(row.potentialProfitLossMinor).toStringAsFixed(2),
          row.sourceNumber ?? row.sourceType,
        ],
      ),
    ),
  );

  String _build(List<String> headers, Iterable<List<String>> rows) {
    final output = StringBuffer()..writeln(headers.map(_escape).join(','));
    for (final row in rows) {
      output.writeln(row.map(_escape).join(','));
    }
    return output.toString();
  }

  String _escape(String value) => '"${value.replaceAll('"', '""')}"';
}
