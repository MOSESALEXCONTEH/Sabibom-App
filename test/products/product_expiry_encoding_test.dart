import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/products/data/products_repository.dart';

void main() {
  test(
    'product expiry is encoded as a valid UTC instant without date drift',
    () {
      final encoded = encodeProductInitialExpiryDate(DateTime(2026, 8, 20));

      expect(encoded, '2026-08-20T12:00:00.000Z');
      expect(DateTime.parse(encoded!).toUtc().day, 20);
    },
  );
}
