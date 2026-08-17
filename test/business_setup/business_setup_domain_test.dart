import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/business_setup/domain/business_setup_data.dart';
import 'package:sabibom/features/business_setup/domain/business.dart';
import 'package:sabibom/features/business_setup/domain/business_operating_model.dart';
import 'package:sabibom/features/business_setup/domain/receipt_settings.dart';

void main() {
  test('defaults to a globally supported device currency and UTC timezone', () {
    final data = BusinessSetupData.initial();
    expect(
      CurrencyConfig.supported.map((currency) => currency.code),
      contains(data.currency.code),
    );
    expect(data.timezone, 'UTC');
    expect(BusinessSetupData.timezones, contains('Africa/Freetown'));
    expect(BusinessSetupData.timezones, contains('America/New_York'));
  });

  test('business persists selected global currency and timezone', () {
    final data = BusinessSetupData.initial().copyWith(
      currency: CurrencyConfig.usd,
      timezone: 'America/New_York',
    );
    final business = Business.fromSetupData(
      businessId: 'business-1',
      ownerId: 'owner-1',
      data: data,
    );

    expect(business.toMap()['currencyCode'], 'USD');
    expect(business.toMap()['timezone'], 'America/New_York');
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
