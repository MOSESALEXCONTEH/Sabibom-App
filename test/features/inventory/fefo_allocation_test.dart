import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/inventory/domain/inventory_batch.dart';
import 'package:sabibom/features/inventory/domain/product_profit_calculator.dart';

List<InventoryBatch> orderForFefo(List<InventoryBatch> batches) {
  final eligible = batches
      .where((batch) => batch.status == InventoryBatchStatus.active)
      .where((batch) => batch.quantityRemaining > 0)
      .toList();
  eligible.sort((left, right) {
    final leftKnown = left.hasKnownExpiry;
    final rightKnown = right.hasKnownExpiry;
    if (leftKnown && !rightKnown) return -1;
    if (!leftKnown && rightKnown) return 1;
    if (leftKnown && rightKnown) {
      return left.expiryDate!.compareTo(right.expiryDate!);
    }
    return left.receivedAt.compareTo(right.receivedAt);
  });
  return eligible;
}

List<BatchAllocation> allocateFefo({
  required double quantity,
  required List<InventoryBatch> batches,
}) {
  var remaining = quantity;
  final allocations = <BatchAllocation>[];
  for (final batch in orderForFefo(batches)) {
    if (remaining <= 0) break;
    final take = remaining < batch.quantityRemaining
        ? remaining
        : batch.quantityRemaining;
    allocations.add(
      BatchAllocation(
        batchId: batch.id,
        quantity: take,
        unitCostMinor: batch.unitCostMinor,
        expiryDate: batch.expiryDate,
        lineCostMinor: ProductProfitCalculator.lineValue(
          take,
          batch.unitCostMinor,
        ),
      ),
    );
    remaining -= take;
  }
  if (remaining > 0.0000001) {
    throw StateError('Insufficient batch stock');
  }
  return allocations;
}

void main() {
  test('FEFO consumes earliest known expiry first and spans batches', () {
    final batches = <InventoryBatch>[
      InventoryBatch(
        id: 'b',
        businessId: 'biz',
        branchId: 'main',
        productId: 'milk',
        productName: 'Milk',
        sourceType: InventoryBatchSourceType.purchase,
        quantityReceived: 10,
        quantityRemaining: 10,
        unitCostMinor: 2200,
        sellingPriceAtReceiptMinor: 3000,
        expiryDateKnown: true,
        expiryDate: DateTime.utc(2026, 9, 20),
        receivedAt: DateTime.utc(2026, 7, 1),
        status: InventoryBatchStatus.active,
      ),
      InventoryBatch(
        id: 'a',
        businessId: 'biz',
        branchId: 'main',
        productId: 'milk',
        productName: 'Milk',
        sourceType: InventoryBatchSourceType.purchase,
        quantityReceived: 5,
        quantityRemaining: 5,
        unitCostMinor: 2000,
        sellingPriceAtReceiptMinor: 3000,
        expiryDateKnown: true,
        expiryDate: DateTime.utc(2026, 8, 10),
        receivedAt: DateTime.utc(2026, 7, 1),
        status: InventoryBatchStatus.active,
      ),
      InventoryBatch(
        id: 'unknown',
        businessId: 'biz',
        branchId: 'main',
        productId: 'milk',
        productName: 'Milk',
        sourceType: InventoryBatchSourceType.manualStockIn,
        quantityReceived: 4,
        quantityRemaining: 4,
        unitCostMinor: 2100,
        sellingPriceAtReceiptMinor: 3000,
        expiryDateKnown: false,
        receivedAt: DateTime.utc(2026, 7, 2),
        status: InventoryBatchStatus.active,
      ),
    ];

    final allocations = allocateFefo(quantity: 7, batches: batches);
    expect(allocations.map((a) => a.batchId).toList(), <String>['a', 'b']);
    expect(allocations[0].quantity, 5);
    expect(allocations[1].quantity, 2);
    expect(orderForFefo(batches).last.id, 'unknown');
  });

  test('FEFO rejects insufficient stock', () {
    expect(
      () => allocateFefo(
        quantity: 3,
        batches: <InventoryBatch>[
          InventoryBatch(
            id: 'a',
            businessId: 'biz',
            branchId: 'main',
            productId: 'milk',
            productName: 'Milk',
            sourceType: InventoryBatchSourceType.purchase,
            quantityReceived: 2,
            quantityRemaining: 2,
            unitCostMinor: 2000,
            sellingPriceAtReceiptMinor: 3000,
            expiryDateKnown: true,
            expiryDate: DateTime.utc(2026, 8, 10),
            receivedAt: DateTime.utc(2026, 7, 1),
            status: InventoryBatchStatus.active,
          ),
        ],
      ),
      throwsStateError,
    );
  });
}
