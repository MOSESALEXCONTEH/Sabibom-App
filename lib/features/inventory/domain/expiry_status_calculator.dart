import 'package:timezone/timezone.dart' as tz;

import '../../products/domain/product.dart';
import 'inventory_batch.dart';

class BatchExpiryState {
  const BatchExpiryState({
    required this.batch,
    required this.status,
    this.daysRemaining,
  });

  final InventoryBatch batch;
  final ProductExpiryStatus status;
  final int? daysRemaining;
}

class ProductExpirySummary {
  const ProductExpirySummary({
    required this.status,
    required this.expiringQuantity,
    required this.expiredQuantity,
    required this.unknownExpiryQuantity,
    this.nextExpiryDate,
    this.nextExpiryBatchId,
    this.nextExpiryBatchQuantity = 0,
  });

  const ProductExpirySummary.notTracked()
    : status = ProductExpiryStatus.notTracked,
      expiringQuantity = 0,
      expiredQuantity = 0,
      unknownExpiryQuantity = 0,
      nextExpiryDate = null,
      nextExpiryBatchId = null,
      nextExpiryBatchQuantity = 0;

  final ProductExpiryStatus status;
  final DateTime? nextExpiryDate;
  final String? nextExpiryBatchId;
  final double nextExpiryBatchQuantity;
  final double expiringQuantity;
  final double expiredQuantity;
  final double unknownExpiryQuantity;
}

abstract final class ExpiryStatusCalculator {
  static int daysRemaining({
    required DateTime expiryDate,
    required DateTime now,
    required String businessTimezone,
  }) {
    final location = _location(businessTimezone);
    final localNow = tz.TZDateTime.from(now, location);
    final today = tz.TZDateTime(
      location,
      localNow.year,
      localNow.month,
      localNow.day,
    );
    // Expiry is a calendar date. Preserve its date components instead of
    // shifting a midnight timestamp into a neighbouring timezone.
    final expiry = tz.TZDateTime(
      location,
      expiryDate.year,
      expiryDate.month,
      expiryDate.day,
    );
    return expiry.difference(today).inDays;
  }

  static ProductExpiryStatus statusForDate({
    required DateTime expiryDate,
    required DateTime now,
    required String businessTimezone,
    int reminderThresholdDays = 30,
  }) {
    final remaining = daysRemaining(
      expiryDate: expiryDate,
      now: now,
      businessTimezone: businessTimezone,
    );
    if (remaining < 0) return ProductExpiryStatus.expired;
    if (remaining == 0) return ProductExpiryStatus.expiresToday;
    if (remaining <= reminderThresholdDays) {
      return ProductExpiryStatus.expiringSoon;
    }
    return ProductExpiryStatus.safe;
  }

  static ProductExpirySummary summarize({
    required bool tracksExpiry,
    required Iterable<InventoryBatch> batches,
    required DateTime now,
    required String businessTimezone,
    int reminderThresholdDays = 30,
  }) {
    if (!tracksExpiry) return const ProductExpirySummary.notTracked();

    final relevant = batches
        .where((batch) => batch.quantityRemaining > 0)
        .where(
          (batch) =>
              batch.status != InventoryBatchStatus.depleted &&
              batch.status != InventoryBatchStatus.voided,
        )
        .toList();
    final known = <BatchExpiryState>[];
    var unknownQuantity = 0.0;
    for (final batch in relevant) {
      final expiryDate = batch.expiryDate;
      if (!batch.expiryDateKnown || expiryDate == null) {
        unknownQuantity += batch.quantityRemaining;
        continue;
      }
      known.add(
        BatchExpiryState(
          batch: batch,
          status: statusForDate(
            expiryDate: expiryDate,
            now: now,
            businessTimezone: businessTimezone,
            reminderThresholdDays: reminderThresholdDays,
          ),
          daysRemaining: daysRemaining(
            expiryDate: expiryDate,
            now: now,
            businessTimezone: businessTimezone,
          ),
        ),
      );
    }
    known.sort(
      (left, right) =>
          left.batch.expiryDate!.compareTo(right.batch.expiryDate!),
    );

    var expiringQuantity = 0.0;
    var expiredQuantity = 0.0;
    final statuses = <ProductExpiryStatus>{};
    for (final state in known) {
      statuses.add(state.status);
      switch (state.status) {
        case ProductExpiryStatus.expiringSoon:
        case ProductExpiryStatus.expiresToday:
          expiringQuantity += state.batch.quantityRemaining;
        case ProductExpiryStatus.expired:
          expiredQuantity += state.batch.quantityRemaining;
        case ProductExpiryStatus.notTracked:
        case ProductExpiryStatus.safe:
        case ProductExpiryStatus.mixed:
          break;
      }
    }

    final status = statuses.length > 1
        ? ProductExpiryStatus.mixed
        : statuses.singleOrNull ?? ProductExpiryStatus.safe;
    final next = known.firstOrNull;
    return ProductExpirySummary(
      status: status,
      nextExpiryDate: next?.batch.expiryDate,
      nextExpiryBatchId: next?.batch.id,
      nextExpiryBatchQuantity: next?.batch.quantityRemaining ?? 0,
      expiringQuantity: expiringQuantity,
      expiredQuantity: expiredQuantity,
      unknownExpiryQuantity: unknownQuantity,
    );
  }

  static tz.Location _location(String name) {
    final requested = name.trim();
    final canonical = switch (requested) {
      // The timezone package omits this historical IANA link. Sierra Leone
      // follows GMT year-round, matching Africa/Abidjan.
      'Africa/Freetown' => 'Africa/Abidjan',
      _ => requested,
    };
    try {
      return tz.getLocation(canonical);
    } on ArgumentError {
      return tz.UTC;
    }
  }
}
