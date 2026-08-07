import 'package:cloud_firestore/cloud_firestore.dart';

enum InventoryAdjustmentType {
  stockIn,
  stockOut,
  correction,
  damaged,
  expired,
  returned,
  openingBalance;

  String get label => switch (this) {
    InventoryAdjustmentType.stockIn => 'Stock In',
    InventoryAdjustmentType.stockOut => 'Stock Out',
    InventoryAdjustmentType.correction => 'Correction',
    InventoryAdjustmentType.damaged => 'Damaged',
    InventoryAdjustmentType.expired => 'Expired',
    InventoryAdjustmentType.returned => 'Returned',
    InventoryAdjustmentType.openingBalance => 'Opening Balance',
  };

  String get storedValue => switch (this) {
    InventoryAdjustmentType.stockIn => 'stock_in',
    InventoryAdjustmentType.stockOut => 'stock_out',
    InventoryAdjustmentType.correction => 'correction',
    InventoryAdjustmentType.damaged => 'damaged',
    InventoryAdjustmentType.expired => 'expired',
    InventoryAdjustmentType.returned => 'returned',
    InventoryAdjustmentType.openingBalance => 'opening_balance',
  };

  static InventoryAdjustmentType fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return InventoryAdjustmentType.values.firstWhere(
      (type) => type.storedValue == raw || type.name == raw,
      orElse: () => InventoryAdjustmentType.correction,
    );
  }

  /// Positive deltas increase stock; negative deltas decrease stock.
  double signedQuantity(double quantity) {
    final abs = quantity.abs();
    return switch (this) {
      InventoryAdjustmentType.stockIn ||
      InventoryAdjustmentType.returned ||
      InventoryAdjustmentType.openingBalance => abs,
      InventoryAdjustmentType.stockOut ||
      InventoryAdjustmentType.damaged ||
      InventoryAdjustmentType.expired => -abs,
      InventoryAdjustmentType.correction => quantity,
    };
  }
}

class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.type,
    required this.quantityChange,
    required this.stockBefore,
    required this.stockAfter,
    required this.referenceType,
    this.reason,
    this.note,
    this.referenceId,
    this.createdBy,
    this.createdAt,
  });

  factory InventoryMovement.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return InventoryMovement(
      id: snapshot.id,
      productId: data['productId'] as String? ?? '',
      productName: data['productName'] as String? ?? '',
      type: InventoryAdjustmentType.fromStorage(data['type']),
      quantityChange: (data['quantityChange'] as num?)?.toDouble() ?? 0,
      stockBefore: (data['stockBefore'] as num?)?.toDouble() ?? 0,
      stockAfter: (data['stockAfter'] as num?)?.toDouble() ?? 0,
      reason: data['reason'] as String?,
      note: data['note'] as String?,
      referenceType: data['referenceType'] as String? ?? 'manual_adjustment',
      referenceId: data['referenceId'] as String?,
      createdBy: data['createdBy'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String productId;
  final String productName;
  final InventoryAdjustmentType type;
  final double quantityChange;
  final double stockBefore;
  final double stockAfter;
  final String? reason;
  final String? note;
  final String referenceType;
  final String? referenceId;
  final String? createdBy;
  final DateTime? createdAt;
}
