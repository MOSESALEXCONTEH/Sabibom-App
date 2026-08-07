import '../../customers/domain/customer.dart';
import '../../products/domain/product.dart';
import '../../suppliers/domain/supplier.dart';

class InventoryValuationRow {
  const InventoryValuationRow({
    required this.productId,
    required this.name,
    required this.sku,
    required this.quantity,
    required this.unitCostMinor,
    required this.lineValueMinor,
    required this.isLowStock,
    required this.isOutOfStock,
    this.categoryName,
  });

  final String productId;
  final String name;
  final String sku;
  final double quantity;
  final int unitCostMinor;
  final int lineValueMinor;
  final bool isLowStock;
  final bool isOutOfStock;
  final String? categoryName;
}

class InventoryValuationReport {
  const InventoryValuationReport({
    required this.rows,
    required this.totalValueMinor,
    required this.trackedProductCount,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.lowStockValueMinor,
  });

  final List<InventoryValuationRow> rows;
  final int totalValueMinor;
  final int trackedProductCount;
  final int lowStockCount;
  final int outOfStockCount;
  final int lowStockValueMinor;

  factory InventoryValuationReport.fromProducts(List<Product> products) {
    final tracked = products
        .where((p) => p.trackStock && p.status == ProductStatus.active)
        .toList();
    final rows =
        tracked
            .map((product) {
              final qty = product.quantity;
              final value = (qty * product.costPriceMinor).round();
              return InventoryValuationRow(
                productId: product.id,
                name: product.name,
                sku: product.sku ?? '',
                quantity: qty,
                unitCostMinor: product.costPriceMinor,
                lineValueMinor: value,
                isLowStock: product.isLowStock,
                isOutOfStock: product.isOutOfStock,
                categoryName: product.categoryName,
              );
            })
            .toList()
          ..sort((a, b) => b.lineValueMinor.compareTo(a.lineValueMinor));

    final lowStock = rows.where((r) => r.isLowStock || r.isOutOfStock);
    return InventoryValuationReport(
      rows: rows,
      totalValueMinor: rows.fold(0, (sum, r) => sum + r.lineValueMinor),
      trackedProductCount: rows.length,
      lowStockCount: rows.where((r) => r.isLowStock).length,
      outOfStockCount: rows.where((r) => r.isOutOfStock).length,
      lowStockValueMinor: lowStock.fold(0, (sum, r) => sum + r.lineValueMinor),
    );
  }
}

class CustomerBalanceReport {
  const CustomerBalanceReport({
    required this.customers,
    required this.totalDebtMinor,
    required this.owingCount,
  });

  final List<Customer> customers;
  final int totalDebtMinor;
  final int owingCount;

  factory CustomerBalanceReport.fromCustomers(List<Customer> customers) {
    final owing =
        customers
            .where(
              (c) => c.status == CustomerStatus.active && c.balanceMinor > 0,
            )
            .toList()
          ..sort((a, b) => b.balanceMinor.compareTo(a.balanceMinor));
    return CustomerBalanceReport(
      customers: owing,
      totalDebtMinor: owing.fold(0, (sum, c) => sum + c.balanceMinor),
      owingCount: owing.length,
    );
  }
}

class SupplierBalanceReport {
  const SupplierBalanceReport({
    required this.suppliers,
    required this.totalDebtMinor,
    required this.owingCount,
  });

  final List<Supplier> suppliers;
  final int totalDebtMinor;
  final int owingCount;

  factory SupplierBalanceReport.fromSuppliers(List<Supplier> suppliers) {
    final owing =
        suppliers
            .where(
              (s) => s.status == SupplierStatus.active && s.balanceMinor > 0,
            )
            .toList()
          ..sort((a, b) => b.balanceMinor.compareTo(a.balanceMinor));
    return SupplierBalanceReport(
      suppliers: owing,
      totalDebtMinor: owing.fold(0, (sum, s) => sum + s.balanceMinor),
      owingCount: owing.length,
    );
  }
}
