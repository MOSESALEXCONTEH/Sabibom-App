import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/core/sync/offline_mutation_queue.dart';
import 'package:sabibom/features/products/application/products_providers.dart';
import 'package:sabibom/features/purchases/domain/purchase.dart';

void main() {
  test('pending purchase adds stock only to its selected branch', () {
    final mutation = OfflineMutation(
      id: 'purchase-1',
      type: OfflineMutationType.purchaseComplete,
      userId: 'user-1',
      businessId: 'business-1',
      createdAt: DateTime.utc(2026, 8, 15),
      payload: <String, dynamic>{
        'summary': <String, dynamic>{'branchId': 'east'},
        'request': <String, dynamic>{
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'productId': 'rice',
              'quantity': 12,
              'trackStock': true,
            },
          ],
        },
      },
    );

    expect(
      pendingPurchaseStockAdditions(
        mutations: <OfflineMutation>[mutation],
        businessId: 'business-1',
        branchId: 'east',
      ),
      <String, double>{'rice': 12},
    );
    expect(
      pendingPurchaseStockAdditions(
        mutations: <OfflineMutation>[mutation],
        businessId: 'business-1',
        branchId: 'main',
      ),
      isEmpty,
    );
  });

  test('pending purchase summary reconstructs its details offline', () {
    final purchase = Purchase.fromMap('purchase-1', <String, dynamic>{
      'businessId': 'business-1',
      'branchId': 'east',
      'purchaseNumber': 'Pending purchase',
      'supplierId': 'supplier-1',
      'supplierName': 'Makeni Supply',
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'purchaseItemId': 'item-1',
          'productId': 'rice',
          'name': 'Rice',
          'quantity': 2,
          'unitCostMinor': 1000,
          'trackStock': true,
        },
      ],
      'subtotalMinor': 2000,
      'discountMinor': 0,
      'taxMinor': 0,
      'deliveryMinor': 0,
      'totalMinor': 2000,
      'amountPaidMinor': 2000,
      'balanceDueMinor': 0,
      'status': 'completed',
      'paymentStatus': 'paid',
      'createdAt': '2026-08-15T12:00:00.000Z',
    });

    expect(purchase.branchId, 'east');
    expect(purchase.items.single.name, 'Rice');
    expect(purchase.createdAt, DateTime.utc(2026, 8, 15, 12));
  });
}
