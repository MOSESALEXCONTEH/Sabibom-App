/// Stable deduplication keys for product-expiry notification cycles.
abstract final class ExpiryNotificationKeys {
  static String approaching({
    required String businessId,
    required String batchId,
    required int reminderDay,
    required String userId,
  }) =>
      'product_expiry_approaching_${businessId}_${batchId}_${reminderDay}_$userId';

  static String expiresToday({
    required String businessId,
    required String batchId,
    required String userId,
  }) =>
      'product_expires_today_${businessId}_${batchId}_$userId';

  static String expired({
    required String businessId,
    required String batchId,
    required String userId,
  }) =>
      'product_expired_${businessId}_${batchId}_$userId';

  static String unknownExpiry({
    required String businessId,
    required String batchId,
    required String userId,
  }) =>
      'product_expiry_unknown_${businessId}_${batchId}_$userId';

  static String disposed({
    required String businessId,
    required String movementId,
    required String userId,
  }) =>
      'expired_stock_disposed_${businessId}_${movementId}_$userId';

  /// Event key without recipient suffix — used when resolving a batch cycle.
  static String batchCyclePrefix({
    required String businessId,
    required String batchId,
  }) =>
      'product_expiry_${businessId}_$batchId';
}
