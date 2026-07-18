import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/business_setup/domain/business_setup_data.dart';
import 'package:sabibom/features/business_setup/domain/receipt_settings.dart';

void main() {
  test('defaults Sierra Leone currency', () {
    final data = BusinessSetupData.initial();
    expect(data.currency.code, 'SLE');
    expect(data.currency.name, 'Sierra Leonean Leone');
    expect(data.currency.symbol, 'Le');
  });

  test('receipt settings defaults are applied', () {
    final settings = ReceiptSettings.initial();
    expect(settings.footerMessage, ReceiptSettings.defaultFooterMessage);
    expect(settings.showLogo, isTrue);
    expect(settings.showTaxBreakdown, isFalse);
  });

  test('other business type uses custom type', () {
    final data = BusinessSetupData.initial().copyWith(
      businessType: 'Other',
      customBusinessType: 'Laundry',
    );
    expect(data.effectiveBusinessType, 'Laundry');
  });
}
