import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/receipts/domain/receipt_contrast.dart';
import 'package:sabibom/features/receipts/domain/receipt_template.dart';
import 'package:sabibom/features/sales/domain/sale.dart';
import 'package:sabibom/features/sales/domain/sale_models.dart';

void main() {
  test('detects poor contrast combinations', () {
    expect(ReceiptContrast.isPoorContrast('#FFFFFF', '#FFFFFF'), isTrue);
    expect(ReceiptContrast.isPoorContrast('#111827', '#FFFFFF'), isFalse);
  });

  test('fromSnapshot falls back for older sales without snapshot', () {
    final template = ReceiptTemplate.fromSnapshot('biz-1', null);
    expect(template.templateType, ReceiptTemplateType.modern);
  });

  test('fromSnapshot hydrates saved sale design fields', () {
    final template = ReceiptTemplate.fromSnapshot('biz-1', <String, dynamic>{
      'templateId': 'tpl-1',
      'name': 'Classic Shop',
      'templateType': 'classic',
      'primaryColor': '#0F766E',
      'showTax': false,
      'footerMessage': 'Come again',
    });
    expect(template.id, 'tpl-1');
    expect(template.templateType, ReceiptTemplateType.classic);
    expect(template.primaryColor, '#0F766E');
    expect(template.showTax, isFalse);
    expect(template.footerMessage, 'Come again');
  });

  test('Sale parses receiptTemplateSnapshot map', () {
    final sale = Sale.fromMap('sale-1', <String, dynamic>{
      'businessId': 'biz-1',
      'receiptNumber': 'SB-1',
      'customerName': 'Walk-in',
      'items': <Map<String, dynamic>>[],
      'subtotalMinor': 100,
      'discountMinor': 0,
      'taxMinor': 0,
      'totalMinor': 100,
      'amountPaidMinor': 100,
      'balanceDueMinor': 0,
      'changeMinor': 0,
      'currencyCode': 'SLE',
      'currencySymbol': 'Le',
      'paymentMethod': 'cash',
      'paymentStatus': 'paid',
      'saleStatus': 'completed',
      'receiptTemplateSnapshot': <String, dynamic>{
        'templateId': 'tpl-9',
        'primaryColor': '#5B3DF5',
      },
    });
    expect(sale.receiptTemplateSnapshot?['templateId'], 'tpl-9');
    expect(sale.paymentMethod, PaymentMethod.cash);
  });
}
