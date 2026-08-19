import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/maintenance/application/release_gate.dart';
import 'package:sabibom/features/maintenance/domain/runtime_configuration.dart';

RuntimeAndroidUpdatePolicy policy({
  bool enabled = true,
  bool effectiveEnabled = true,
  String environment = 'production',
  String packageId = RuntimeAndroidUpdatePolicy.expectedPackageId,
  String latest = '100',
  String minimum = '80',
  String storeUrl = RuntimeAndroidUpdatePolicy.canonicalPlayUrl,
  DateTime? effectiveAt,
  DateTime? expiresAt,
}) => RuntimeAndroidUpdatePolicy(
  schemaVersion: 2,
  enabled: enabled,
  effectiveEnabled: effectiveEnabled,
  environment: environment,
  packageId: packageId,
  latestBuildNumber: latest,
  minimumBuildNumber: minimum,
  storeUrl: storeUrl,
  effectiveAt: effectiveAt,
  expiresAt: expiresAt ?? DateTime.utc(2026, 8, 20),
);

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

  test('requires an update only below the strict build-number floor', () {
    final now = DateTime.utc(2026, 8, 18);
    expect(
      shouldRequireAndroidUpdate(
        installedBuildNumber: '79',
        policy: policy(),
        now: now,
      ),
      isTrue,
    );
    expect(
      shouldRequireAndroidUpdate(
        installedBuildNumber: '80',
        policy: policy(),
        now: now,
      ),
      isFalse,
    );
    expect(
      shouldRequireAndroidUpdate(
        installedBuildNumber: '90071992547409930001',
        policy: policy(latest: '90071992547409930002', minimum: '100'),
        now: now,
      ),
      isFalse,
    );
  });

  test('fails open for disabled, malformed, future, or expired policy', () {
    final now = DateTime.utc(2026, 8, 18);
    bool required(RuntimeAndroidUpdatePolicy value) =>
        shouldRequireAndroidUpdate(
          installedBuildNumber: '1',
          policy: value,
          now: now,
        );

    expect(required(policy(enabled: false)), isFalse);
    expect(required(policy(effectiveEnabled: false)), isFalse);
    expect(required(policy(minimum: 'not-a-build')), isFalse);
    expect(required(policy(environment: 'preview')), isFalse);
    expect(required(policy(effectiveAt: DateTime.utc(2026, 8, 19))), isFalse);
    expect(required(policy(expiresAt: DateTime.utc(2026, 8, 17))), isFalse);
  });

  test('rejects a minimum build above the latest build', () {
    expect(
      shouldRequireAndroidUpdate(
        installedBuildNumber: '1',
        policy: policy(latest: '10', minimum: '11'),
        now: DateTime.utc(2026, 8, 18),
      ),
      isFalse,
    );
  });
}
