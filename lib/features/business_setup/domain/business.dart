import 'business_setup_data.dart';

class Business {
  const Business({
    required this.businessId,
    required this.name,
    required this.normalizedName,
    required this.ownerId,
    required this.businessType,
    required this.customBusinessType,
    required this.logoUrl,
    required this.phoneNumber,
    required this.email,
    required this.address,
    required this.district,
    required this.country,
    required this.currency,
    required this.taxEnabled,
    required this.taxPercentage,
    required this.financialYearStartMonth,
    required this.status,
  });

  factory Business.fromSetupData({
    required String businessId,
    required String ownerId,
    required BusinessSetupData data,
  }) {
    final name = data.businessName.trim();
    return Business(
      businessId: businessId,
      name: name,
      normalizedName: _normalizeName(name),
      ownerId: ownerId,
      businessType: data.businessType,
      customBusinessType: data.businessType == 'Other'
          ? data.customBusinessType.trim()
          : null,
      logoUrl: null,
      phoneNumber: data.phoneNumber.trim(),
      email: data.email.trim().isEmpty ? null : data.email.trim(),
      address: data.address.trim(),
      district: data.effectiveDistrict,
      country: data.country,
      currency: data.currency,
      taxEnabled: data.taxEnabled,
      taxPercentage: data.taxEnabled ? data.taxPercentage : 0,
      financialYearStartMonth: data.financialYearStartMonth,
      status: 'active',
    );
  }

  factory Business.fromFirestore(Map<String, dynamic> data) {
    return Business(
      businessId: data['businessId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      normalizedName: data['normalizedName'] as String? ?? '',
      ownerId: data['ownerId'] as String? ?? '',
      businessType: data['businessType'] as String? ?? '',
      customBusinessType: data['customBusinessType'] as String?,
      logoUrl: data['logoUrl'] as String?,
      phoneNumber: data['phoneNumber'] as String? ?? '',
      email: data['email'] as String?,
      address: data['address'] as String? ?? '',
      district: data['district'] as String? ?? '',
      country: data['country'] as String? ?? 'Sierra Leone',
      currency: CurrencyConfig(
        code: data['currencyCode'] as String? ?? CurrencyConfig.sle.code,
        name: data['currencyName'] as String? ?? CurrencyConfig.sle.name,
        symbol: data['currencySymbol'] as String? ?? CurrencyConfig.sle.symbol,
      ),
      taxEnabled: data['taxEnabled'] as bool? ?? false,
      taxPercentage: (data['taxPercentage'] as num?)?.toDouble() ?? 0,
      financialYearStartMonth: data['financialYearStartMonth'] as String? ?? 'January',
      status: data['status'] as String? ?? 'active',
    );
  }

  final String businessId;
  final String name;
  final String normalizedName;
  final String ownerId;
  final String businessType;
  final String? customBusinessType;
  final String? logoUrl;
  final String phoneNumber;
  final String? email;
  final String address;
  final String district;
  final String country;
  final CurrencyConfig currency;
  final bool taxEnabled;
  final double taxPercentage;
  final String financialYearStartMonth;
  final String status;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'businessId': businessId,
      'name': name,
      'normalizedName': normalizedName,
      'ownerId': ownerId,
      'businessType': businessType,
      'customBusinessType': customBusinessType,
      'logoUrl': logoUrl,
      'phoneNumber': phoneNumber,
      'email': email,
      'address': address,
      'district': district,
      'country': country,
      'currencyCode': currency.code,
      'currencyName': currency.name,
      'currencySymbol': currency.symbol,
      'taxEnabled': taxEnabled,
      'taxPercentage': taxPercentage,
      'financialYearStartMonth': financialYearStartMonth,
      'status': status,
    };
  }

  static String _normalizeName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
