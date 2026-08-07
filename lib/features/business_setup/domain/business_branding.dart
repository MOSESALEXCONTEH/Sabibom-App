/// Optional branding fields stored on the business document.
class BusinessBranding {
  const BusinessBranding({
    this.logoUrl,
    this.logoCid,
    this.logoFileName,
    this.logoMimeType,
    this.logoUpdatedAt,
    this.brandPrimaryColor = '#5B3DF5',
    this.brandSecondaryColor = '#10B981',
    this.receiptTextColor = '#111827',
    this.businessTagline,
    this.website,
    this.defaultReceiptTemplateId,
  });

  factory BusinessBranding.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const BusinessBranding();
    String? asString(Object? value) {
      if (value == null) return null;
      if (value is String) {
        final trimmed = value.trim();
        return trimmed.isEmpty ? null : trimmed;
      }
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    return BusinessBranding(
      logoUrl: asString(data['logoUrl']),
      logoCid: asString(data['logoCid']),
      logoFileName: asString(data['logoFileName']),
      logoMimeType: asString(data['logoMimeType']),
      logoUpdatedAt: null,
      brandPrimaryColor:
          asString(data['brandPrimaryColor']) ?? '#5B3DF5',
      brandSecondaryColor:
          asString(data['brandSecondaryColor']) ?? '#10B981',
      receiptTextColor: asString(data['receiptTextColor']) ?? '#111827',
      businessTagline: asString(data['businessTagline']),
      website: asString(data['website']),
      defaultReceiptTemplateId: asString(data['defaultReceiptTemplateId']),
    );
  }

  final String? logoUrl;
  final String? logoCid;
  final String? logoFileName;
  final String? logoMimeType;
  final DateTime? logoUpdatedAt;
  final String brandPrimaryColor;
  final String brandSecondaryColor;
  final String receiptTextColor;
  final String? businessTagline;
  final String? website;
  final String? defaultReceiptTemplateId;

  Map<String, Object?> toMap() => <String, Object?>{
    'logoUrl': logoUrl,
    'logoCid': logoCid,
    'logoFileName': logoFileName,
    'logoMimeType': logoMimeType,
    'brandPrimaryColor': brandPrimaryColor,
    'brandSecondaryColor': brandSecondaryColor,
    'receiptTextColor': receiptTextColor,
    'businessTagline': businessTagline,
    'website': website,
    'defaultReceiptTemplateId': defaultReceiptTemplateId,
  };
}
