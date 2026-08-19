abstract final class BillingEntitlementKeys {
  static const branchesMax = 'branches.max';
  static const staffMax = 'staff.max';
  static const reportsHistoryDays = 'reports.history_days';
  static const reportsAdvanced = 'reports.advanced';
  static const reportsExport = 'reports.export';
  static const sabiDailyRequests = 'sabi.daily_requests';
  static const messagingBulk = 'messaging.bulk';
  static const approvalsEnabled = 'approvals.enabled';
  static const backupEnabled = 'backup.enabled';
  static const adsEnabled = 'ads.enabled';

  static const all = <String>{
    branchesMax,
    staffMax,
    reportsHistoryDays,
    reportsAdvanced,
    reportsExport,
    sabiDailyRequests,
    messagingBulk,
    approvalsEnabled,
    backupEnabled,
    adsEnabled,
  };
}

enum BillingTier { free, pro, complimentary }

class BusinessEntitlements {
  const BusinessEntitlements._(this.tier, this._values);

  factory BusinessEntitlements.fromMap({
    required BillingTier tier,
    required Map<String, dynamic> values,
  }) {
    final defaults = BusinessEntitlements.forTier(tier);
    final normalized = Map<String, Object>.from(defaults._values);

    for (final entry in values.entries) {
      if (!BillingEntitlementKeys.all.contains(entry.key)) continue;
      final value = entry.value;
      if (value is bool || value is int) {
        normalized[entry.key] = value as Object;
      } else if (value is num) {
        normalized[entry.key] = value.toInt();
      }
    }

    return BusinessEntitlements._(tier, Map.unmodifiable(normalized));
  }

  factory BusinessEntitlements.forTier(BillingTier tier) {
    return BusinessEntitlements._(
      tier,
      Map.unmodifiable(switch (tier) {
        BillingTier.free => _freeValues,
        BillingTier.pro || BillingTier.complimentary => _proValues,
      }),
    );
  }

  factory BusinessEntitlements.globalFreeAccess() {
    return BusinessEntitlements._(
      BillingTier.free,
      Map.unmodifiable(<String, Object>{
        ..._proValues,
        BillingEntitlementKeys.adsEnabled: true,
      }),
    );
  }

  static const unlimited = -1;

  static const _freeValues = <String, Object>{
    BillingEntitlementKeys.branchesMax: 1,
    BillingEntitlementKeys.staffMax: 2,
    BillingEntitlementKeys.reportsHistoryDays: 30,
    BillingEntitlementKeys.reportsAdvanced: false,
    BillingEntitlementKeys.reportsExport: false,
    BillingEntitlementKeys.sabiDailyRequests: 10,
    BillingEntitlementKeys.messagingBulk: false,
    BillingEntitlementKeys.approvalsEnabled: false,
    BillingEntitlementKeys.backupEnabled: false,
    BillingEntitlementKeys.adsEnabled: true,
  };

  static const _proValues = <String, Object>{
    BillingEntitlementKeys.branchesMax: unlimited,
    BillingEntitlementKeys.staffMax: unlimited,
    BillingEntitlementKeys.reportsHistoryDays: unlimited,
    BillingEntitlementKeys.reportsAdvanced: true,
    BillingEntitlementKeys.reportsExport: true,
    BillingEntitlementKeys.sabiDailyRequests: unlimited,
    BillingEntitlementKeys.messagingBulk: true,
    BillingEntitlementKeys.approvalsEnabled: true,
    BillingEntitlementKeys.backupEnabled: true,
    BillingEntitlementKeys.adsEnabled: false,
  };

  final BillingTier tier;
  final Map<String, Object> _values;

  bool isEnabled(String key) => _values[key] == true;

  int limit(String key) {
    final value = _values[key];
    return value is int ? value : 0;
  }

  bool isUnlimited(String key) => limit(key) == unlimited;

  Map<String, Object> toMap() => Map.unmodifiable(_values);
}
