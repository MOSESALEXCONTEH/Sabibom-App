import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/maintenance/application/release_gate.dart';

void main() {
  test('requires an update when the installed version is older', () {
    expect(isVersionOlder('2.0.9', '2.1.0'), isTrue);
    expect(isVersionOlder('1.9.9', '2.0'), isTrue);
  });

  test('allows equal and newer installed versions', () {
    expect(isVersionOlder('2.1.0', '2.1.0'), isFalse);
    expect(isVersionOlder('2.2.0', '2.1.9'), isFalse);
    expect(isVersionOlder('2.1', '2.1.0'), isFalse);
  });
}
