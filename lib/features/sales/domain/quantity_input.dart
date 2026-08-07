/// Parses mixed quantity text such as `2 bags`, `1.5kg`, or `3`.
///
/// Calculations always use [QuantityInput.quantity]. The original text is kept
/// in [QuantityInput.raw] so receipts and carts can show what the merchant typed.
class QuantityInput {
  const QuantityInput({
    required this.raw,
    required this.quantity,
    required this.unit,
  });

  final String raw;
  final double quantity;
  final String unit;

  bool get isValid => quantity.isFinite && quantity > 0;
}

/// Parses mixed money text such as `50`, `50 Le`, or `paid`.
///
/// Calculations always use [MoneyInput.amount] (major currency units).
/// Text-only values like `paid` resolve to `0` so the line can show the note
/// without charging.
class MoneyInput {
  const MoneyInput({required this.raw, required this.amount});

  final String raw;
  final double amount;

  bool get isValid => raw.trim().isNotEmpty && amount.isFinite && amount >= 0;
}

/// Extracts the first number for math and any remaining letters as the unit.
QuantityInput parseQuantityInput(String input) {
  final raw = input.trim();
  if (raw.isEmpty) {
    return const QuantityInput(raw: '', quantity: 0, unit: 'unit');
  }

  final match = RegExp(r'(-?\d+(?:[.,]\d+)?)').firstMatch(raw);
  if (match == null) {
    final lettersOnly = raw
        .replaceAll(RegExp(r'[^A-Za-z\s/-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return QuantityInput(
      raw: raw,
      quantity: 0,
      unit: lettersOnly.isEmpty ? 'unit' : lettersOnly,
    );
  }

  final numberText = match.group(1)!.replaceAll(',', '.');
  final quantity = double.tryParse(numberText) ?? 0;
  final unit = raw
      .replaceRange(match.start, match.end, ' ')
      .replaceAll(RegExp(r'[^A-Za-z\s/-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  return QuantityInput(
    raw: raw,
    quantity: quantity,
    unit: unit.isEmpty ? 'unit' : unit,
  );
}

/// Extracts the first number for money math. Letter-only text → amount `0`.
MoneyInput parseMoneyInput(String input) {
  final raw = input.trim();
  if (raw.isEmpty) {
    return const MoneyInput(raw: '', amount: -1);
  }

  final match = RegExp(r'(-?\d+(?:[.,]\d+)?)').firstMatch(raw);
  if (match == null) {
    // e.g. "paid", "free", "complimentary"
    return MoneyInput(raw: raw, amount: 0);
  }

  final numberText = match.group(1)!.replaceAll(',', '.');
  final amount = double.tryParse(numberText) ?? -1;
  return MoneyInput(raw: raw, amount: amount);
}

/// Display label for a sale line quantity: prefer the merchant's original input.
String formatSaleQuantityLabel({
  required double quantity,
  required String unit,
  String? quantityInput,
}) {
  final recorded = quantityInput?.trim();
  if (recorded != null && recorded.isNotEmpty) return recorded;
  final qty = quantity == quantity.roundToDouble()
      ? quantity.toInt().toString()
      : quantity.toStringAsFixed(2);
  final unitLabel = unit.trim();
  if (unitLabel.isEmpty || unitLabel.toLowerCase() == 'unit') return qty;
  return '$qty $unitLabel';
}

/// Display label for unit price: prefer recorded text (e.g. `paid`).
String formatSaleUnitPriceLabel({
  required String formattedMoney,
  String? unitPriceInput,
}) {
  final recorded = unitPriceInput?.trim();
  if (recorded != null && recorded.isNotEmpty) return recorded;
  return formattedMoney;
}
