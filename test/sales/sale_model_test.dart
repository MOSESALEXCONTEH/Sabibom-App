import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/sales/domain/sale.dart';
import 'package:sabibom/features/sales/domain/sale_models.dart';

void main() {
  test('sale from map prefers provided document id', () {
    final sale = Sale.fromMap('doc-123', <String, dynamic>{
      'saleId': 'legacy-id',
      'receiptNumber': 'SB-1',
      'customerName': 'Walk-in Customer',
      'items': <Map<String, Object?>>[
        <String, Object?>{
          'name': 'Rice',
          'quantity': 1,
          'unitPriceMinor': 1000,
          'lineTotalMinor': 1000,
        },
      ],
      'subtotalMinor': 1000,
      'discountMinor': 0,
      'taxMinor': 0,
      'totalMinor': 1000,
      'amountPaidMinor': 1000,
      'balanceDueMinor': 0,
      'changeMinor': 0,
      'paymentMethod': 'cash',
      'paymentStatus': 'paid',
      'saleStatus': 'completed',
    });

    expect(sale.id, 'doc-123');
    expect(sale.receiptNumber, 'SB-1');
    expect(sale.items.single.name, 'Rice');
    expect(sale.paymentMethod, PaymentMethod.cash);
  });

  test('sale product supports sellingPriceMinor and legacy sellingPrice', () {
    final modern = SaleProduct.fromFirestore('p1', <String, dynamic>{
      'name': 'Rice',
      'sellingPriceMinor': 1500,
      'costPriceMinor': 900,
      'quantity': 4,
      'trackStock': true,
      'status': 'active',
    });
    final legacy = SaleProduct.fromFirestore('p2', <String, dynamic>{
      'name': 'Oil',
      'sellingPrice': 12.5,
      'costPrice': 8,
      'quantity': 2,
      'trackStock': true,
      'status': 'active',
    });

    expect(modern.sellingPriceMinor, 1500);
    expect(legacy.sellingPriceMinor, 1250);
    expect(legacy.costPriceMinor, 800);
  });

  test('sale preserves the stored East Branch receipt identity', () {
    final sale = Sale.fromMap('east-sale', <String, dynamic>{
      'businessId': 'business-1',
      'branchId': 'east',
      'branchNameSnapshot': 'East Branch',
      'branchCodeSnapshot': 'EAST',
      'receiptNumber': 'EAST-000001',
      'items': const <Map<String, Object?>>[],
      'paymentMethod': 'cash',
      'paymentStatus': 'paid',
      'saleStatus': 'completed',
    });

    expect(sale.branchId, 'east');
    expect(sale.branchNameSnapshot, 'East Branch');
    expect(sale.branchCodeSnapshot, 'EAST');
  });
}
