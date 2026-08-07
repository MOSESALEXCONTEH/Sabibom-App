abstract final class StockQuantityRules {
  static const Set<String> decimalUnits = <String>{
    'kilogram',
    'kg',
    'litre',
    'liter',
    'l',
    'metre',
    'meter',
    'm',
  };

  static bool allowsDecimals(String unit) =>
      decimalUnits.contains(unit.trim().toLowerCase());

  static String? validate({
    required double? quantity,
    required String unit,
    bool allowZero = true,
  }) {
    if (quantity == null || !quantity.isFinite) {
      return 'Enter a valid stock quantity.';
    }
    if (quantity < 0 || (!allowZero && quantity == 0)) {
      return allowZero
          ? 'Stock cannot be negative.'
          : 'Stock must be greater than zero.';
    }
    if (!allowsDecimals(unit) && quantity != quantity.truncateToDouble()) {
      return '$unit quantities must be whole numbers.';
    }
    return null;
  }
}
