import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/branches/domain/business_branch.dart';
import 'package:sabibom/features/inventory/domain/branch_inventory.dart';
import 'package:sabibom/features/products/domain/product.dart';

BranchInventory inventory({
  required String branchId,
  required double quantity,
  int cost = 100,
  double lowStockThreshold = 2,
}) {
  return BranchInventory(
    businessId: 'biz-1',
    branchId: branchId,
    productId: 'product-1',
    quantity: quantity,
    reservedQuantity: 0,
    lowStockThreshold: lowStockThreshold,
    averageUnitCostMinor: cost,
    stockCostValueMinor: (quantity * cost).round(),
    expectedStockRevenueMinor: (quantity * 200).round(),
    potentialProfitRemainingMinor: (quantity * (200 - cost)).round(),
    realizedGrossProfitMinor: 0,
    expiringQuantity: 0,
    expiredQuantity: 0,
    unknownExpiryQuantity: 0,
    nextExpiryBatchQuantity: 0,
    expiryStatus: ProductExpiryStatus.notTracked,
  );
}

void main() {
  group('Phase 3 branch inventory', () {
    test('keeps branch quantities separate', () {
      final main = inventory(branchId: 'main', quantity: 40);
      final east = inventory(branchId: 'east', quantity: 15);

      expect(main.quantity, 40);
      expect(east.quantity, 15);
    });

    test(
      'legacy branch inventory inherits the product low-stock threshold',
      () {
        final east = inventory(
          branchId: 'east',
          quantity: 2,
          lowStockThreshold: 0,
        );

        expect(east.effectiveLowStockThreshold(5), 5);
      },
    );

    test('aggregates stock only for All Branches reads', () {
      final aggregate = BranchInventory.aggregate(
        businessId: 'biz-1',
        productId: 'product-1',
        records: <BranchInventory>[
          inventory(branchId: 'main', quantity: 40),
          inventory(branchId: 'east', quantity: 15),
          inventory(branchId: 'west', quantity: 22),
        ],
        fallbackUnitCostMinor: 100,
        fallbackLowStockThreshold: 2,
      );

      expect(aggregate.branchId, isEmpty);
      expect(aggregate.quantity, 77);
      expect(aggregate.availableQuantity, 77);
      expect(aggregate.stockCostValueMinor, 7700);
    });

    test('uses weighted branch cost for aggregate', () {
      final aggregate = BranchInventory.aggregate(
        businessId: 'biz-1',
        productId: 'product-1',
        records: <BranchInventory>[
          inventory(branchId: 'main', quantity: 10, cost: 100),
          inventory(branchId: 'east', quantity: 10, cost: 200),
        ],
        fallbackUnitCostMinor: 50,
        fallbackLowStockThreshold: 2,
      );

      expect(aggregate.averageUnitCostMinor, 150);
    });

    test('legacy branchless records belong to Main Branch', () {
      const legacy = <String, dynamic>{'businessId': 'biz-1'};
      expect(matchesBranchScope(legacy, 'main'), isTrue);
      expect(matchesBranchScope(legacy, 'east'), isFalse);
    });

    test('All Branches reads include legacy branchless records', () {
      const legacy = <String, dynamic>{'businessId': 'biz-1'};
      expect(
        matchesBranchScopeWithMode(
          legacy,
          viewMode: BranchViewMode.allBranches,
        ),
        isTrue,
      );
    });

    test('single branch only matches its own records', () {
      const east = <String, dynamic>{'businessId': 'biz-1', 'branchId': 'east'};
      expect(matchesBranchScope(east, 'east'), isTrue);
      expect(matchesBranchScope(east, 'main'), isFalse);
      expect(matchesBranchScope(east, 'west'), isFalse);
    });

    test('reserved stock is excluded from available quantity', () {
      final row = BranchInventory(
        businessId: 'biz-1',
        branchId: 'main',
        productId: 'product-1',
        quantity: 10,
        reservedQuantity: 3,
        lowStockThreshold: 2,
        averageUnitCostMinor: 100,
        stockCostValueMinor: 1000,
        expectedStockRevenueMinor: 2000,
        potentialProfitRemainingMinor: 1000,
        realizedGrossProfitMinor: 0,
        expiringQuantity: 0,
        expiredQuantity: 0,
        unknownExpiryQuantity: 0,
        nextExpiryBatchQuantity: 0,
        expiryStatus: ProductExpiryStatus.notTracked,
      );

      expect(row.availableQuantity, 7);
    });

    test('empty aggregate is a non-writable zero-stock view', () {
      final aggregate = BranchInventory.aggregate(
        businessId: 'biz-1',
        productId: 'product-1',
        records: const <BranchInventory>[],
        fallbackUnitCostMinor: 100,
        fallbackLowStockThreshold: 2,
      );

      expect(aggregate.branchId, isEmpty);
      expect(aggregate.quantity, 0);
    });
  });
}
