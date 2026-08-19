import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android manifest removes broad media permissions from dependencies',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(
        manifest,
        contains('xmlns:tools="http://schemas.android.com/tools"'),
      );

      for (final permission in <String>[
        'android.permission.READ_EXTERNAL_STORAGE',
        'android.permission.READ_MEDIA_IMAGES',
        'android.permission.READ_MEDIA_VIDEO',
        'android.permission.READ_MEDIA_AUDIO',
      ]) {
        final declaration = RegExp(
          '<uses-permission\\s+[^>]*android:name="$permission"[^>]*/>',
          multiLine: true,
        ).firstMatch(manifest);
        expect(
          declaration,
          isNotNull,
          reason: '$permission removal is missing',
        );
        expect(
          declaration!.group(0),
          contains('tools:node="remove"'),
          reason: '$permission must be removed from the merged manifest',
        );
      }
    },
  );

  test('Android manifest configures notification permission and channel', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('android:name="android.permission.POST_NOTIFICATIONS"'),
    );
    final channelMetadata = RegExp(
      '<meta-data\\s+[^>]*android:name="com\\.google\\.firebase\\.messaging\\.default_notification_channel_id"[^>]*/>',
      multiLine: true,
    ).firstMatch(manifest);
    expect(channelMetadata, isNotNull);
    expect(
      channelMetadata!.group(0),
      contains('android:value="sabibom_general"'),
    );
  });
}
