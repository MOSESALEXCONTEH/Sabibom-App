import 'package:cloud_firestore/cloud_firestore.dart';

import '../../sales/domain/sale_models.dart';

enum PurchaseStatus { draft, completed, returned, voided }

enum PurchasePaymentStatus { paid, partiallyPaid, unpaid }

class PurchaseItem {
  const PurchaseItem({
    required this.purchaseItemId,
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitCostMinor,
    required this.trackStock,
    this.sku,
    this.unit = 'unit',
    this.discountType,
    this.discountValue = 0,
    this.tracksExpiry = false,
    this.expiryDate,
    this.expiryDateKnown = false,
    this.inventoryBatchId,
  });

  final String purchaseItemId;
  final String productId;
  final String name;
  final String? sku;
  final String unit;
  final double quantity;
  final int unitCostMinor;
  final bool trackStock;
  final DiscountType? discountType;
  final double discountValue;
  final bool tracksExpiry;
  final DateTime? expiryDate;
  final bool expiryDateKnown;
  final String? inventoryBatchId;

  factory PurchaseItem.fromMap(Map<String, dynamic> data) => PurchaseItem(
    purchaseItemId: data['purchaseItemId'] as String? ?? '',
    productId: data['productId'] as String? ?? '',
    name: data['name'] as String? ?? 'Unnamed product',
    sku: data['sku'] as String?,
    unit: data['unit'] as String? ?? 'unit',
    quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
    unitCostMinor: (data['unitCostMinor'] as num?)?.round() ?? 0,
    trackStock: data['trackStock'] as bool? ?? true,
    discountType: DiscountType.values
        .where((type) => type.name == data['discountType'])
        .firstOrNull,
    discountValue: (data['discountValue'] as num?)?.toDouble() ?? 0,
    tracksExpiry: data['tracksExpiry'] as bool? ?? false,
    expiryDate: switch (data['expiryDate']) {
      Timestamp value => value.toDate(),
      String value => DateTime.tryParse(value),
      _ => null,
    },
    expiryDateKnown: data['expiryDateKnown'] as bool? ?? false,
    inventoryBatchId: data['inventoryBatchId'] as String?,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    'purchaseItemId': purchaseItemId,
    'productId': productId,
    'name': name,
    'sku': sku,
    'unit': unit,
    'quantity': quantity,
    'unitCostMinor': unitCostMinor,
    'trackStock': trackStock,
    'discountType': discountType?.name,
    'discountValue': discountValue,
    'tracksExpiry': tracksExpiry,
    'expiryDate': expiryDate?.toIso8601String(),
    'expiryDateKnown': expiryDateKnown && expiryDate != null,
    'inventoryBatchId': inventoryBatchId,
  };
}

class Purchase {
  const Purchase({
    required this.purchaseId,
    required this.businessId,
    this.branchId,
    this.branchNameSnapshot,
    this.branchCodeSnapshot,
    required this.purchaseNumber,
    required this.supplierId,
    required this.supplierName,
    required this.items,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.deliveryMinor,
    required this.totalMinor,
    required this.amountPaidMinor,
    required this.balanceDueMinor,
    required this.status,
    required this.paymentStatus,
    this.paymentMethod,
    this.createdAt,
  });

  final String purchaseId;
  final String businessId;
  final String? branchId;
  final String? branchNameSnapshot;
  final String? branchCodeSnapshot;
  final String purchaseNumber;
  final String supplierId;
  final String supplierName;
  final List<PurchaseItem> items;
  final int subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int deliveryMinor;
  final int totalMinor;
  final int amountPaidMinor;
  final int balanceDueMinor;
  final PurchaseStatus status;
  final PurchasePaymentStatus paymentStatus;
  final String? paymentMethod;
  final DateTime? createdAt;

  factory Purchase.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Purchase.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});
  }

  factory Purchase.fromMap(String id, Map<String, dynamic> data) {
    final items = (data['items'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => PurchaseItem.fromMap(Map<String, dynamic>.from(item)))
        .toList();
    return Purchase(
      purchaseId: id,
      businessId: data['businessId'] as String? ?? '',
      branchId: (data['branchId'] as String?)?.trim(),
      branchNameSnapshot: (data['branchNameSnapshot'] as String?)?.trim(),
      branchCodeSnapshot: (data['branchCodeSnapshot'] as String?)?.trim(),
      purchaseNumber: data['purchaseNumber'] as String? ?? id,
      supplierId: data['supplierId'] as String? ?? '',
      supplierName: data['supplierName'] as String? ?? 'Unknown supplier',
      items: items,
      subtotalMinor: (data['subtotalMinor'] as num?)?.round() ?? 0,
      discountMinor: (data['discountMinor'] as num?)?.round() ?? 0,
      taxMinor: (data['taxMinor'] as num?)?.round() ?? 0,
      deliveryMinor: (data['deliveryMinor'] as num?)?.round() ?? 0,
      totalMinor: (data['totalMinor'] as num?)?.round() ?? 0,
      amountPaidMinor: (data['amountPaidMinor'] as num?)?.round() ?? 0,
      balanceDueMinor: (data['balanceDueMinor'] as num?)?.round() ?? 0,
      status: PurchaseStatus.values.firstWhere(
        (status) => status.name == data['status'],
        orElse: () => PurchaseStatus.completed,
      ),
      paymentStatus: PurchasePaymentStatus.values.firstWhere(
        (status) => status.name == data['paymentStatus'],
        orElse: () => PurchasePaymentStatus.unpaid,
      ),
      paymentMethod: data['paymentMethod'] as String?,
      createdAt: switch (data['createdAt']) {
        Timestamp value => value.toDate(),
        DateTime value => value,
        String value => DateTime.tryParse(value),
        _ => null,
      },
    );
  }
}

String formatPurchaseNumber(String yyyymmdd, int number) =>
    'PUR-$yyyymmdd-${number.toString().padLeft(4, '0')}';

class PurchaseException implements Exception {
  const PurchaseException(this.code, {this.message});
  final String code;
  final String? message;

  String get friendlyMessage =>
      message ??
      switch (code) {
        'unauthenticated' => 'Your session expired. Please sign in again.',
        'not-found' =>
          'The requested purchase, supplier, or product was not found.',
        'failed-precondition' => 'This purchase can no longer be completed.',
        'permission-denied' =>
          'You do not have permission to record purchases.',
        _ => 'Something went wrong while processing the purchase.',
      };

  @override
  String toString() => 'PurchaseException($code): $friendlyMessage';
}
