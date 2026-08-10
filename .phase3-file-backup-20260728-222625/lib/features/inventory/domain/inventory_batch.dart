import 'package:cloud_firestore/cloud_firestore.dart';

enum InventoryBatchSourceType {
  initialStock('initial_stock'),
  purchase('purchase'),
  manualStockIn('manual_stock_in'),
  returnToStock('return_to_stock'),
  import('import'),
  legacyMigration('legacy_migration');

  const InventoryBatchSourceType(this.storedValue);

  final String storedValue;

  static InventoryBatchSourceType fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return InventoryBatchSourceType.values.firstWhere(
      (type) => type.storedValue == raw || type.name == raw,
      orElse: () => InventoryBatchSourceType.import,
    );
  }
}

enum InventoryBatchStatus {
  active,
  depleted,
  expired,
  voided;

  static InventoryBatchStatus fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return InventoryBatchStatus.values.firstWhere(
      (status) => status.name == raw,
      orElse: () => InventoryBatchStatus.active,
    );
  }
}

class InventoryBatch {
  const InventoryBatch({
    required this.id,
    required this.businessId,
    required this.productId,
    required this.productName,
    required this.sourceType,
    required this.quantityReceived,
    required this.quantityRemaining,
    required this.unitCostMinor,
    required this.sellingPriceAtReceiptMinor,
    required this.expiryDateKnown,
    required this.receivedAt,
    required this.status,
    this.sku,
    this.sourceId,
    this.sourceNumber,
    this.expiryDate,
    this.createdBy,
    this.createdByName,
    this.createdAt,
    this.updatedAt,
    this.depletedAt,
  });

  factory InventoryBatch.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return InventoryBatch.fromMap(
      snapshot.id,
      snapshot.data() ?? const <String, dynamic>{},
    );
  }

  factory InventoryBatch.fromMap(String id, Map<String, dynamic> data) {
    final expiryDate = _date(data['expiryDate']);
    return InventoryBatch(
      id: id,
      businessId: data['businessId'] as String? ?? '',
      productId: data['productId'] as String? ?? '',
      productName: data['productName'] as String? ?? 'Unnamed product',
      sku: data['sku'] as String?,
      sourceType: InventoryBatchSourceType.fromStorage(data['sourceType']),
      sourceId: data['sourceId'] as String?,
      sourceNumber: data['sourceNumber'] as String?,
      quantityReceived: (data['quantityReceived'] as num?)?.toDouble() ?? 0,
      quantityRemaining: (data['quantityRemaining'] as num?)?.toDouble() ?? 0,
      unitCostMinor: (data['unitCostMinor'] as num?)?.round() ?? 0,
      sellingPriceAtReceiptMinor:
          (data['sellingPriceAtReceiptMinor'] as num?)?.round() ?? 0,
      expiryDate: expiryDate,
      expiryDateKnown: data['expiryDateKnown'] as bool? ?? expiryDate != null,
      receivedAt:
          _date(data['receivedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      status: InventoryBatchStatus.fromStorage(data['status']),
      createdBy: data['createdBy'] as String?,
      createdByName: data['createdByName'] as String?,
      createdAt: _date(data['createdAt']),
      updatedAt: _date(data['updatedAt']),
      depletedAt: _date(data['depletedAt']),
    );
  }

  final String id;
  final String businessId;
  final String productId;
  final String productName;
  final String? sku;
  final InventoryBatchSourceType sourceType;
  final String? sourceId;
  final String? sourceNumber;
  final double quantityReceived;
  final double quantityRemaining;
  final int unitCostMinor;
  final int sellingPriceAtReceiptMinor;
  final DateTime? expiryDate;
  final bool expiryDateKnown;
  final DateTime receivedAt;
  final InventoryBatchStatus status;
  final String? createdBy;
  final String? createdByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? depletedAt;

  bool get hasRemainingStock => quantityRemaining > 0;
  bool get isActive =>
      status == InventoryBatchStatus.active && hasRemainingStock;
  bool get hasKnownExpiry => expiryDateKnown && expiryDate != null;

  Map<String, Object?> toFirestoreMap() => <String, Object?>{
    'businessId': businessId,
    'productId': productId,
    'productName': productName.trim(),
    'sku': sku,
    'sourceType': sourceType.storedValue,
    'sourceId': sourceId,
    'sourceNumber': sourceNumber,
    'quantityReceived': quantityReceived,
    'quantityRemaining': quantityRemaining,
    'unitCostMinor': unitCostMinor,
    'sellingPriceAtReceiptMinor': sellingPriceAtReceiptMinor,
    'expiryDate': expiryDate == null ? null : Timestamp.fromDate(expiryDate!),
    'expiryDateKnown': expiryDateKnown && expiryDate != null,
    'receivedAt': Timestamp.fromDate(receivedAt),
    'status': status.name,
    'createdBy': createdBy,
    'createdByName': createdByName,
    'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
    'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
    'depletedAt': depletedAt == null ? null : Timestamp.fromDate(depletedAt!),
  };

  static DateTime? _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

class BatchAllocation {
  const BatchAllocation({
    required this.batchId,
    required this.quantity,
    required this.unitCostMinor,
    required this.lineCostMinor,
    this.expiryDate,
  });

  factory BatchAllocation.fromMap(Map<String, dynamic> data) {
    return BatchAllocation(
      batchId: data['batchId'] as String? ?? '',
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
      unitCostMinor: (data['unitCostMinor'] as num?)?.round() ?? 0,
      expiryDate: InventoryBatch._date(data['expiryDate']),
      lineCostMinor: (data['lineCostMinor'] as num?)?.round() ?? 0,
    );
  }

  final String batchId;
  final double quantity;
  final int unitCostMinor;
  final DateTime? expiryDate;
  final int lineCostMinor;

  Map<String, Object?> toMap() => <String, Object?>{
    'batchId': batchId,
    'quantity': quantity,
    'unitCostMinor': unitCostMinor,
    'expiryDate': expiryDate == null ? null : Timestamp.fromDate(expiryDate!),
    'lineCostMinor': lineCostMinor,
  };
}
