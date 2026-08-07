import 'inventory_batch.dart';

class ProductProfitSummary {
  const ProductProfitSummary({
    required this.unitPotentialProfitMinor,
    required this.stockCostValueMinor,
    required this.expectedStockRevenueMinor,
    required this.potentialProfitRemainingMinor,
    required this.realizedGrossProfitMinor,
    required this.projectedGrossProfitMinor,
    required this.profitIsEstimated,
  });

  final int unitPotentialProfitMinor;
  final int stockCostValueMinor;
  final int expectedStockRevenueMinor;
  final int potentialProfitRemainingMinor;
  final int realizedGrossProfitMinor;
  final int projectedGrossProfitMinor;
  final bool profitIsEstimated;

  bool get hasPotentialLoss => potentialProfitRemainingMinor < 0;
}

class RealizedProductLine {
  const RealizedProductLine({
    required this.actualNetRevenueMinor,
    required this.costOfGoodsSoldMinor,
    this.isExact = true,
  });

  final int actualNetRevenueMinor;
  final int costOfGoodsSoldMinor;
  final bool isExact;

  int get grossProfitMinor => actualNetRevenueMinor - costOfGoodsSoldMinor;
}

abstract final class ProductProfitCalculator {
  static ProductProfitSummary calculate({
    required double currentStock,
    required int currentUnitCostMinor,
    required int currentSellingPriceMinor,
    Iterable<InventoryBatch> activeBatches = const <InventoryBatch>[],
    Iterable<RealizedProductLine> realizedLines = const <RealizedProductLine>[],
  }) {
    final batches = activeBatches
        .where((batch) => batch.status == InventoryBatchStatus.active)
        .where((batch) => batch.quantityRemaining > 0)
        .toList(growable: false);

    final stockCost = batches.isEmpty
        ? lineValue(currentStock, currentUnitCostMinor)
        : batches.fold<int>(
            0,
            (total, batch) =>
                total + lineValue(batch.quantityRemaining, batch.unitCostMinor),
          );
    final saleableQuantity = batches.isEmpty
        ? currentStock
        : batches.fold<double>(
            0,
            (total, batch) => total + batch.quantityRemaining,
          );
    final expectedRevenue = lineValue(
      saleableQuantity,
      currentSellingPriceMinor,
    );
    final realized = realizedLines.fold<int>(
      0,
      (total, line) => total + line.grossProfitMinor,
    );
    final estimated = realizedLines.any((line) => !line.isExact);
    final potential = expectedRevenue - stockCost;
    return ProductProfitSummary(
      unitPotentialProfitMinor: currentSellingPriceMinor - currentUnitCostMinor,
      stockCostValueMinor: stockCost,
      expectedStockRevenueMinor: expectedRevenue,
      potentialProfitRemainingMinor: potential,
      realizedGrossProfitMinor: realized,
      projectedGrossProfitMinor: realized + potential,
      profitIsEstimated: estimated,
    );
  }

  static int lineValue(double quantity, int unitAmountMinor) {
    if (!quantity.isFinite || quantity <= 0) return 0;
    return (quantity * unitAmountMinor).round();
  }

  static int grossMarginBasisPoints({
    required int realizedGrossProfitMinor,
    required int actualNetRevenueMinor,
  }) {
    if (actualNetRevenueMinor == 0) return 0;
    return ((realizedGrossProfitMinor * 10000) / actualNetRevenueMinor).round();
  }
}
