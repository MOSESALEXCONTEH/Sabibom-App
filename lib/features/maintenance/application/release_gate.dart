import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/runtime_configuration_repository.dart';
import '../domain/runtime_configuration.dart';

class ReleaseGateDecision {
  const ReleaseGateDecision({
    required this.currentVersion,
    required this.currentBuildNumber,
    required this.release,
    required this.updateRequired,
  });

  final String currentVersion;
  final String currentBuildNumber;
  final RuntimeAndroidRelease release;
  final bool updateRequired;

  RuntimeAndroidUpdatePolicy get policy => release.updatePolicy;
}

final _decimalBuild = RegExp(r'^(0|[1-9]\d*)$');

bool isCanonicalBuildNumber(String? value) =>
    value != null && _decimalBuild.hasMatch(value);

bool isBuildNumberOlder(String current, String minimum) {
  if (!isCanonicalBuildNumber(current) || !isCanonicalBuildNumber(minimum)) {
    return false;
  }
  return BigInt.parse(current) < BigInt.parse(minimum);
}

bool shouldRequireAndroidUpdate({
  required String installedBuildNumber,
  required RuntimeAndroidUpdatePolicy policy,
  DateTime? now,
}) {
  final checkedAt = (now ?? DateTime.now()).toUtc();
  final latest = policy.latestBuildNumber;
  final minimum = policy.minimumBuildNumber;
  if (policy.schemaVersion != 2 ||
      !policy.enabled ||
      !policy.effectiveEnabled ||
      policy.environment != 'production' ||
      policy.packageId != RuntimeAndroidUpdatePolicy.expectedPackageId ||
      policy.storeUrl != RuntimeAndroidUpdatePolicy.canonicalPlayUrl ||
      !isCanonicalBuildNumber(installedBuildNumber) ||
      !isCanonicalBuildNumber(latest) ||
      !isCanonicalBuildNumber(minimum) ||
      policy.expiresAt == null ||
      policy.expiresAt!.isBefore(checkedAt) ||
      policy.expiresAt!.isAtSameMomentAs(checkedAt) ||
      (policy.effectiveAt?.isAfter(checkedAt) ?? false)) {
    return false;
  }
  if (BigInt.parse(minimum!) > BigInt.parse(latest!)) return false;
  return isBuildNumberOlder(installedBuildNumber, minimum);
}

ReleaseGateDecision decideReleaseGate({
  required PackageInfo packageInfo,
  required RuntimeAndroidRelease release,
  DateTime? now,
}) => ReleaseGateDecision(
  currentVersion: packageInfo.version,
  currentBuildNumber: packageInfo.buildNumber,
  release: release,
  updateRequired: shouldRequireAndroidUpdate(
    installedBuildNumber: packageInfo.buildNumber,
    policy: release.updatePolicy,
    now: now,
  ),
);

// Kept for non-enforcement display/tests that still compare release names.
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

final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

final releaseGateProvider = FutureProvider<ReleaseGateDecision?>((ref) async {
  final runtime = ref.watch(runtimeConfigurationProvider).asData?.value;
  if (runtime == null) return null;
  final package = await ref.watch(packageInfoProvider.future);
  return decideReleaseGate(
    packageInfo: package,
    release: runtime.androidRelease,
  );
});
