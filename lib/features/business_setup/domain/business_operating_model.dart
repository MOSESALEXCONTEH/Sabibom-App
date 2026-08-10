enum BusinessOperatingModel {
  product,
  service,
  hybrid;

  String get storedValue => name;

  String get displayName => switch (this) {
    product => 'Products',
    service => 'Services',
    hybrid => 'Products and services',
  };

  String get description => switch (this) {
    product => 'Sell physical products and manage stock and purchases.',
    service => 'Provide services, record income, and manage clients.',
    hybrid => 'Sell physical products and provide services.',
  };

  static BusinessOperatingModel fromStorage(
    Object? value, {
    String? businessType,
    String? customBusinessType,
  }) {
    final raw = '$value'.trim().toLowerCase();
    for (final model in values) {
      if (model.name == raw) return model;
    }
    return inferFromBusinessType(
      businessType ?? '',
      customBusinessType: customBusinessType,
    );
  }

  static BusinessOperatingModel inferFromBusinessType(
    String businessType, {
    String? customBusinessType,
  }) {
    final effective = businessType.trim().toLowerCase() == 'other'
        ? (customBusinessType ?? '')
        : businessType;
    final normalized = effective.trim().toLowerCase();
    const serviceTerms = <String>[
      'service',
      'salon',
      'barber',
      'consult',
      'office',
      'agency',
      'laundry',
      'repair',
      'mobile money',
    ];
    if (serviceTerms.any(normalized.contains)) {
      return BusinessOperatingModel.service;
    }
    const hybridTerms = <String>['restaurant', 'bar', 'hotel', 'cafe'];
    if (hybridTerms.any(normalized.contains)) {
      return BusinessOperatingModel.hybrid;
    }
    return BusinessOperatingModel.product;
  }
}
