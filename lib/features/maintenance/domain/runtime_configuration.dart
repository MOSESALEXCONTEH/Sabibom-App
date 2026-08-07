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

class RuntimeAndroidRelease {
  const RuntimeAndroidRelease({
    this.latestVersion,
    this.minimumSupportedVersion,
    this.storeUrl,
    this.releaseNotes,
  });

  final String? latestVersion;
  final String? minimumSupportedVersion;
  final String? storeUrl;
  final String? releaseNotes;

  factory RuntimeAndroidRelease.fromMap(Map<String, dynamic> data) =>
      RuntimeAndroidRelease(
        latestVersion: data['latestVersion'] as String?,
        minimumSupportedVersion: data['minimumSupportedVersion'] as String?,
        storeUrl: data['storeUrl'] as String?,
        releaseNotes: data['releaseNotes'] as String?,
      );
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
