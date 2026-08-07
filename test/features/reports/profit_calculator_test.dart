import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/customers/domain/customer.dart';
import 'package:sabibom/features/expenses/domain/expense.dart';
import 'package:sabibom/features/products/domain/product.dart';
import 'package:sabibom/features/reports/domain/profit_calculator.dart';
import 'package:sabibom/features/sales/domain/sale.dart';
import 'package:sabibom/features/sales/domain/sale_models.dart';
import 'package:sabibom/features/suppliers/domain/supplier.dart';

void main() {
  test('calculates profit without treating purchases as expenses', () {
    final summary = ProfitCalculator.calculate(
      sales: [
        _sale(
          items: [
            const SaleLineItem(
              name: 'Rice',
              quantity: 2,
              unitPriceMinor: 1000,
              lineTotalMinor: 2000,
              costPriceMinor: 400,
            ),
          ],
        ),
      ],
      expenses: [
        _expense(300),
        _expense(900, status: ExpenseStatus.voided),
      ],
      products: [_product(quantity: 3, cost: 400)],
      suppliers: [_supplier(250)],
      customers: [_customer(125)],
    );

    expect(summary.grossSalesMinor, 2000);
    expect(summary.netSalesMinor, 1800);
    expect(summary.cogsMinor, 800);
    expect(summary.grossProfitMinor, 1000);
    expect(summary.expenseMinor, 300);
    expect(summary.netProfitMinor, 700);
    expect(summary.stockValueMinor, 1200);
    expect(summary.supplierDebtMinor, 250);
    expect(summary.customerDebtMinor, 125);
  });

  test('flags COGS when a completed sale item has no cost snapshot', () {
    final summary = ProfitCalculator.calculate(
      sales: [
        _sale(
          items: [
            const SaleLineItem(
              name: 'Custom',
              quantity: 1,
              unitPriceMinor: 500,
              lineTotalMinor: 500,
            ),
          ],
        ),
      ],
      expenses: const [],
      products: const [],
      suppliers: const [],
      customers: const [],
    );
    expect(summary.cogsEstimated, isTrue);
    expect(summary.cogsMinor, 0);
  });
}

Sale _sale({required List<SaleLineItem> items}) => Sale(
  id: 'sale',
  businessId: 'business',
  receiptNumber: 'R1',
  customerName: 'Customer',
  items: items,
  subtotalMinor: 2000,
  discountMinor: 200,
  taxMinor: 0,
  totalMinor: 1800,
  amountPaidMinor: 1800,
  balanceDueMinor: 0,
  changeMinor: 0,
  currencyCode: 'SLE',
  currencySymbol: 'Le',
  paymentMethod: PaymentMethod.cash,
  paymentStatus: PaymentStatus.paid,
  saleStatus: SaleStatus.completed,
);

Expense _expense(int amount, {ExpenseStatus status = ExpenseStatus.active}) =>
    Expense(
      id: 'expense',
      businessId: 'business',
      expenseNumber: 'E1',
      categoryId: 'cat',
      categoryName: 'Rent',
      amountMinor: amount,
      currencyCode: 'SLE',
      description: 'Shop rent',
      paymentMethod: ExpensePaymentMethod.cash,
      expenseDate: DateTime(2026),
      status: status,
    );

Product _product({required double quantity, required int cost}) => Product(
  id: 'product',
  businessId: 'business',
  name: 'Rice',
  sellingPriceMinor: 600,
  costPriceMinor: cost,
  quantity: quantity,
  lowStockThreshold: 0,
  trackStock: true,
  unit: 'Bag',
  status: ProductStatus.active,
);

Supplier _supplier(int balance) => Supplier(
  id: 'supplier',
  businessId: 'business',
  name: 'Supplier',
  balanceMinor: balance,
  totalPurchasesMinor: 0,
  totalPaidMinor: 0,
  purchaseCount: 0,
  status: SupplierStatus.active,
);

Customer _customer(int balance) => Customer(
  id: 'customer',
  businessId: 'business',
  name: 'Customer',
  balanceMinor: balance,
  totalSalesMinor: 0,
  totalPaidMinor: 0,
  purchaseCount: 0,
  status: CustomerStatus.active,
);
