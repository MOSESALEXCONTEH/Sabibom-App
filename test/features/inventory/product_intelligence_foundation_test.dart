import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/inventory/domain/expiry_status_calculator.dart';
import 'package:sabibom/features/inventory/domain/inventory_batch.dart';
import 'package:sabibom/features/inventory/domain/inventory_expiry_settings.dart';
import 'package:sabibom/features/inventory/domain/product_profit_calculator.dart';
import 'package:sabibom/features/inventory/domain/stock_quantity_rules.dart';
import 'package:sabibom/features/products/domain/product.dart';
import 'package:timezone/data/latest.dart' as timezone_data;

void main() {
  setUpAll(timezone_data.initializeTimeZones);

  group('Product compatibility', () {
    test('legacy product defaults to no expiry tracking', () {
      final product = Product.fromMap('legacy', <String, dynamic>{
        'businessId': 'business',
        'name': 'Shoe',
        'sellingPriceMinor': 2500,
        'costPriceMinor': 2000,
        'quantity': 50,
      });

      expect(product.tracksExpiry, isFalse);
      expect(product.expiryStatus, ProductExpiryStatus.notTracked);
      expect(product.defaultExpiryReminderDays, 30);
      expect(product.profitEstimateMinor, 500);
    });
  });

  group('ExpiryStatusCalculator', () {
    final now = DateTime.utc(2026, 7, 22, 23, 30);

    test('calculates safe, reminder, today and expired statuses', () {
      ProductExpiryStatus status(int day) =>
          ExpiryStatusCalculator.statusForDate(
            expiryDate: DateTime.utc(2026, 7, day),
            now: now,
            businessTimezone: 'Africa/Freetown',
            reminderThresholdDays: 7,
          );

      expect(status(31), ProductExpiryStatus.safe);
      expect(status(29), ProductExpiryStatus.expiringSoon);
      expect(status(22), ProductExpiryStatus.expiresToday);
      expect(status(21), ProductExpiryStatus.expired);
    });

    test('uses the business timezone date', () {
      final remaining = ExpiryStatusCalculator.daysRemaining(
        expiryDate: DateTime.utc(2026, 7, 23),
        now: DateTime.utc(2026, 7, 23, 0, 30),
        businessTimezone: 'America/New_York',
      );

      expect(remaining, 1);
    });

    test('summarizes mixed and unknown batches', () {
      final summary = ExpiryStatusCalculator.summarize(
        tracksExpiry: true,
        batches: <InventoryBatch>[
          _batch(id: 'expired', expiry: DateTime.utc(2026, 7, 21)),
          _batch(id: 'soon', expiry: DateTime.utc(2026, 7, 25)),
          _batch(id: 'unknown'),
        ],
        now: now,
        businessTimezone: 'Africa/Freetown',
        reminderThresholdDays: 7,
      );

      expect(summary.status, ProductExpiryStatus.mixed);
      expect(summary.expiredQuantity, 10);
      expect(summary.expiringQuantity, 10);
      expect(summary.unknownExpiryQuantity, 10);
      expect(summary.nextExpiryBatchId, 'expired');
    });
  });

  group('ProductProfitCalculator', () {
    test('calculates the Shoe example in minor units', () {
      final summary = ProductProfitCalculator.calculate(
        currentStock: 50,
        currentUnitCostMinor: 2000,
        currentSellingPriceMinor: 2500,
      );

      expect(summary.unitPotentialProfitMinor, 500);
      expect(summary.stockCostValueMinor, 100000);
      expect(summary.expectedStockRevenueMinor, 125000);
      expect(summary.potentialProfitRemainingMinor, 25000);
    });

    test('uses mixed batch costs and shows a potential loss', () {
      final mixed = ProductProfitCalculator.calculate(
        currentStock: 20,
        currentUnitCostMinor: 2200,
        currentSellingPriceMinor: 2500,
        activeBatches: <InventoryBatch>[
          _batch(id: 'a', unitCostMinor: 2000),
          _batch(id: 'b', unitCostMinor: 2200),
        ],
      );
      final loss = ProductProfitCalculator.calculate(
        currentStock: 2,
        currentUnitCostMinor: 3000,
        currentSellingPriceMinor: 2500,
      );

      expect(mixed.potentialProfitRemainingMinor, 8000);
      expect(loss.potentialProfitRemainingMinor, -1000);
      expect(loss.hasPotentialLoss, isTrue);
    });

    test('realized profit and margin never produce invalid numbers', () {
      final summary = ProductProfitCalculator.calculate(
        currentStock: 0,
        currentUnitCostMinor: 0,
        currentSellingPriceMinor: 0,
        realizedLines: const <RealizedProductLine>[
          RealizedProductLine(
            actualNetRevenueMinor: 25000,
            costOfGoodsSoldMinor: 20000,
          ),
        ],
      );

      expect(summary.realizedGrossProfitMinor, 5000);
      expect(
        ProductProfitCalculator.grossMarginBasisPoints(
          realizedGrossProfitMinor: summary.realizedGrossProfitMinor,
          actualNetRevenueMinor: 0,
        ),
        0,
      );
    });
  });

  group('Validation and settings', () {
    test(
      'whole-item units reject decimals while measured units allow them',
      () {
        expect(
          StockQuantityRules.validate(quantity: 1.5, unit: 'Piece'),
          isNotNull,
        );
        expect(
          StockQuantityRules.validate(quantity: 1.5, unit: 'Kilogram'),
          isNull,
        );
      },
    );

    test('reminder days are bounded, sorted and deduplicated', () {
      expect(
        InventoryExpirySettings.normalizeReminderDays(<int>[
          7,
          30,
          7,
          -1,
          1000,
          0,
        ]),
        <int>[30, 7, 0],
      );
    });
  });
}

InventoryBatch _batch({
  required String id,
  DateTime? expiry,
  int unitCostMinor = 2000,
}) {
  return InventoryBatch(
    id: id,
    businessId: 'business',
    branchId: 'main',
    productId: 'product',
    productName: 'Milk',
    sourceType: InventoryBatchSourceType.purchase,
    quantityReceived: 10,
    quantityRemaining: 10,
    unitCostMinor: unitCostMinor,
    sellingPriceAtReceiptMinor: 2500,
    expiryDate: expiry,
    expiryDateKnown: expiry != null,
    receivedAt: DateTime.utc(2026, 7, 1),
    status: InventoryBatchStatus.active,
  );
}
