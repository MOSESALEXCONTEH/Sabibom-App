import 'package:cloud_firestore/cloud_firestore.dart';

import '../../products/domain/product.dart';

/// Branch-owned stock state for a business-level product definition.
///
/// Product identity, name and pricing remain under
/// `businesses/{businessId}/products/{productId}`. Quantities and stock
/// summaries live under
/// `businesses/{businessId}/branches/{branchId}/inventory/{productId}`.
class BranchInventory {
  const BranchInventory({
    required this.businessId,
    required this.branchId,
    required this.productId,
    required this.quantity,
    required this.reservedQuantity,
    required this.lowStockThreshold,
    required this.averageUnitCostMinor,
    required this.stockCostValueMinor,
    required this.expectedStockRevenueMinor,
    required this.potentialProfitRemainingMinor,
    required this.realizedGrossProfitMinor,
    required this.expiringQuantity,
    required this.expiredQuantity,
    required this.unknownExpiryQuantity,
    required this.nextExpiryBatchQuantity,
    required this.expiryStatus,
    this.nextExpiryDate,
    this.nextExpiryBatchId,
    this.updatedAt,
  });

  factory BranchInventory.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return BranchInventory.fromMap(snapshot.data() ?? const {}, snapshot.id);
  }

  factory BranchInventory.fromMap(
    Map<String, dynamic> data,
    String fallbackProductId,
  ) {
    return BranchInventory(
      businessId: _string(data['businessId']) ?? '',
      branchId: _string(data['branchId']) ?? '',
      productId: _string(data['productId']) ?? fallbackProductId,
      quantity: _number(data['quantity']),
      reservedQuantity: _number(data['reservedQuantity']),
      lowStockThreshold: _number(data['lowStockThreshold']),
      averageUnitCostMinor:
          (data['averageUnitCostMinor'] as num?)?.round() ??
          (data['unitCostMinor'] as num?)?.round() ??
          0,
      stockCostValueMinor: (data['stockCostValueMinor'] as num?)?.round() ?? 0,
      expectedStockRevenueMinor:
          (data['expectedStockRevenueMinor'] as num?)?.round() ?? 0,
      potentialProfitRemainingMinor:
          (data['potentialProfitRemainingMinor'] as num?)?.round() ?? 0,
      realizedGrossProfitMinor:
          (data['realizedGrossProfitMinor'] as num?)?.round() ?? 0,
      expiringQuantity: _number(data['expiringQuantity']),
      expiredQuantity: _number(data['expiredQuantity']),
      unknownExpiryQuantity: _number(data['unknownExpiryQuantity']),
      nextExpiryBatchQuantity: _number(data['nextExpiryBatchQuantity']),
      nextExpiryDate: _date(data['nextExpiryDate']),
      nextExpiryBatchId: _string(data['nextExpiryBatchId']),
      expiryStatus: ProductExpiryStatus.fromStorage(data['expiryStatus']),
      updatedAt: _date(data['updatedAt']),
    );
  }

  final String businessId;
  final String branchId;
  final String productId;
  final double quantity;
  final double reservedQuantity;
  final double lowStockThreshold;
  final int averageUnitCostMinor;
  final int stockCostValueMinor;
  final int expectedStockRevenueMinor;
  final int potentialProfitRemainingMinor;
  final int realizedGrossProfitMinor;
  final double expiringQuantity;
  final double expiredQuantity;
  final double unknownExpiryQuantity;
  final double nextExpiryBatchQuantity;
  final DateTime? nextExpiryDate;
  final String? nextExpiryBatchId;
  final ProductExpiryStatus expiryStatus;
  final DateTime? updatedAt;

  double get availableQuantity =>
      (quantity - reservedQuantity).clamp(0, double.infinity).toDouble();

  double effectiveLowStockThreshold(double productThreshold) {
    if (lowStockThreshold > 0) return lowStockThreshold;
    return productThreshold < 0 ? 0 : productThreshold;
  }

  Map<String, Object?> toFirestoreMap() => <String, Object?>{
    'businessId': businessId,
    'branchId': branchId,
    'productId': productId,
    'quantity': quantity,
    'reservedQuantity': reservedQuantity,
    'availableQuantity': availableQuantity,
    'lowStockThreshold': lowStockThreshold,
    'averageUnitCostMinor': averageUnitCostMinor,
    'stockCostValueMinor': stockCostValueMinor,
    'expectedStockRevenueMinor': expectedStockRevenueMinor,
    'potentialProfitRemainingMinor': potentialProfitRemainingMinor,
    'realizedGrossProfitMinor': realizedGrossProfitMinor,
    'expiringQuantity': expiringQuantity,
    'expiredQuantity': expiredQuantity,
    'unknownExpiryQuantity': unknownExpiryQuantity,
    'nextExpiryBatchQuantity': nextExpiryBatchQuantity,
    'nextExpiryDate': nextExpiryDate == null
        ? null
        : Timestamp.fromDate(nextExpiryDate!),
    'nextExpiryBatchId': nextExpiryBatchId,
    'expiryStatus': expiryStatus.storedValue,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Creates an aggregate used only for authorised All Branches reads.
  /// It is never a writable inventory target.
  static BranchInventory aggregate({
    required String businessId,
    required String productId,
    required Iterable<BranchInventory> records,
    required int fallbackUnitCostMinor,
    required double fallbackLowStockThreshold,
  }) {
    final rows = records.toList(growable: false);
    if (rows.isEmpty) {
      return BranchInventory(
        businessId: businessId,
        branchId: '',
        productId: productId,
        quantity: 0,
        reservedQuantity: 0,
        lowStockThreshold: fallbackLowStockThreshold,
        averageUnitCostMinor: fallbackUnitCostMinor,
        stockCostValueMinor: 0,
        expectedStockRevenueMinor: 0,
        potentialProfitRemainingMinor: 0,
        realizedGrossProfitMinor: 0,
        expiringQuantity: 0,
        expiredQuantity: 0,
        unknownExpiryQuantity: 0,
        nextExpiryBatchQuantity: 0,
        expiryStatus: ProductExpiryStatus.notTracked,
      );
    }

    final quantity = rows.fold<double>(0, (sum, row) => sum + row.quantity);
    final reserved = rows.fold<double>(
      0,
      (sum, row) => sum + row.reservedQuantity,
    );
    final weightedCostNumerator = rows.fold<double>(
      0,
      (sum, row) => sum + row.quantity * row.averageUnitCostMinor,
    );
    final nearestExpiryRows =
        rows.where((row) => row.nextExpiryDate != null).toList(growable: false)
          ..sort(
            (left, right) =>
                left.nextExpiryDate!.compareTo(right.nextExpiryDate!),
          );
    final statuses = rows.map((row) => row.expiryStatus).toSet();

    return BranchInventory(
      businessId: businessId,
      branchId: '',
      productId: productId,
      quantity: quantity,
      reservedQuantity: reserved,
      lowStockThreshold: rows.fold<double>(
        0,
        (sum, row) => sum + row.lowStockThreshold,
      ),
      averageUnitCostMinor: quantity <= 0
          ? fallbackUnitCostMinor
          : (weightedCostNumerator / quantity).round(),
      stockCostValueMinor: rows.fold<int>(
        0,
        (sum, row) => sum + row.stockCostValueMinor,
      ),
      expectedStockRevenueMinor: rows.fold<int>(
        0,
        (sum, row) => sum + row.expectedStockRevenueMinor,
      ),
      potentialProfitRemainingMinor: rows.fold<int>(
        0,
        (sum, row) => sum + row.potentialProfitRemainingMinor,
      ),
      realizedGrossProfitMinor: rows.fold<int>(
        0,
        (sum, row) => sum + row.realizedGrossProfitMinor,
      ),
      expiringQuantity: rows.fold<double>(
        0,
        (sum, row) => sum + row.expiringQuantity,
      ),
      expiredQuantity: rows.fold<double>(
        0,
        (sum, row) => sum + row.expiredQuantity,
      ),
      unknownExpiryQuantity: rows.fold<double>(
        0,
        (sum, row) => sum + row.unknownExpiryQuantity,
      ),
      nextExpiryBatchQuantity: nearestExpiryRows.isEmpty
          ? 0
          : nearestExpiryRows.first.nextExpiryBatchQuantity,
      nextExpiryDate: nearestExpiryRows.isEmpty
          ? null
          : nearestExpiryRows.first.nextExpiryDate,
      nextExpiryBatchId: nearestExpiryRows.isEmpty
          ? null
          : nearestExpiryRows.first.nextExpiryBatchId,
      expiryStatus: statuses.length == 1
          ? statuses.first
          : ProductExpiryStatus.mixed,
      updatedAt: rows
          .map((row) => row.updatedAt)
          .whereType<DateTime>()
          .fold<DateTime?>(null, (latest, value) {
            if (latest == null || value.isAfter(latest)) return value;
            return latest;
          }),
    );
  }

  static double _number(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : 0;

  static String? _string(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
