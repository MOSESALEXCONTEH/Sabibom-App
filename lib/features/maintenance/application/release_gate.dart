import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/runtime_configuration_repository.dart';
import '../domain/runtime_configuration.dart';

class ReleaseGateDecision {
  const ReleaseGateDecision({
    required this.currentVersion,
    required this.release,
    required this.updateRequired,
  });

  final String currentVersion;
  final RuntimeAndroidRelease release;
  final bool updateRequired;
}

List<int> _versionParts(String value) {
  final clean = value.trim().split('-').first;
  return clean.split('.').map((part) => int.tryParse(part) ?? 0).toList();
}

bool isVersionOlder(String current, String minimum) {
  final left = _versionParts(current);
  final right = _versionParts(minimum);
  final count = left.length > right.length ? left.length : right.length;
  for (var index = 0; index < count; index += 1) {
    final currentPart = index < left.length ? left[index] : 0;
    final minimumPart = index < right.length ? right[index] : 0;
    if (currentPart != minimumPart) return currentPart < minimumPart;
  }
  return false;
}

final releaseGateProvider = FutureProvider<ReleaseGateDecision?>((ref) async {
  final runtime = ref.watch(runtimeConfigurationProvider).asData?.value;
  if (runtime == null) return null;
  final package = await PackageInfo.fromPlatform();
  final minimum = runtime.androidRelease.minimumSupportedVersion?.trim();
  return ReleaseGateDecision(
    currentVersion: package.version,
    release: runtime.androidRelease,
    updateRequired:
        minimum != null &&
        minimum.isNotEmpty &&
        isVersionOlder(package.version, minimum),
  );
});
