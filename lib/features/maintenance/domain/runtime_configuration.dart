class RuntimeMaintenanceConfiguration {
  const RuntimeMaintenanceConfiguration({
    required this.enabled,
    required this.effectiveEnabled,
    required this.scope,
    required this.message,
    this.startsAt,
    this.endsAt,
  });

  final bool enabled;
  final bool effectiveEnabled;
  final String scope;
  final String message;
  final DateTime? startsAt;
  final DateTime? endsAt;

  bool get blocksMobile =>
      effectiveEnabled && (scope == 'all' || scope == 'mobile');

  factory RuntimeMaintenanceConfiguration.fromMap(Map<String, dynamic> data) {
    DateTime? parseDate(Object? value) {
      if (value is! String || value.isEmpty) return null;
      return DateTime.tryParse(value)?.toLocal();
    }

    return RuntimeMaintenanceConfiguration(
      enabled: data['enabled'] == true,
      effectiveEnabled: data['effectiveEnabled'] == true,
      scope: data['scope'] as String? ?? 'all',
      message: (data['message'] as String?)?.trim().isNotEmpty == true
          ? (data['message'] as String).trim()
          : 'SabiBom is temporarily unavailable for maintenance.',
      startsAt: parseDate(data['startsAt']),
      endsAt: parseDate(data['endsAt']),
    );
  }
}

class RuntimeAndroidUpdatePolicy {
  const RuntimeAndroidUpdatePolicy({
    this.schemaVersion,
    this.enabled = false,
    this.effectiveEnabled = false,
    this.environment,
    this.packageId,
    this.latestBuildNumber,
    this.minimumBuildNumber,
    this.displayVersion,
    this.storeUrl,
    this.title = 'Update SabiBom',
    this.message = 'A newer version of SabiBom is required to continue.',
    this.effectiveAt,
    this.expiresAt,
    this.updatedAt,
    this.revision = 0,
  });

  static const expectedPackageId = 'com.sabibom.app';
  static const canonicalPlayUrl =
      'https://play.google.com/store/apps/details?id=com.sabibom.app';

  final int? schemaVersion;
  final bool enabled;
  final bool effectiveEnabled;
  final String? environment;
  final String? packageId;
  final String? latestBuildNumber;
  final String? minimumBuildNumber;
  final String? displayVersion;
  final String? storeUrl;
  final String title;
  final String message;
  final DateTime? effectiveAt;
  final DateTime? expiresAt;
  final DateTime? updatedAt;
  final int revision;

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  factory RuntimeAndroidUpdatePolicy.fromMap(Map<String, dynamic> data) {
    String? stringValue(String key) {
      final value = data[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    return RuntimeAndroidUpdatePolicy(
      schemaVersion: (data['schemaVersion'] as num?)?.toInt(),
      enabled: data['enabled'] == true,
      effectiveEnabled: data['effectiveEnabled'] == true,
      environment: stringValue('environment'),
      packageId: stringValue('packageId'),
      latestBuildNumber: stringValue('latestBuildNumber'),
      minimumBuildNumber: stringValue('minimumBuildNumber'),
      displayVersion: stringValue('displayVersion'),
      storeUrl: stringValue('storeUrl'),
      title: stringValue('title') ?? 'Update SabiBom',
      message:
          stringValue('message') ??
          'A newer version of SabiBom is required to continue.',
      effectiveAt: _parseDate(data['effectiveAt']),
      expiresAt: _parseDate(data['expiresAt']),
      updatedAt: _parseDate(data['updatedAt']),
      revision: (data['revision'] as num?)?.toInt() ?? 0,
    );
  }
}

class RuntimeAndroidRelease {
  const RuntimeAndroidRelease({
    this.latestVersion,
    this.minimumSupportedVersion,
    this.storeUrl,
    this.releaseNotes,
    this.updatePolicy = const RuntimeAndroidUpdatePolicy(),
  });

  final String? latestVersion;
  final String? minimumSupportedVersion;
  final String? storeUrl;
  final String? releaseNotes;
  final RuntimeAndroidUpdatePolicy updatePolicy;

  factory RuntimeAndroidRelease.fromMap(Map<String, dynamic> data) {
    final policy = data['updatePolicy'];
    return RuntimeAndroidRelease(
      latestVersion: data['latestVersion'] as String?,
      minimumSupportedVersion: data['minimumSupportedVersion'] as String?,
      storeUrl: data['storeUrl'] as String?,
      releaseNotes: data['releaseNotes'] as String?,
      updatePolicy: RuntimeAndroidUpdatePolicy.fromMap(
        policy is Map ? Map<String, dynamic>.from(policy) : const {},
      ),
    );
  }
}

class RuntimeConfiguration {
  const RuntimeConfiguration({
    required this.maintenance,
    this.androidRelease = const RuntimeAndroidRelease(),
  });

  final RuntimeMaintenanceConfiguration maintenance;
  final RuntimeAndroidRelease androidRelease;

  factory RuntimeConfiguration.fromMap(Map<String, dynamic> data) {
    final raw = data['maintenance'];
    final release = data['release'];
    final android = release is Map ? release['android'] : null;
    return RuntimeConfiguration(
      maintenance: RuntimeMaintenanceConfiguration.fromMap(
        raw is Map ? Map<String, dynamic>.from(raw) : const {},
      ),
      androidRelease: RuntimeAndroidRelease.fromMap(
        android is Map ? Map<String, dynamic>.from(android) : const {},
      ),
    );
  }
}
