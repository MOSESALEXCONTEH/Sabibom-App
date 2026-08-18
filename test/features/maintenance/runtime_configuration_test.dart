import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/maintenance/domain/runtime_configuration.dart';

void main() {
  test('parses maintenance and Android release configuration', () {
    final configuration = RuntimeConfiguration.fromMap({
      'maintenance': {
        'enabled': true,
        'effectiveEnabled': true,
        'scope': 'mobile',
        'message': 'Scheduled maintenance',
      },
      'release': {
        'android': {
          'latestVersion': '2.4.0',
          'minimumSupportedVersion': '2.1.0',
          'storeUrl':
              'https://play.google.com/store/apps/details?id=com.sabibom.app',
          'releaseNotes': 'Branch reporting improvements',
          'updatePolicy': {
            'schemaVersion': 2,
            'enabled': true,
            'effectiveEnabled': true,
            'environment': 'production',
            'packageId': 'com.sabibom.app',
            'latestBuildNumber': '24',
            'minimumBuildNumber': '21',
            'displayVersion': '2.4.0',
            'storeUrl':
                'https://play.google.com/store/apps/details?id=com.sabibom.app',
            'title': 'Update SabiBom',
            'message': 'Install the latest version.',
            'expiresAt': '2026-08-20T00:00:00.000Z',
            'revision': 3,
          },
        },
      },
    });

    expect(configuration.maintenance.blocksMobile, isTrue);
    expect(configuration.androidRelease.latestVersion, '2.4.0');
    expect(configuration.androidRelease.minimumSupportedVersion, '2.1.0');
    expect(
      configuration.androidRelease.releaseNotes,
      'Branch reporting improvements',
    );
    expect(configuration.androidRelease.updatePolicy.schemaVersion, 2);
    expect(configuration.androidRelease.updatePolicy.minimumBuildNumber, '21');
    expect(configuration.androidRelease.updatePolicy.revision, 3);
  });

  test('missing release configuration remains backward compatible', () {
    final configuration = RuntimeConfiguration.fromMap({
      'maintenance': {'enabled': false, 'effectiveEnabled': false},
    });

    expect(configuration.maintenance.blocksMobile, isFalse);
    expect(configuration.androidRelease.minimumSupportedVersion, isNull);
    expect(configuration.androidRelease.updatePolicy.enabled, isFalse);
  });
}
