import 'dart:math' as math;

/// Simple WCAG-ish contrast helpers for receipt color warnings.
class ReceiptContrast {
  const ReceiptContrast._();

  static double relativeLuminance(String hex) {
    final cleaned = hex.replaceAll('#', '');
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return 0;
    final r = ((value >> 16) & 0xFF) / 255.0;
    final g = ((value >> 8) & 0xFF) / 255.0;
    final b = (value & 0xFF) / 255.0;
    double channel(double c) => c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
  }

  static double contrastRatio(String foregroundHex, String backgroundHex) {
    final l1 = relativeLuminance(foregroundHex);
    final l2 = relativeLuminance(backgroundHex);
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  static bool isPoorContrast(String foregroundHex, String backgroundHex) =>
      contrastRatio(foregroundHex, backgroundHex) < 4.5;
}
