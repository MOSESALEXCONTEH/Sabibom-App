import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/core/sync/offline_mutation_queue.dart';
import 'package:sabibom/features/sales/application/sales_providers.dart';
import 'package:sabibom/features/sales/domain/sale.dart';

OfflineMutation sale({
  required String id,
  required String branchId,
  required String productId,
  required double quantity,
}) => OfflineMutation(
  id: id,
  type: OfflineMutationType.saleComplete,
  userId: 'user-1',
  businessId: 'business-1',
  createdAt: DateTime.utc(2026, 8, 14),
  payload: <String, dynamic>{
    'summary': <String, dynamic>{'branchId': branchId},
    'request': <String, dynamic>{
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'productId': productId,
          'quantity': quantity,
          'trackStock': true,
        },
      ],
    },
  },
);

void main() {
  test('offline sales reserve stock only in their selected branch', () {
    final mutations = <OfflineMutation>[
      sale(id: 'east-1', branchId: 'east', productId: 'rice', quantity: 3),
      sale(id: 'east-2', branchId: 'east', productId: 'rice', quantity: 2),
      sale(id: 'main-1', branchId: 'main', productId: 'rice', quantity: 8),
    ];

    expect(
      pendingSaleStockReservations(
        mutations: mutations,
        businessId: 'business-1',
        branchId: 'east',
      ),
      <String, double>{'rice': 5},
    );
    expect(
      pendingSaleStockReservations(
        mutations: mutations,
        businessId: 'business-1',
        branchId: 'main',
      ),
      <String, double>{'rice': 8},
    );
  });

  test('pending sale reconstructs receipt items and stays branch scoped', () {
    final mutation = OfflineMutation(
      id: 'sale-sale-1',
      type: OfflineMutationType.saleComplete,
      userId: 'user-1',
      businessId: 'business-1',
      createdAt: DateTime.utc(2026, 8, 15),
      payload: <String, dynamic>{
        'summary': <String, dynamic>{
          'saleId': 'sale-1',
          'branchId': 'east',
          'receiptNumber': 'Pending sale-1',
          'totalMinor': 1800,
          'amountPaidMinor': 1800,
          'balanceDueMinor': 0,
          'createdAt': '2026-08-15T10:30:00.000Z',
        },
        'request': <String, dynamic>{
          'businessId': 'business-1',
          'branchId': 'east',
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'productId': 'rice',
              'name': 'Rice',
              'quantity': 2,
              'unitPriceMinor': 1000,
              'discountType': 'percentage',
              'discountValue': 10,
            },
          ],
        },
      },
    );

    final map = pendingSaleMapFromMutations(
      mutations: <OfflineMutation>[mutation],
      businessId: 'business-1',
      saleId: 'sale-1',
      branchId: 'east',
    );
    final sale = Sale.fromMap('sale-1', map!);
    expect(sale.items.single.lineTotalMinor, 1800);
    expect(sale.createdAt, DateTime.utc(2026, 8, 15, 10, 30));
    expect(
      pendingSaleMapFromMutations(
        mutations: <OfflineMutation>[mutation],
        businessId: 'business-1',
        saleId: 'sale-1',
        branchId: 'main',
      ),
      isNull,
    );
  });
}
