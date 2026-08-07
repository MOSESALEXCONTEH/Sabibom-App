import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/notifications/domain/expiry_notification_keys.dart';
import 'package:sabibom/features/products/domain/product.dart';
import 'package:sabibom/features/reports/domain/product_intelligence_report_models.dart';
import 'package:sabibom/features/sales/domain/sale.dart';
import 'package:sabibom/features/sales/domain/sale_models.dart';

void main() {
  group('ExpiryNotificationKeys', () {
    test('builds stable recipient-suffixed keys', () {
      expect(
        ExpiryNotificationKeys.approaching(
          businessId: 'b1',
          batchId: 'batch1',
          reminderDay: 7,
          userId: 'u1',
        ),
        'product_expiry_approaching_b1_batch1_7_u1',
      );
      expect(
        ExpiryNotificationKeys.expired(
          businessId: 'b1',
          batchId: 'batch1',
          userId: 'u1',
        ),
        'product_expired_b1_batch1_u1',
      );
    });
  });

  group('ProductProfitReport', () {
    test('aggregates realized profit from sale snapshots', () {
      final product = Product.fromMap('shoe', <String, dynamic>{
        'businessId': 'b1',
        'name': 'Shoe',
        'sellingPriceMinor': 2500,
        'costPriceMinor': 2000,
        'quantity': 40,
        'potentialProfitRemainingMinor': 20000,
        'status': 'active',
      });
      final sale = Sale.fromMap('s1', <String, dynamic>{
        'businessId': 'b1',
        'receiptNumber': 'R1',
        'customerName': 'Walk-in',
        'saleStatus': 'completed',
        'paymentMethod': 'cash',
        'paymentStatus': 'paid',
        'currencyCode': 'SLE',
        'currencySymbol': 'Le',
        'subtotalMinor': 25000,
        'discountMinor': 0,
        'taxMinor': 0,
        'totalMinor': 25000,
        'amountPaidMinor': 25000,
        'items': [
          {
            'productId': 'shoe',
            'name': 'Shoe',
            'quantity': 10,
            'unitPriceMinor': 2500,
            'lineTotalMinor': 25000,
            'costPriceMinor': 2000,
            'actualNetRevenueMinor': 25000,
            'costOfGoodsSoldMinor': 20000,
            'grossProfitMinor': 5000,
            'profitIsExact': true,
          },
        ],
      });

      final report = ProductProfitReport.fromProductsAndSales(
        products: [product],
        sales: [sale],
      );

      expect(report.rows, hasLength(1));
      expect(report.rows.first.realizedGrossProfitMinor, 5000);
      expect(report.rows.first.quantitySold, 10);
      expect(report.rows.first.potentialProfitRemainingMinor, 20000);
      expect(report.totalProjectedGrossProfitMinor, 25000);
    });
  });

  group('SaleLineItem profit fields', () {
    test('parses snapshot profit fields', () {
      final item = SaleLineItem.fromMap(<String, dynamic>{
        'productId': 'p1',
        'name': 'Milk',
        'quantity': 2,
        'unitPriceMinor': 1000,
        'lineTotalMinor': 2000,
        'costOfGoodsSoldMinor': 1400,
        'actualNetRevenueMinor': 2000,
        'grossProfitMinor': 600,
      });
      expect(item.productId, 'p1');
      expect(item.grossProfitMinor, 600);
      expect(SaleStatus.completed, isNot(SaleStatus.voided));
    });
  });
}
