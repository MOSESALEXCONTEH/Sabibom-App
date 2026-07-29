import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/purchases/data/purchases_repository.dart';
import 'package:sabibom/features/purchases/domain/purchase.dart';

void main() {
  test('purchase command owns the final East Branch identity', () {
    const request = CompletePurchaseRequest(
      purchaseId: 'purchase-1',
      businessId: 'business-1',
      branchId: 'east',
      branchNameSnapshot: 'East Branch',
      branchCodeSnapshot: 'EAST',
      supplierId: 'supplier-1',
      supplierName: 'Supplier',
      items: <PurchaseItem>[
        PurchaseItem(
          purchaseItemId: 'line-1',
          productId: 'product-1',
          name: 'Rice',
          quantity: 1,
          unitCostMinor: 1000,
          trackStock: true,
        ),
      ],
      amountPaidMinor: 1000,
    );

    expect(request.businessId, 'business-1');
    expect(request.branchId, 'east');
    expect(request.branchNameSnapshot, 'East Branch');
    expect(request.branchCodeSnapshot, 'EAST');
  });
}
