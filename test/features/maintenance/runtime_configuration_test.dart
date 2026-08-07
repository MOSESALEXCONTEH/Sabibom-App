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
  });

  test('missing release configuration remains backward compatible', () {
    final configuration = RuntimeConfiguration.fromMap({
      'maintenance': {'enabled': false, 'effectiveEnabled': false},
    });

    expect(configuration.maintenance.blocksMobile, isFalse);
    expect(configuration.androidRelease.minimumSupportedVersion, isNull);
  });
}
