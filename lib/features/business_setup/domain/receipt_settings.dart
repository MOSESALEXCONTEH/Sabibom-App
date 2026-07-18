class ReceiptSettings {
  const ReceiptSettings({
    required this.businessName,
    required this.phoneNumber,
    required this.address,
    required this.footerMessage,
    required this.showLogo,
    required this.showCashierName,
    required this.showCustomerName,
    required this.showTaxBreakdown,
  });

  static const defaultFooterMessage = 'Thank you for doing business with us.';

  factory ReceiptSettings.initial() {
    return const ReceiptSettings(
      businessName: '',
      phoneNumber: '',
      address: '',
      footerMessage: defaultFooterMessage,
      showLogo: true,
      showCashierName: true,
      showCustomerName: true,
      showTaxBreakdown: false,
    );
  }

  final String businessName;
  final String phoneNumber;
  final String address;
  final String footerMessage;
  final bool showLogo;
  final bool showCashierName;
  final bool showCustomerName;
  final bool showTaxBreakdown;

  ReceiptSettings copyWith({
    String? businessName,
    String? phoneNumber,
    String? address,
    String? footerMessage,
    bool? showLogo,
    bool? showCashierName,
    bool? showCustomerName,
    bool? showTaxBreakdown,
  }) {
    return ReceiptSettings(
      businessName: businessName ?? this.businessName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      address: address ?? this.address,
      footerMessage: footerMessage ?? this.footerMessage,
      showLogo: showLogo ?? this.showLogo,
      showCashierName: showCashierName ?? this.showCashierName,
      showCustomerName: showCustomerName ?? this.showCustomerName,
      showTaxBreakdown: showTaxBreakdown ?? this.showTaxBreakdown,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'businessName': businessName,
      'phoneNumber': phoneNumber,
      'address': address,
      'footerMessage': footerMessage,
      'showLogo': showLogo,
      'showCashierName': showCashierName,
      'showCustomerName': showCustomerName,
      'showTaxBreakdown': showTaxBreakdown,
    };
  }

  Map<String, dynamic> toLoggableMap() {
    return <String, dynamic>{
      'businessName': businessName,
      'address': address,
      'footerMessage': footerMessage,
      'showLogo': showLogo,
      'showCashierName': showCashierName,
      'showCustomerName': showCustomerName,
      'showTaxBreakdown': showTaxBreakdown,
    };
  }
}
