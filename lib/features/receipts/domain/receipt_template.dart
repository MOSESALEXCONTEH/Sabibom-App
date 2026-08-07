enum ReceiptTemplateType {
  modern,
  classic,
  minimal,
  luxury,
  gradient,
  corporate,
  boutique,
  bold,
  retail,
  wave,
}

enum ReceiptPaperSize { thermal58, thermal80, a4, digital }

enum ReceiptLogoSize { small, medium, large, xlarge }

enum ReceiptLogoShape { circle, rounded, original }

enum ReceiptAlignment { left, center, right }

enum ReceiptQrCodeType { none, receiptNumber, businessWebsite }

enum ReceiptPaidStampMode { hidden, paidOnly, unpaidOnly, always }

enum ReceiptShadingStyle {
  none,
  softWave,
  darkMesh,
  cornerGlow,
  auroraMist,
  diagonalSweep,
  sunsetBloom,
  paperTexture,
}

enum ReceiptSignatureMode { placeholder, draw, upload }

class ReceiptTemplate {
  const ReceiptTemplate({
    required this.id,
    required this.businessId,
    required this.name,
    required this.templateType,
    required this.paperSize,
    required this.isDefault,
    required this.primaryColor,
    required this.secondaryColor,
    required this.textColor,
    required this.backgroundColor,
    required this.accentAlpha,
    required this.shadingStyle,
    required this.headerAlignment,
    required this.logoEnabled,
    required this.logoSize,
    required this.logoShape,
    required this.showBusinessName,
    required this.showBusinessPhone,
    required this.showBusinessEmail,
    required this.showBusinessAddress,
    required this.showWebsite,
    required this.showCustomer,
    required this.showCashier,
    required this.showSku,
    required this.showUnitPrice,
    required this.showDiscount,
    required this.showTax,
    required this.showPaymentDetails,
    required this.showNotes,
    required this.showSignature,
    required this.signatureMode,
    required this.signatureImageBase64,
    required this.shadingImageUrl,
    required this.signatureScale,
    required this.paidStampMode,
    required this.paidStampText,
    required this.unpaidStampText,
    required this.showQrCode,
    required this.qrCodeType,
    required this.customHeader,
    required this.footerMessage,
    required this.returnPolicy,
    required this.termsText,
    required this.watermarkText,
    this.businessNameFontSize = 18,
    this.bodyFontSize = 12,
    this.totalFontSize = 16,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory ReceiptTemplate.builtIn({
    required ReceiptTemplateType type,
    required String businessId,
  }) {
    final spec = builtInSpec(type);
    return ReceiptTemplate(
      id: 'builtin_${type.name}',
      businessId: businessId,
      name: spec.name,
      templateType: type,
      paperSize: spec.paperSize,
      isDefault: type == ReceiptTemplateType.luxury,
      primaryColor: spec.primaryColor,
      secondaryColor: spec.secondaryColor,
      textColor: spec.textColor,
      backgroundColor: spec.backgroundColor,
      accentAlpha: 1,
        shadingStyle: type == ReceiptTemplateType.luxury
          ? ReceiptShadingStyle.darkMesh
          : type == ReceiptTemplateType.wave
          ? ReceiptShadingStyle.softWave
          : ReceiptShadingStyle.none,
      headerAlignment: spec.headerAlignment,
      logoEnabled: true,
      logoSize: ReceiptLogoSize.medium,
      logoShape: spec.logoShape,
      showBusinessName: true,
      showBusinessPhone: true,
      showBusinessEmail: type != ReceiptTemplateType.minimal,
      showBusinessAddress: true,
      showWebsite: spec.showWebsite,
      showCustomer: true,
      showCashier: true,
      showSku: type != ReceiptTemplateType.minimal &&
          type != ReceiptTemplateType.retail,
      showUnitPrice: true,
      showDiscount: true,
      showTax: true,
      showPaymentDetails: true,
      showNotes: true,
      showSignature: spec.showSignature,
      signatureMode: ReceiptSignatureMode.placeholder,
      signatureImageBase64: null,
      shadingImageUrl: null,
      signatureScale: 1,
      paidStampMode: ReceiptPaidStampMode.unpaidOnly,
      paidStampText: 'The invoice has been paid.',
      unpaidStampText: 'The invoice has not been paid.',
      showQrCode: type == ReceiptTemplateType.modern,
      qrCodeType: type == ReceiptTemplateType.modern
          ? ReceiptQrCodeType.receiptNumber
          : ReceiptQrCodeType.none,
      customHeader: spec.customHeader,
      footerMessage: spec.footerMessage,
      returnPolicy: '',
      termsText: '',
      watermarkText: '',
    );
  }

  /// Default look-and-feel for each built-in design.
  static ReceiptBuiltInSpec builtInSpec(ReceiptTemplateType type) =>
      switch (type) {
        ReceiptTemplateType.modern => const ReceiptBuiltInSpec(
          name: 'Modern',
          description: 'Clean centered header with rounded accents.',
          primaryColor: '#5B3DF5',
          secondaryColor: '#10B981',
          logoShape: ReceiptLogoShape.circle,
          showWebsite: true,
        ),
        ReceiptTemplateType.classic => const ReceiptBuiltInSpec(
          name: 'Classic',
          description: 'Traditional store receipt with signature line.',
          primaryColor: '#1F2937',
          secondaryColor: '#6B7280',
          showSignature: true,
        ),
        ReceiptTemplateType.minimal => const ReceiptBuiltInSpec(
          name: 'Minimal',
          description: 'Just the essentials, lots of white space.',
          primaryColor: '#111827',
          secondaryColor: '#9CA3AF',
        ),
        ReceiptTemplateType.luxury => const ReceiptBuiltInSpec(
          name: 'Luxury Invoice',
          description: 'Dark banner with gold rules, A4 invoice look.',
          primaryColor: '#1E1B4B',
          secondaryColor: '#C9A227',
          paperSize: ReceiptPaperSize.a4,
          headerAlignment: ReceiptAlignment.left,
          showSignature: true,
          showWebsite: true,
          customHeader: 'RECEIPT',
          footerMessage:
              'Thank you for your business. Payment due upon receipt unless noted.',
        ),
        ReceiptTemplateType.gradient => const ReceiptBuiltInSpec(
          name: 'Gradient Luxe',
          description: 'Sweeping color gradient header and totals band.',
          primaryColor: '#7C3AED',
          secondaryColor: '#DB2777',
          paperSize: ReceiptPaperSize.a4,
          headerAlignment: ReceiptAlignment.left,
          showWebsite: true,
          customHeader: 'RECEIPT',
        ),
        ReceiptTemplateType.corporate => const ReceiptBuiltInSpec(
          name: 'Corporate',
          description: 'Side accent stripe with structured two-column header.',
          primaryColor: '#0F4C81',
          secondaryColor: '#38BDF8',
          paperSize: ReceiptPaperSize.a4,
          headerAlignment: ReceiptAlignment.left,
          showSignature: true,
          showWebsite: true,
          customHeader: 'RECEIPT',
        ),
        ReceiptTemplateType.boutique => const ReceiptBuiltInSpec(
          name: 'Boutique',
          description: 'Elegant centered layout with thin ruled dividers.',
          primaryColor: '#8C5E3C',
          secondaryColor: '#D4B08C',
          backgroundColor: '#FFFBF5',
          customHeader: 'Thank you',
        ),
        ReceiptTemplateType.bold => const ReceiptBuiltInSpec(
          name: 'Bold Blocks',
          description: 'High-contrast color blocks and oversized total.',
          primaryColor: '#DC2626',
          secondaryColor: '#111827',
          paperSize: ReceiptPaperSize.a4,
          headerAlignment: ReceiptAlignment.left,
          customHeader: 'RECEIPT',
        ),
        ReceiptTemplateType.retail => const ReceiptBuiltInSpec(
          name: 'Retail Till',
          description: 'Compact till-roll style, great for thermal printers.',
          primaryColor: '#111827',
          secondaryColor: '#374151',
          paperSize: ReceiptPaperSize.thermal80,
        ),
        ReceiptTemplateType.wave => const ReceiptBuiltInSpec(
          name: 'Soft Wave',
          description: 'Rounded pastel header with pill totals card.',
          primaryColor: '#0D9488',
          secondaryColor: '#F59E0B',
          backgroundColor: '#FDFDFB',
          logoShape: ReceiptLogoShape.circle,
          showWebsite: true,
        ),
      };

  /// Hydrate a template from a sale snapshot, or fall back to Modern.
  factory ReceiptTemplate.fromSnapshot(
    String businessId,
    Map<String, dynamic>? snapshot,
  ) {
    if (snapshot == null || snapshot.isEmpty) {
      return ReceiptTemplate.builtIn(
        type: ReceiptTemplateType.modern,
        businessId: businessId,
      );
    }
    final id = (snapshot['templateId'] as String?)?.trim();
    return ReceiptTemplate.fromMap(
      (id == null || id.isEmpty) ? 'snapshot' : id,
      <String, dynamic>{'businessId': businessId, ...snapshot},
    );
  }

  factory ReceiptTemplate.fromMap(String id, Map<String, dynamic> data) {
    bool parseBool(Object? value, {required bool fallback}) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
          return true;
        }
        if (normalized == 'false' || normalized == '0' || normalized == 'no') {
          return false;
        }
      }
      return fallback;
    }

    double parseDouble(Object? value, {required double fallback}) {
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
      return fallback;
    }

    T parseEnum<T extends Enum>(
      List<T> values,
      Object? value,
      T fallback,
    ) {
      if (value is T) return value;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        for (final item in values) {
          if (item.name.toLowerCase() == normalized) return item;
        }
      }
      return fallback;
    }

    ReceiptTemplateType parseType(Object? value) =>
        parseEnum(ReceiptTemplateType.values, value, ReceiptTemplateType.modern);
    ReceiptPaperSize parsePaper(Object? value) =>
        parseEnum(ReceiptPaperSize.values, value, ReceiptPaperSize.digital);
    return ReceiptTemplate(
      id: id,
      businessId: data['businessId'] as String? ?? '',
      name: data['name'] as String? ?? 'Receipt',
      templateType: parseType(data['templateType']),
      paperSize: parsePaper(data['paperSize']),
      isDefault: data['isDefault'] as bool? ?? false,
      primaryColor: data['primaryColor'] as String? ?? '#5B3DF5',
      secondaryColor: data['secondaryColor'] as String? ?? '#10B981',
      textColor: data['textColor'] as String? ?? '#111827',
      backgroundColor: data['backgroundColor'] as String? ?? '#FFFFFF',
      accentAlpha: parseDouble(data['accentAlpha'], fallback: 1),
      shadingStyle: parseEnum(
        ReceiptShadingStyle.values,
        data['shadingStyle'],
        ReceiptShadingStyle.none,
      ),
      headerAlignment: parseEnum(
        ReceiptAlignment.values,
        data['headerAlignment'],
        ReceiptAlignment.center,
      ),
      businessNameFontSize:
          parseDouble(data['businessNameFontSize'], fallback: 18),
      bodyFontSize: parseDouble(data['bodyFontSize'], fallback: 12),
      totalFontSize: parseDouble(data['totalFontSize'], fallback: 16),
      logoEnabled: parseBool(data['logoEnabled'], fallback: true),
      logoSize: parseEnum(
        ReceiptLogoSize.values,
        data['logoSize'],
        ReceiptLogoSize.medium,
      ),
      logoShape: parseEnum(
        ReceiptLogoShape.values,
        data['logoShape'],
        ReceiptLogoShape.rounded,
      ),
      showBusinessName: parseBool(data['showBusinessName'], fallback: true),
      showBusinessPhone: parseBool(data['showBusinessPhone'], fallback: true),
      showBusinessEmail: parseBool(data['showBusinessEmail'], fallback: true),
      showBusinessAddress: parseBool(data['showBusinessAddress'], fallback: true),
      showWebsite: parseBool(data['showWebsite'], fallback: false),
      showCustomer: parseBool(data['showCustomer'], fallback: true),
      showCashier: parseBool(data['showCashier'], fallback: true),
      showSku: parseBool(data['showSku'], fallback: false),
      showUnitPrice: parseBool(data['showUnitPrice'], fallback: true),
      showDiscount: parseBool(data['showDiscount'], fallback: true),
      showTax: parseBool(data['showTax'], fallback: true),
      showPaymentDetails: parseBool(data['showPaymentDetails'], fallback: true),
      showNotes: parseBool(data['showNotes'], fallback: true),
      showSignature: parseBool(data['showSignature'], fallback: false),
      signatureMode: parseEnum(
        ReceiptSignatureMode.values,
        data['signatureMode'],
        ReceiptSignatureMode.placeholder,
      ),
      signatureImageBase64: (data['signatureImageBase64'] as String?)?.trim(),
      shadingImageUrl: (data['shadingImageUrl'] as String?)?.trim(),
      signatureScale: parseDouble(data['signatureScale'], fallback: 1),
      paidStampMode: parseEnum(
        ReceiptPaidStampMode.values,
        data['paidStampMode'],
        ReceiptPaidStampMode.unpaidOnly,
      ),
      paidStampText:
          data['paidStampText'] as String? ?? 'The invoice has been paid.',
      unpaidStampText:
          data['unpaidStampText'] as String? ?? 'The invoice has not been paid.',
      showQrCode: parseBool(data['showQrCode'], fallback: false),
      qrCodeType: parseEnum(
        ReceiptQrCodeType.values,
        data['qrCodeType'],
        ReceiptQrCodeType.none,
      ),
      customHeader: data['customHeader'] as String? ?? '',
      footerMessage:
          data['footerMessage'] as String? ??
          'Thank you for doing business with us.',
      returnPolicy: data['returnPolicy'] as String? ?? '',
      termsText: data['termsText'] as String? ?? '',
      watermarkText: data['watermarkText'] as String? ?? '',
      createdBy: data['createdBy'] as String?,
    );
  }

  final String id;
  final String businessId;
  final String name;
  final ReceiptTemplateType templateType;
  final ReceiptPaperSize paperSize;
  final bool isDefault;
  final String primaryColor;
  final String secondaryColor;
  final String textColor;
  final String backgroundColor;
  final double accentAlpha;
  final ReceiptShadingStyle shadingStyle;
  final ReceiptAlignment headerAlignment;
  final double businessNameFontSize;
  final double bodyFontSize;
  final double totalFontSize;
  final bool logoEnabled;
  final ReceiptLogoSize logoSize;
  final ReceiptLogoShape logoShape;
  final bool showBusinessName;
  final bool showBusinessPhone;
  final bool showBusinessEmail;
  final bool showBusinessAddress;
  final bool showWebsite;
  final bool showCustomer;
  final bool showCashier;
  final bool showSku;
  final bool showUnitPrice;
  final bool showDiscount;
  final bool showTax;
  final bool showPaymentDetails;
  final bool showNotes;
  final bool showSignature;
  final ReceiptSignatureMode signatureMode;
  final String? signatureImageBase64;
  final String? shadingImageUrl;
  final double signatureScale;
  final ReceiptPaidStampMode paidStampMode;
  final String paidStampText;
  final String unpaidStampText;
  final bool showQrCode;
  final ReceiptQrCodeType qrCodeType;
  final String customHeader;
  final String footerMessage;
  final String returnPolicy;
  final String termsText;
  final String watermarkText;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ReceiptTemplate copyWith({
    String? id,
    String? name,
    ReceiptTemplateType? templateType,
    ReceiptPaperSize? paperSize,
    bool? isDefault,
    String? primaryColor,
    String? secondaryColor,
    String? textColor,
    String? backgroundColor,
    double? businessNameFontSize,
    double? bodyFontSize,
    double? totalFontSize,
    double? accentAlpha,
    ReceiptShadingStyle? shadingStyle,
    ReceiptAlignment? headerAlignment,
    bool? logoEnabled,
    ReceiptLogoSize? logoSize,
    ReceiptLogoShape? logoShape,
    bool? showBusinessName,
    bool? showBusinessPhone,
    bool? showBusinessEmail,
    bool? showBusinessAddress,
    bool? showWebsite,
    bool? showCustomer,
    bool? showCashier,
    bool? showSku,
    bool? showUnitPrice,
    bool? showDiscount,
    bool? showTax,
    bool? showPaymentDetails,
    bool? showNotes,
    bool? showSignature,
    ReceiptSignatureMode? signatureMode,
    String? signatureImageBase64,
    String? shadingImageUrl,
    bool clearShadingImage = false,
    double? signatureScale,
    bool clearSignatureImage = false,
    ReceiptPaidStampMode? paidStampMode,
    String? paidStampText,
    String? unpaidStampText,
    bool? showQrCode,
    ReceiptQrCodeType? qrCodeType,
    String? customHeader,
    String? footerMessage,
    String? returnPolicy,
    String? termsText,
    String? watermarkText,
  }) => ReceiptTemplate(
    id: id ?? this.id,
    businessId: businessId,
    name: name ?? this.name,
    templateType: templateType ?? this.templateType,
    paperSize: paperSize ?? this.paperSize,
    isDefault: isDefault ?? this.isDefault,
    primaryColor: primaryColor ?? this.primaryColor,
    secondaryColor: secondaryColor ?? this.secondaryColor,
    textColor: textColor ?? this.textColor,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    accentAlpha: accentAlpha ?? this.accentAlpha,
    shadingStyle: shadingStyle ?? this.shadingStyle,
    headerAlignment: headerAlignment ?? this.headerAlignment,
    businessNameFontSize: businessNameFontSize ?? this.businessNameFontSize,
    bodyFontSize: bodyFontSize ?? this.bodyFontSize,
    totalFontSize: totalFontSize ?? this.totalFontSize,
    logoEnabled: logoEnabled ?? this.logoEnabled,
    logoSize: logoSize ?? this.logoSize,
    logoShape: logoShape ?? this.logoShape,
    showBusinessName: showBusinessName ?? this.showBusinessName,
    showBusinessPhone: showBusinessPhone ?? this.showBusinessPhone,
    showBusinessEmail: showBusinessEmail ?? this.showBusinessEmail,
    showBusinessAddress: showBusinessAddress ?? this.showBusinessAddress,
    showWebsite: showWebsite ?? this.showWebsite,
    showCustomer: showCustomer ?? this.showCustomer,
    showCashier: showCashier ?? this.showCashier,
    showSku: showSku ?? this.showSku,
    showUnitPrice: showUnitPrice ?? this.showUnitPrice,
    showDiscount: showDiscount ?? this.showDiscount,
    showTax: showTax ?? this.showTax,
    showPaymentDetails: showPaymentDetails ?? this.showPaymentDetails,
    showNotes: showNotes ?? this.showNotes,
    showSignature: showSignature ?? this.showSignature,
    signatureMode: signatureMode ?? this.signatureMode,
    signatureImageBase64: clearSignatureImage
      ? null
      : (signatureImageBase64 ?? this.signatureImageBase64),
    shadingImageUrl: clearShadingImage
      ? null
      : (shadingImageUrl ?? this.shadingImageUrl),
    signatureScale: signatureScale ?? this.signatureScale,
    paidStampMode: paidStampMode ?? this.paidStampMode,
    paidStampText: paidStampText ?? this.paidStampText,
    unpaidStampText: unpaidStampText ?? this.unpaidStampText,
    showQrCode: showQrCode ?? this.showQrCode,
    qrCodeType: qrCodeType ?? this.qrCodeType,
    customHeader: customHeader ?? this.customHeader,
    footerMessage: footerMessage ?? this.footerMessage,
    returnPolicy: returnPolicy ?? this.returnPolicy,
    termsText: termsText ?? this.termsText,
    watermarkText: watermarkText ?? this.watermarkText,
    createdBy: createdBy,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'businessId': businessId,
    'name': name,
    'templateType': templateType.name,
    'paperSize': paperSize.name,
    'isDefault': isDefault,
    'primaryColor': primaryColor,
    'secondaryColor': secondaryColor,
    'textColor': textColor,
    'backgroundColor': backgroundColor,
    'accentAlpha': accentAlpha,
    'shadingStyle': shadingStyle.name,
    'headerAlignment': headerAlignment.name,
    'businessNameFontSize': businessNameFontSize,
    'bodyFontSize': bodyFontSize,
    'totalFontSize': totalFontSize,
    'logoEnabled': logoEnabled,
    'logoSize': logoSize.name,
    'logoShape': logoShape.name,
    'showBusinessName': showBusinessName,
    'showBusinessPhone': showBusinessPhone,
    'showBusinessEmail': showBusinessEmail,
    'showBusinessAddress': showBusinessAddress,
    'showWebsite': showWebsite,
    'showCustomer': showCustomer,
    'showCashier': showCashier,
    'showSku': showSku,
    'showUnitPrice': showUnitPrice,
    'showDiscount': showDiscount,
    'showTax': showTax,
    'showPaymentDetails': showPaymentDetails,
    'showNotes': showNotes,
    'showSignature': showSignature,
    'signatureMode': signatureMode.name,
    'signatureImageBase64': signatureImageBase64,
    'shadingImageUrl': shadingImageUrl,
    'signatureScale': signatureScale,
    'paidStampMode': paidStampMode.name,
    'paidStampText': paidStampText,
    'unpaidStampText': unpaidStampText,
    'showQrCode': showQrCode,
    'qrCodeType': qrCodeType.name,
    'customHeader': customHeader,
    'footerMessage': footerMessage,
    'returnPolicy': returnPolicy,
    'termsText': termsText,
    'watermarkText': watermarkText,
  };

  /// Compact snapshot stored on sale documents.
  Map<String, Object?> toSnapshot({String? logoUrl, String? logoCid}) =>
      <String, Object?>{
        'templateId': id,
        'name': name,
        'templateType': templateType.name,
        'paperSize': paperSize.name,
        'primaryColor': primaryColor,
        'secondaryColor': secondaryColor,
        'textColor': textColor,
        'backgroundColor': backgroundColor,
        'accentAlpha': accentAlpha,
        'shadingStyle': shadingStyle.name,
        'headerAlignment': headerAlignment.name,
        'businessNameFontSize': businessNameFontSize,
        'bodyFontSize': bodyFontSize,
        'totalFontSize': totalFontSize,
        'logoEnabled': logoEnabled,
        'logoSize': logoSize.name,
        'logoShape': logoShape.name,
        'logoUrl': logoUrl,
        'logoCid': logoCid,
        'showBusinessName': showBusinessName,
        'showBusinessPhone': showBusinessPhone,
        'showBusinessEmail': showBusinessEmail,
        'showBusinessAddress': showBusinessAddress,
        'showWebsite': showWebsite,
        'showCustomer': showCustomer,
        'showCashier': showCashier,
        'showSku': showSku,
        'showUnitPrice': showUnitPrice,
        'showDiscount': showDiscount,
        'showTax': showTax,
        'showPaymentDetails': showPaymentDetails,
        'showNotes': showNotes,
        'showSignature': showSignature,
        'signatureMode': signatureMode.name,
        'signatureImageBase64': signatureImageBase64,
        'shadingImageUrl': shadingImageUrl,
        'signatureScale': signatureScale,
        'paidStampMode': paidStampMode.name,
        'paidStampText': paidStampText,
        'unpaidStampText': unpaidStampText,
        'showQrCode': showQrCode,
        'footerMessage': footerMessage,
        'customHeader': customHeader,
      };
}

class ReceiptBuiltInSpec {
  const ReceiptBuiltInSpec({
    required this.name,
    required this.description,
    required this.primaryColor,
    required this.secondaryColor,
    this.textColor = '#111827',
    this.backgroundColor = '#FFFFFF',
    this.paperSize = ReceiptPaperSize.digital,
    this.headerAlignment = ReceiptAlignment.center,
    this.logoShape = ReceiptLogoShape.rounded,
    this.showSignature = false,
    this.showWebsite = false,
    this.customHeader = '',
    this.footerMessage = 'Thank you for doing business with us.',
  });

  final String name;
  final String description;
  final String primaryColor;
  final String secondaryColor;
  final String textColor;
  final String backgroundColor;
  final ReceiptPaperSize paperSize;
  final ReceiptAlignment headerAlignment;
  final ReceiptLogoShape logoShape;
  final bool showSignature;
  final bool showWebsite;
  final String customHeader;
  final String footerMessage;
}
