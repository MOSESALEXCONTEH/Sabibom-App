import 'package:intl/intl.dart';

/// Presentation formatting helpers for business data.
abstract final class AppFormatters {
  /// Formats a number as a compact West African CFA currency amount.
  static String currency(num amount) => NumberFormat.currency(
    locale: 'en_GB',
    symbol: 'CFA ',
    decimalDigits: 0,
  ).format(amount);
}
