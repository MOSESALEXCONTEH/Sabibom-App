import '../../inventory/domain/expiry_status_calculator.dart';
import '../../inventory/domain/inventory_batch.dart';
import '../../products/domain/product.dart';
import '../../sales/domain/sale.dart';
import '../../sales/domain/sale_models.dart';

enum ProductProfitSort {
  realizedProfitDesc,
  potentialProfitDesc,
  projectedProfitDesc,
  nameAsc,
  quantitySoldDesc,
}

enum ExpiryReportSort { expiryDateAsc, expiredFirst, nameAsc, quantityDesc }

/// One product row for the Product Profit report.
class ProductProfitRow {
  const ProductProfitRow({
    required this.productId,
    required this.name,
    required this.sku,
    required this.categoryId,
    required this.categoryName,
    required this.quantityOnHand,
    required this.quantitySold,
    required this.actualNetRevenueMinor,
    required this.costOfGoodsSoldMinor,
    required this.realizedGrossProfitMinor,
    required this.potentialProfitRemainingMinor,
    required this.projectedGrossProfitMinor,
    required this.profitIsEstimated,
    required this.trackStock,
  });

  final String productId;
  final String name;
  final String sku;
  final String? categoryId;
  final String? categoryName;
  final double quantityOnHand;
  final double quantitySold;
  final int actualNetRevenueMinor;
  final int costOfGoodsSoldMinor;
  final int realizedGrossProfitMinor;
  final int potentialProfitRemainingMinor;
  final int projectedGrossProfitMinor;
  final bool profitIsEstimated;
  final bool trackStock;

  int get grossMarginBasisPoints {
    if (actualNetRevenueMinor == 0) return 0;
    return ((realizedGrossProfitMinor * 10000) / actualNetRevenueMinor).round();
  }
}

class ProductProfitReport {
  const ProductProfitReport({
    required this.rows,
    required this.totalRealizedGrossProfitMinor,
    required this.totalPotentialProfitRemainingMinor,
    required this.totalProjectedGrossProfitMinor,
    required this.totalQuantitySold,
    required this.anyEstimated,
  });

  final List<ProductProfitRow> rows;
  final int totalRealizedGrossProfitMinor;
  final int totalPotentialProfitRemainingMinor;
  final int totalProjectedGrossProfitMinor;
  final double totalQuantitySold;
  final bool anyEstimated;

  factory ProductProfitReport.fromProductsAndSales({
    required List<Product> products,
    required List<Sale> sales,
    String? categoryId,
    bool inStockOnly = false,
    ProductProfitSort sort = ProductProfitSort.realizedProfitDesc,
  }) {
    final aggregates = <String, _ProfitAgg>{};
    for (final sale in sales) {
      if (sale.saleStatus != SaleStatus.completed) continue;
      for (final item in sale.items) {
        final productId = item.productId;
        if (productId == null || productId.isEmpty) continue;
        final agg = aggregates.putIfAbsent(productId, _ProfitAgg.new);
        agg.quantitySold += item.quantity;
        final revenue = item.actualNetRevenueMinor ?? item.lineTotalMinor;
        final costUnit = item.costPriceMinor;
        final cogs =
            item.costOfGoodsSoldMinor ??
            (costUnit == null ? 0 : (costUnit * item.quantity).round());
        final profit = item.grossProfitMinor ?? (revenue - cogs);
        agg.actualNetRevenueMinor += revenue;
        agg.costOfGoodsSoldMinor += cogs;
        agg.realizedGrossProfitMinor += profit;
        if (!item.profitIsExact ||
            item.costOfGoodsSoldMinor == null ||
            costUnit == null) {
          agg.profitIsEstimated = true;
        }
      }
    }

    final rows = <ProductProfitRow>[];
    for (final product in products) {
      if (product.status != ProductStatus.active) continue;
      if (categoryId != null &&
          categoryId.isNotEmpty &&
          product.categoryId != categoryId) {
        continue;
      }
      if (inStockOnly && product.trackStock && product.quantity <= 0) continue;

      final agg = aggregates[product.id];
      final potential = product.potentialProfitRemainingMinor != 0
          ? product.potentialProfitRemainingMinor
          : ((product.quantity * product.sellingPriceMinor).round() -
                (product.quantity * product.costPriceMinor).round());
      // Period realized comes from sale snapshots when present; otherwise fall
      // back to the product's all-time counter for an empty period view.
      final realized =
          agg?.realizedGrossProfitMinor ??
          (sales.isEmpty ? product.realizedGrossProfitMinor : 0);
      final estimated =
          (agg?.profitIsEstimated ?? false) || product.profitIsEstimated;
      rows.add(
        ProductProfitRow(
          productId: product.id,
          name: product.name,
          sku: product.sku ?? '',
          categoryId: product.categoryId,
          categoryName: product.categoryName,
          quantityOnHand: product.quantity,
          quantitySold: agg?.quantitySold ?? 0,
          actualNetRevenueMinor: agg?.actualNetRevenueMinor ?? 0,
          costOfGoodsSoldMinor: agg?.costOfGoodsSoldMinor ?? 0,
          realizedGrossProfitMinor: realized,
          potentialProfitRemainingMinor: potential,
          projectedGrossProfitMinor: realized + potential,
          profitIsEstimated: estimated,
          trackStock: product.trackStock,
        ),
      );
    }

    _sortProfitRows(rows, sort);
    return ProductProfitReport(
      rows: rows,
      totalRealizedGrossProfitMinor: rows.fold(
        0,
        (sum, row) => sum + row.realizedGrossProfitMinor,
      ),
      totalPotentialProfitRemainingMinor: rows.fold(
        0,
        (sum, row) => sum + row.potentialProfitRemainingMinor,
      ),
      totalProjectedGrossProfitMinor: rows.fold(
        0,
        (sum, row) => sum + row.projectedGrossProfitMinor,
      ),
      totalQuantitySold: rows.fold(0, (sum, row) => sum + row.quantitySold),
      anyEstimated: rows.any((row) => row.profitIsEstimated),
    );
  }

  static void _sortProfitRows(
    List<ProductProfitRow> rows,
    ProductProfitSort sort,
  ) {
    switch (sort) {
      case ProductProfitSort.realizedProfitDesc:
        rows.sort(
          (a, b) =>
              b.realizedGrossProfitMinor.compareTo(a.realizedGrossProfitMinor),
        );
      case ProductProfitSort.potentialProfitDesc:
        rows.sort(
          (a, b) => b.potentialProfitRemainingMinor.compareTo(
            a.potentialProfitRemainingMinor,
          ),
        );
      case ProductProfitSort.projectedProfitDesc:
        rows.sort(
          (a, b) => b.projectedGrossProfitMinor.compareTo(
            a.projectedGrossProfitMinor,
          ),
        );
      case ProductProfitSort.nameAsc:
        rows.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case ProductProfitSort.quantitySoldDesc:
        rows.sort((a, b) => b.quantitySold.compareTo(a.quantitySold));
    }
  }
}

class _ProfitAgg {
  double quantitySold = 0;
  int actualNetRevenueMinor = 0;
  int costOfGoodsSoldMinor = 0;
  int realizedGrossProfitMinor = 0;
  bool profitIsEstimated = false;
}

/// One expiry section (e.g. Expired, Expires today, Expiring soon).
class ExpiryReportSection {
  const ExpiryReportSection({
    required this.status,
    required this.title,
    required this.rows,
    required this.totalQuantity,
    required this.totalCostMinor,
    required this.totalPotentialRevenueMinor,
    required this.totalPotentialProfitLossMinor,
  });

  final ProductExpiryStatus status;
  final String title;
  final List<ExpiryReportRow> rows;
  final double totalQuantity;
  final int totalCostMinor;
  final int totalPotentialRevenueMinor;
  final int totalPotentialProfitLossMinor;
}

class ExpiryReportRow {
  const ExpiryReportRow({
    required this.productId,
    required this.productName,
    required this.batchId,
    required this.sku,
    required this.categoryName,
    required this.quantityRemaining,
    required this.unitCostMinor,
    required this.sellingPriceMinor,
    required this.expiryDate,
    required this.expiryDateKnown,
    required this.status,
    required this.daysRemaining,
    required this.sourceType,
    this.sourceNumber,
  });

  final String productId;
  final String productName;
  final String batchId;
  final String sku;
  final String? categoryName;
  final double quantityRemaining;
  final int unitCostMinor;
  final int sellingPriceMinor;
  final DateTime? expiryDate;
  final bool expiryDateKnown;
  final ProductExpiryStatus status;
  final int? daysRemaining;
  final String sourceType;
  final String? sourceNumber;

  int get costValueMinor => (quantityRemaining * unitCostMinor).round();
  int get potentialRevenueMinor =>
      (quantityRemaining * sellingPriceMinor).round();
  int get potentialProfitLossMinor => potentialRevenueMinor - costValueMinor;
}

class ProductExpiryReport {
  const ProductExpiryReport({
    required this.sections,
    required this.totalExpiredCostMinor,
    required this.totalExpiringQuantity,
    required this.totalExpiredQuantity,
    required this.totalUnknownQuantity,
  });

  final List<ExpiryReportSection> sections;
  final int totalExpiredCostMinor;
  final double totalExpiringQuantity;
  final double totalExpiredQuantity;
  final double totalUnknownQuantity;

  factory ProductExpiryReport.fromProductsAndBatches({
    required List<Product> products,
    required List<InventoryBatch> batches,
    required DateTime now,
    required String businessTimezone,
    String? categoryId,
    ProductExpiryStatus? statusFilter,
    ExpiryReportSort sort = ExpiryReportSort.expiryDateAsc,
    int reminderThresholdDays = 30,
  }) {
    final productById = {
      for (final product in products)
        if (product.status == ProductStatus.active) product.id: product,
    };

    final buckets = <ProductExpiryStatus, List<ExpiryReportRow>>{
      ProductExpiryStatus.expired: <ExpiryReportRow>[],
      ProductExpiryStatus.expiresToday: <ExpiryReportRow>[],
      ProductExpiryStatus.expiringSoon: <ExpiryReportRow>[],
      ProductExpiryStatus.safe: <ExpiryReportRow>[],
      ProductExpiryStatus.notTracked: <ExpiryReportRow>[],
    };

    for (final batch in batches) {
      if (batch.quantityRemaining <= 0) continue;
      if (batch.status == InventoryBatchStatus.depleted ||
          batch.status == InventoryBatchStatus.voided) {
        continue;
      }
      final product = productById[batch.productId];
      if (product == null || !product.tracksExpiry) continue;
      if (categoryId != null &&
          categoryId.isNotEmpty &&
          product.categoryId != categoryId) {
        continue;
      }

      final ProductExpiryStatus status;
      final int? days;
      if (!batch.expiryDateKnown || batch.expiryDate == null) {
        status = ProductExpiryStatus.notTracked;
        days = null;
      } else {
        days = ExpiryStatusCalculator.daysRemaining(
          expiryDate: batch.expiryDate!,
          now: now,
          businessTimezone: businessTimezone,
        );
        status = ExpiryStatusCalculator.statusForDate(
          expiryDate: batch.expiryDate!,
          now: now,
          businessTimezone: businessTimezone,
          reminderThresholdDays: product.defaultExpiryReminderDays > 0
              ? product.defaultExpiryReminderDays
              : reminderThresholdDays,
        );
      }

      if (statusFilter != null && status != statusFilter) continue;

      buckets[status]!.add(
        ExpiryReportRow(
          productId: product.id,
          productName: product.name,
          batchId: batch.id,
          sku: product.sku ?? batch.sku ?? '',
          categoryName: product.categoryName,
          quantityRemaining: batch.quantityRemaining,
          unitCostMinor: batch.unitCostMinor,
          sellingPriceMinor: product.sellingPriceMinor,
          expiryDate: batch.expiryDate,
          expiryDateKnown: batch.expiryDateKnown,
          status: status,
          daysRemaining: days,
          sourceType: batch.sourceType.storedValue,
          sourceNumber: batch.sourceNumber,
        ),
      );
    }

    for (final list in buckets.values) {
      _sortExpiryRows(list, sort);
    }

    ExpiryReportSection section(ProductExpiryStatus status, String title) {
      final rows = buckets[status] ?? const <ExpiryReportRow>[];
      return ExpiryReportSection(
        status: status,
        title: title,
        rows: rows,
        totalQuantity: rows.fold(0, (sum, row) => sum + row.quantityRemaining),
        totalCostMinor: rows.fold(0, (sum, row) => sum + row.costValueMinor),
        totalPotentialRevenueMinor: rows.fold(
          0,
          (sum, row) => sum + row.potentialRevenueMinor,
        ),
        totalPotentialProfitLossMinor: rows.fold(
          0,
          (sum, row) => sum + row.potentialProfitLossMinor,
        ),
      );
    }

    final sections = <ExpiryReportSection>[
      section(ProductExpiryStatus.expired, 'Expired'),
      section(ProductExpiryStatus.expiresToday, 'Expires today'),
      section(ProductExpiryStatus.expiringSoon, 'Expiring soon'),
      section(ProductExpiryStatus.notTracked, 'Unknown expiry'),
      if (statusFilter == ProductExpiryStatus.safe)
        section(ProductExpiryStatus.safe, 'Safe'),
    ].where((section) => section.rows.isNotEmpty).toList(growable: false);

    final expired = buckets[ProductExpiryStatus.expired]!;
    final expiring = [
      ...buckets[ProductExpiryStatus.expiresToday]!,
      ...buckets[ProductExpiryStatus.expiringSoon]!,
    ];
    final unknown = buckets[ProductExpiryStatus.notTracked]!;

    return ProductExpiryReport(
      sections: sections,
      totalExpiredCostMinor: expired.fold(
        0,
        (sum, row) => sum + row.costValueMinor,
      ),
      totalExpiringQuantity: expiring.fold(
        0,
        (sum, row) => sum + row.quantityRemaining,
      ),
      totalExpiredQuantity: expired.fold(
        0,
        (sum, row) => sum + row.quantityRemaining,
      ),
      totalUnknownQuantity: unknown.fold(
        0,
        (sum, row) => sum + row.quantityRemaining,
      ),
    );
  }

  static void _sortExpiryRows(
    List<ExpiryReportRow> rows,
    ExpiryReportSort sort,
  ) {
    switch (sort) {
      case ExpiryReportSort.expiryDateAsc:
        rows.sort((a, b) {
          final aDate = a.expiryDate;
          final bDate = b.expiryDate;
          if (aDate == null && bDate == null) {
            return a.productName.compareTo(b.productName);
          }
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return aDate.compareTo(bDate);
        });
      case ExpiryReportSort.expiredFirst:
        rows.sort((a, b) {
          final byStatus = a.status.index.compareTo(b.status.index);
          if (byStatus != 0) return byStatus;
          return (a.daysRemaining ?? 9999).compareTo(b.daysRemaining ?? 9999);
        });
      case ExpiryReportSort.nameAsc:
        rows.sort(
          (a, b) => a.productName.toLowerCase().compareTo(
            b.productName.toLowerCase(),
          ),
        );
      case ExpiryReportSort.quantityDesc:
        rows.sort((a, b) => b.quantityRemaining.compareTo(a.quantityRemaining));
    }
  }
}
