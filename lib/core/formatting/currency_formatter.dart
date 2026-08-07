import 'package:intl/intl.dart';

/// Formats monetary values without leaking null or non-finite values into UI.
String formatCurrency(
  num? amount, {
  String code = 'SLE',
  String symbol = 'Le',
}) {
  final safeAmount = amount == null || !amount.isFinite ? 0 : amount;
  return NumberFormat.currency(
    locale: 'en_GB',
    name: code,
    symbol: '$symbol ',
    decimalDigits: 2,
  ).format(safeAmount);
}
