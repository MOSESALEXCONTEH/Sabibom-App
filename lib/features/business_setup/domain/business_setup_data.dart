import 'receipt_settings.dart';

class CurrencyConfig {
  const CurrencyConfig({
    required this.code,
    required this.name,
    required this.symbol,
  });

  static const sle = CurrencyConfig(
    code: 'SLE',
    name: 'Sierra Leonean Leone',
    symbol: 'Le',
  );

  final String code;
  final String name;
  final String symbol;
}

enum BusinessSetupStep {
  businessDetails,
  contactAndLocation,
  financialSettings,
  receiptSettings,
  review,
}

class BusinessSetupData {
  const BusinessSetupData({
    required this.businessName,
    required this.businessType,
    required this.customBusinessType,
    required this.ownerName,
    required this.logoPath,
    required this.phoneNumber,
    required this.email,
    required this.address,
    required this.district,
    required this.customDistrict,
    required this.country,
    required this.currency,
    required this.taxEnabled,
    required this.taxPercentage,
    required this.financialYearStartMonth,
    required this.receiptSettings,
  });

  factory BusinessSetupData.initial() {
    return BusinessSetupData(
      businessName: '',
      businessType: '',
      customBusinessType: '',
      ownerName: '',
      logoPath: null,
      phoneNumber: '',
      email: '',
      address: '',
      district: '',
      customDistrict: '',
      country: 'Sierra Leone',
      currency: CurrencyConfig.sle,
      taxEnabled: false,
      taxPercentage: 0,
      financialYearStartMonth: 'January',
      receiptSettings: ReceiptSettings.initial(),
    );
  }

  static const businessTypes = <String>[
    'Retail Shop',
    'Restaurant',
    'Bar',
    'Pharmacy',
    'Supermarket',
    'Fashion',
    'Electronics',
    'Hardware',
    'Beauty Salon',
    'Barber Shop',
    'Mobile Money',
    'Wholesale',
    'Services',
    'Other',
  ];

  static const districts = <String>[
    'Bo',
    'Bombali',
    'Bonthe',
    'Falaba',
    'Kailahun',
    'Kambia',
    'Karene',
    'Kenema',
    'Koinadugu',
    'Kono',
    'Moyamba',
    'Port Loko',
    'Pujehun',
    'Tonkolili',
    'Western Area Rural',
    'Western Area Urban',
    'Other',
  ];

  static const months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  final String businessName;
  final String businessType;
  final String customBusinessType;
  final String ownerName;
  final String? logoPath;
  final String phoneNumber;
  final String email;
  final String address;
  final String district;
  final String customDistrict;
  final String country;
  final CurrencyConfig currency;
  final bool taxEnabled;
  final double taxPercentage;
  final String financialYearStartMonth;
  final ReceiptSettings receiptSettings;

  String get effectiveBusinessType =>
      businessType == 'Other' ? customBusinessType.trim() : businessType;

  String get effectiveDistrict =>
      district == 'Other' ? customDistrict.trim() : district;

  BusinessSetupData copyWith({
    String? businessName,
    String? businessType,
    String? customBusinessType,
    String? ownerName,
    String? logoPath,
    bool clearLogoPath = false,
    String? phoneNumber,
    String? email,
    String? address,
    String? district,
    String? customDistrict,
    String? country,
    CurrencyConfig? currency,
    bool? taxEnabled,
    double? taxPercentage,
    String? financialYearStartMonth,
    ReceiptSettings? receiptSettings,
  }) {
    return BusinessSetupData(
      businessName: businessName ?? this.businessName,
      businessType: businessType ?? this.businessType,
      customBusinessType: customBusinessType ?? this.customBusinessType,
      ownerName: ownerName ?? this.ownerName,
      logoPath: clearLogoPath ? null : (logoPath ?? this.logoPath),
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      address: address ?? this.address,
      district: district ?? this.district,
      customDistrict: customDistrict ?? this.customDistrict,
      country: country ?? this.country,
      currency: currency ?? this.currency,
      taxEnabled: taxEnabled ?? this.taxEnabled,
      taxPercentage: taxPercentage ?? this.taxPercentage,
      financialYearStartMonth:
          financialYearStartMonth ?? this.financialYearStartMonth,
      receiptSettings: receiptSettings ?? this.receiptSettings,
    );
  }

  Map<String, Object?> toLoggableMap() {
    return <String, Object?>{
      'businessName': businessName,
      'businessType': businessType,
      'customBusinessType': customBusinessType,
      'hasLogo': logoPath?.isNotEmpty == true,
      'district': district,
      'customDistrict': customDistrict,
      'country': country,
      'currency': currency.code,
      'taxEnabled': taxEnabled,
      'taxPercentage': taxPercentage,
      'financialYearStartMonth': financialYearStartMonth,
      'receiptSettings': receiptSettings.toLoggableMap(),
    };
  }
}
