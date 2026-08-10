import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/business_setup/domain/business_setup_data.dart';
import 'package:sabibom/features/business_setup/domain/business.dart';
import 'package:sabibom/features/business_setup/domain/business_operating_model.dart';
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

  group('business operating model', () {
    test('infers service businesses from known and custom types', () {
      expect(
        BusinessOperatingModel.inferFromBusinessType('Barber Shop'),
        BusinessOperatingModel.service,
      );
      expect(
        BusinessOperatingModel.inferFromBusinessType(
          'Other',
          customBusinessType: 'Laundry and cleaning',
        ),
        BusinessOperatingModel.service,
      );
    });

    test('infers hybrid and product businesses conservatively', () {
      expect(
        BusinessOperatingModel.inferFromBusinessType('Restaurant'),
        BusinessOperatingModel.hybrid,
      );
      expect(
        BusinessOperatingModel.inferFromBusinessType('Retail Shop'),
        BusinessOperatingModel.product,
      );
    });

    test('legacy business infers model while stored override wins', () {
      final legacy = Business.fromFirestore(<String, dynamic>{
        'businessType': 'Beauty Salon',
      });
      final overridden = Business.fromFirestore(<String, dynamic>{
        'businessType': 'Beauty Salon',
        'operatingModel': 'hybrid',
      });

      expect(legacy.operatingModel, BusinessOperatingModel.service);
      expect(overridden.operatingModel, BusinessOperatingModel.hybrid);
      expect(overridden.toMap()['operatingModel'], 'hybrid');
    });
  });
}
