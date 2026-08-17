import 'dart:ui';

import 'receipt_settings.dart';
import 'business_operating_model.dart';

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

  static const usd = CurrencyConfig(
    code: 'USD',
    name: 'US Dollar',
    symbol: r'$',
  );

  static const supported = <CurrencyConfig>[
    usd,
    CurrencyConfig(code: 'EUR', name: 'Euro', symbol: '€'),
    CurrencyConfig(code: 'GBP', name: 'British Pound', symbol: '£'),
    sle,
    CurrencyConfig(code: 'NGN', name: 'Nigerian Naira', symbol: '₦'),
    CurrencyConfig(code: 'GHS', name: 'Ghanaian Cedi', symbol: 'GH₵'),
    CurrencyConfig(code: 'KES', name: 'Kenyan Shilling', symbol: 'KSh'),
    CurrencyConfig(code: 'ZAR', name: 'South African Rand', symbol: 'R'),
    CurrencyConfig(code: 'UGX', name: 'Ugandan Shilling', symbol: 'USh'),
    CurrencyConfig(code: 'TZS', name: 'Tanzanian Shilling', symbol: 'TSh'),
    CurrencyConfig(code: 'RWF', name: 'Rwandan Franc', symbol: 'RF'),
    CurrencyConfig(code: 'XOF', name: 'West African CFA Franc', symbol: 'CFA'),
    CurrencyConfig(
      code: 'XAF',
      name: 'Central African CFA Franc',
      symbol: 'FCFA',
    ),
    CurrencyConfig(code: 'MAD', name: 'Moroccan Dirham', symbol: 'MAD'),
    CurrencyConfig(code: 'EGP', name: 'Egyptian Pound', symbol: 'E£'),
    CurrencyConfig(code: 'INR', name: 'Indian Rupee', symbol: '₹'),
    CurrencyConfig(code: 'PKR', name: 'Pakistani Rupee', symbol: 'Rs'),
    CurrencyConfig(code: 'BDT', name: 'Bangladeshi Taka', symbol: '৳'),
    CurrencyConfig(code: 'AED', name: 'UAE Dirham', symbol: 'د.إ'),
    CurrencyConfig(code: 'SAR', name: 'Saudi Riyal', symbol: '﷼'),
    CurrencyConfig(code: 'CAD', name: 'Canadian Dollar', symbol: r'C$'),
    CurrencyConfig(code: 'AUD', name: 'Australian Dollar', symbol: r'A$'),
    CurrencyConfig(code: 'NZD', name: 'New Zealand Dollar', symbol: r'NZ$'),
    CurrencyConfig(code: 'JPY', name: 'Japanese Yen', symbol: '¥'),
    CurrencyConfig(code: 'CNY', name: 'Chinese Yuan', symbol: 'CN¥'),
    CurrencyConfig(code: 'SGD', name: 'Singapore Dollar', symbol: r'S$'),
    CurrencyConfig(code: 'MYR', name: 'Malaysian Ringgit', symbol: 'RM'),
    CurrencyConfig(code: 'PHP', name: 'Philippine Peso', symbol: '₱'),
    CurrencyConfig(code: 'IDR', name: 'Indonesian Rupiah', symbol: 'Rp'),
    CurrencyConfig(code: 'BRL', name: 'Brazilian Real', symbol: r'R$'),
    CurrencyConfig(code: 'MXN', name: 'Mexican Peso', symbol: r'MX$'),
    CurrencyConfig(code: 'CHF', name: 'Swiss Franc', symbol: 'CHF'),
    CurrencyConfig(code: 'TRY', name: 'Turkish Lira', symbol: '₺'),
  ];

  static CurrencyConfig deviceDefault() {
    final countryCode = PlatformDispatcher.instance.locale.countryCode
        ?.toUpperCase();
    final currencyCode = _countryCurrencies[countryCode] ?? 'USD';
    return supported.firstWhere(
      (currency) => currency.code == currencyCode,
      orElse: () => usd,
    );
  }

  static String deviceCountryName() {
    final countryCode = PlatformDispatcher.instance.locale.countryCode
        ?.toUpperCase();
    return _countryNames[countryCode] ?? '';
  }

  static const _countryCurrencies = <String?, String>{
    'SL': 'SLE',
    'US': 'USD',
    'GB': 'GBP',
    'IE': 'EUR',
    'FR': 'EUR',
    'DE': 'EUR',
    'ES': 'EUR',
    'IT': 'EUR',
    'NL': 'EUR',
    'BE': 'EUR',
    'NG': 'NGN',
    'GH': 'GHS',
    'KE': 'KES',
    'ZA': 'ZAR',
    'UG': 'UGX',
    'TZ': 'TZS',
    'RW': 'RWF',
    'IN': 'INR',
    'PK': 'PKR',
    'BD': 'BDT',
    'AE': 'AED',
    'SA': 'SAR',
    'CA': 'CAD',
    'AU': 'AUD',
    'NZ': 'NZD',
    'JP': 'JPY',
    'CN': 'CNY',
    'SG': 'SGD',
    'MY': 'MYR',
    'PH': 'PHP',
    'ID': 'IDR',
    'BR': 'BRL',
    'MX': 'MXN',
    'CH': 'CHF',
    'TR': 'TRY',
  };

  static const _countryNames = <String?, String>{
    'SL': 'Sierra Leone',
    'US': 'United States',
    'GB': 'United Kingdom',
    'IE': 'Ireland',
    'FR': 'France',
    'DE': 'Germany',
    'ES': 'Spain',
    'IT': 'Italy',
    'NL': 'Netherlands',
    'BE': 'Belgium',
    'NG': 'Nigeria',
    'GH': 'Ghana',
    'KE': 'Kenya',
    'ZA': 'South Africa',
    'UG': 'Uganda',
    'TZ': 'Tanzania',
    'RW': 'Rwanda',
    'IN': 'India',
    'PK': 'Pakistan',
    'BD': 'Bangladesh',
    'AE': 'United Arab Emirates',
    'SA': 'Saudi Arabia',
    'CA': 'Canada',
    'AU': 'Australia',
    'NZ': 'New Zealand',
    'JP': 'Japan',
    'CN': 'China',
    'SG': 'Singapore',
    'MY': 'Malaysia',
    'PH': 'Philippines',
    'ID': 'Indonesia',
    'BR': 'Brazil',
    'MX': 'Mexico',
    'CH': 'Switzerland',
    'TR': 'Türkiye',
  };

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
    this.operatingModel = BusinessOperatingModel.product,
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
    this.timezone = 'UTC',
    required this.taxEnabled,
    required this.taxPercentage,
    required this.financialYearStartMonth,
    required this.receiptSettings,
  });

  factory BusinessSetupData.initial() {
    return BusinessSetupData(
      businessName: '',
      businessType: '',
      operatingModel: BusinessOperatingModel.product,
      customBusinessType: '',
      ownerName: '',
      logoPath: null,
      phoneNumber: '',
      email: '',
      address: '',
      district: '',
      customDistrict: '',
      country: CurrencyConfig.deviceCountryName(),
      currency: CurrencyConfig.deviceDefault(),
      timezone: 'UTC',
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
    'Professional Services',
    'Office Services',
    'Laundry & Cleaning',
    'Repair Services',
    'Hotel',
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

  static const timezones = <String>[
    'UTC',
    'Africa/Freetown',
    'Africa/Accra',
    'Africa/Lagos',
    'Africa/Johannesburg',
    'Africa/Nairobi',
    'Africa/Cairo',
    'Europe/London',
    'Europe/Paris',
    'Europe/Berlin',
    'Asia/Dubai',
    'Asia/Kolkata',
    'Asia/Singapore',
    'Asia/Tokyo',
    'Australia/Sydney',
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'America/Toronto',
    'America/Sao_Paulo',
  ];

  final String businessName;
  final String businessType;
  final BusinessOperatingModel operatingModel;
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
  final String timezone;
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
    BusinessOperatingModel? operatingModel,
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
    String? timezone,
    bool? taxEnabled,
    double? taxPercentage,
    String? financialYearStartMonth,
    ReceiptSettings? receiptSettings,
  }) {
    return BusinessSetupData(
      businessName: businessName ?? this.businessName,
      businessType: businessType ?? this.businessType,
      operatingModel: operatingModel ?? this.operatingModel,
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
      timezone: timezone ?? this.timezone,
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
      'operatingModel': operatingModel.storedValue,
      'customBusinessType': customBusinessType,
      'hasLogo': logoPath?.isNotEmpty == true,
      'district': district,
      'customDistrict': customDistrict,
      'country': country,
      'currency': currency.code,
      'timezone': timezone,
      'taxEnabled': taxEnabled,
      'taxPercentage': taxPercentage,
      'financialYearStartMonth': financialYearStartMonth,
      'receiptSettings': receiptSettings.toLoggableMap(),
    };
  }
}
