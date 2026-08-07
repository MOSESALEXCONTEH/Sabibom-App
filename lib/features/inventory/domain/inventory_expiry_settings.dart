enum ExpiredStockSalePolicy {
  block,
  warn;

  static ExpiredStockSalePolicy fromStorage(Object? value) {
    return '$value'.trim().toLowerCase() == warn.name ? warn : block;
  }
}

class InventoryExpirySettings {
  const InventoryExpirySettings({
    this.enabled = true,
    this.defaultReminderDays = defaultDays,
    this.notifyOwners = true,
    this.notifyManagers = true,
    this.notifyStockKeepers = true,
    this.pushEnabled = true,
    this.inAppEnabled = true,
    this.expiredStockSalePolicy = ExpiredStockSalePolicy.block,
    this.updatedBy,
  });

  static const List<int> defaultDays = <int>[30, 14, 7, 3, 1, 0];
  static const int maximumReminderDays = 365;

  factory InventoryExpirySettings.fromMap(Map<String, dynamic> data) {
    final rawDays = data['defaultReminderDays'];
    final days = rawDays is Iterable
        ? rawDays.whereType<num>().map((day) => day.round()).toList()
        : defaultDays;
    return InventoryExpirySettings(
      enabled: data['enabled'] as bool? ?? true,
      defaultReminderDays: normalizeReminderDays(days),
      notifyOwners: data['notifyOwners'] as bool? ?? true,
      notifyManagers: data['notifyManagers'] as bool? ?? true,
      notifyStockKeepers: data['notifyStockKeepers'] as bool? ?? true,
      pushEnabled: data['pushEnabled'] as bool? ?? true,
      inAppEnabled: data['inAppEnabled'] as bool? ?? true,
      expiredStockSalePolicy: ExpiredStockSalePolicy.fromStorage(
        data['expiredStockSalePolicy'],
      ),
      updatedBy: data['updatedBy'] as String?,
    );
  }

  final bool enabled;
  final List<int> defaultReminderDays;
  final bool notifyOwners;
  final bool notifyManagers;
  final bool notifyStockKeepers;
  final bool pushEnabled;
  final bool inAppEnabled;
  final ExpiredStockSalePolicy expiredStockSalePolicy;
  final String? updatedBy;

  static List<int> normalizeReminderDays(Iterable<int> values) {
    final days =
        values
            .where((day) => day >= 0 && day <= maximumReminderDays)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    return List<int>.unmodifiable(days.isEmpty ? defaultDays : days);
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'enabled': enabled,
    'defaultReminderDays': defaultReminderDays,
    'notifyOwners': notifyOwners,
    'notifyManagers': notifyManagers,
    'notifyStockKeepers': notifyStockKeepers,
    'pushEnabled': pushEnabled,
    'inAppEnabled': inAppEnabled,
    'expiredStockSalePolicy': expiredStockSalePolicy.name,
    'updatedBy': updatedBy,
  };
}
