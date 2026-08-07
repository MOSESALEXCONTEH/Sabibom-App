/// Phone helpers for SMS / WhatsApp deep links (Sierra Leone first).
class PhoneE164 {
  const PhoneE164._();

  /// Digits only (strips spaces, dashes, leading +).
  static String digitsOnly(String? raw) {
    if (raw == null) return '';
    return raw.replaceAll(RegExp(r'\D'), '');
  }

  /// Returns international digits without +, e.g. `23276…`, or empty if invalid.
  static String toWhatsAppDigits(String? raw, {String defaultCountry = '232'}) {
    var digits = digitsOnly(raw);
    if (digits.isEmpty) return '';

    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    }

    if (digits.startsWith(defaultCountry)) {
      return digits;
    }

    // Local Sierra Leone mobiles often stored as 0XXXXXXXXX
    if (digits.startsWith('0') && digits.length >= 9) {
      return '$defaultCountry${digits.substring(1)}';
    }

    // 8–9 digit local without leading 0
    if (digits.length >= 8 && digits.length <= 9) {
      return '$defaultCountry$digits';
    }

    // Already looks international (10+ digits)
    if (digits.length >= 10) return digits;
    return '';
  }

  static bool canMessage(String? raw) => toWhatsAppDigits(raw).isNotEmpty;

  static String displayHint(String? raw) {
    final e164 = toWhatsAppDigits(raw);
    if (e164.isEmpty) return '';
    return '+$e164';
  }
}
