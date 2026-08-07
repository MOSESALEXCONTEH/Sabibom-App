import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/receipts/domain/receipt_template.dart';

void main() {
  test('built-in templates are editable copies with stable names', () {
    final modern = ReceiptTemplate.builtIn(
      type: ReceiptTemplateType.modern,
      businessId: 'biz-1',
    );
    final classic = ReceiptTemplate.builtIn(
      type: ReceiptTemplateType.classic,
      businessId: 'biz-1',
    );
    expect(modern.name, 'Modern');
    expect(classic.name, 'Classic');
    expect(modern.isDefault, isFalse);
    expect(classic.isDefault, isFalse);

    final luxury = ReceiptTemplate.builtIn(
      type: ReceiptTemplateType.luxury,
      businessId: 'biz-1',
    );
    expect(luxury.isDefault, isTrue);
  });

  test('snapshot stores logo references not image bytes', () {
    final template = ReceiptTemplate.builtIn(
      type: ReceiptTemplateType.modern,
      businessId: 'biz-1',
    );
    final snapshot = template.toSnapshot(
      logoUrl: 'https://gateway.example/ipfs/cid123',
      logoCid: 'cid123',
    );
    expect(snapshot['logoCid'], 'cid123');
    expect(snapshot['logoUrl'], contains('cid123'));
    expect(snapshot.containsKey('logoBytes'), isFalse);
  });

  test('invalid color fallback remains readable hex strings', () {
    final template = ReceiptTemplate.fromMap('t1', <String, dynamic>{
      'businessId': 'biz-1',
      'name': 'Custom',
      'primaryColor': '#112233',
    });
    expect(template.primaryColor, '#112233');
    expect(template.textColor, '#111827');
  });

  test('string-backed values are parsed safely from legacy payloads', () {
    final template = ReceiptTemplate.fromMap('t1', <String, dynamic>{
      'businessId': 'biz-1',
      'name': 'Legacy',
      'templateType': 'modern',
      'paperSize': 'a4',
      'showBusinessName': 'true',
      'showSignature': 'false',
      'businessNameFontSize': '24',
      'accentAlpha': '0.8',
      'paidStampMode': 'always',
      'signatureMode': 'upload',
      'showQrCode': 'true',
      'qrCodeType': 'receiptNumber',
    });

    expect(template.templateType, ReceiptTemplateType.modern);
    expect(template.paperSize, ReceiptPaperSize.a4);
    expect(template.showBusinessName, isTrue);
    expect(template.showSignature, isFalse);
    expect(template.businessNameFontSize, 24);
    expect(template.accentAlpha, 0.8);
    expect(template.paidStampMode, ReceiptPaidStampMode.always);
    expect(template.signatureMode, ReceiptSignatureMode.upload);
    expect(template.showQrCode, isTrue);
    expect(template.qrCodeType, ReceiptQrCodeType.receiptNumber);
  });
}
