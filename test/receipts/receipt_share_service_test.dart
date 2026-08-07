import 'package:flutter_test/flutter_test.dart';

void main() {
  test('safe PDF file names strip invalid path characters', () {
    const receiptNumber = 'SB/2026:07*18?';
    final safe = receiptNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final name = 'SabiBom_Receipt_$safe.pdf';
    expect(name, 'SabiBom_Receipt_SB_2026_07_18_.pdf');
    expect(name.contains('/'), isFalse);
    expect(name.contains(':'), isFalse);
    expect(name.contains('*'), isFalse);
    expect(name.contains('?'), isFalse);
  });
}
