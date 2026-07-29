import 'package:cloud_firestore/cloud_firestore.dart';

import 'sale_models.dart';

/// A completed sale document loaded from Firestore.
class Sale {
  const Sale({
    required this.id,
    required this.businessId,
    required this.receiptNumber,
    required this.customerName,
    required this.items,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.totalMinor,
    required this.amountPaidMinor,
    required this.balanceDueMinor,
    required this.changeMinor,
    required this.currencyCode,
    required this.currencySymbol,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.saleStatus,
    this.customerId,
    this.branchId,
    this.branchNameSnapshot,
    this.branchCodeSnapshot,
    this.customerPhone,
    this.cashierName,
    this.note,
    this.receiptTemplateSnapshot,
    this.createdAt,
  });

  /// Prefer [snapshot.id]; fall back to a stored `saleId` for older docs.
  factory Sale.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final storedId = (data['saleId'] as String?)?.trim();
    final id = snapshot.id.trim().isNotEmpty ? snapshot.id : (storedId ?? '');
    return Sale.fromMap(id, data);
  }

  factory Sale.fromMap(String id, Map<String, dynamic> data) {
    final rawItems = data['items'] as List<dynamic>? ?? const <dynamic>[];
    return Sale(
      id: id,
      businessId: data['businessId'] as String? ?? '',
      branchId: (data['branchId'] as String?)?.trim(),
      branchNameSnapshot: (data['branchNameSnapshot'] as String?)?.trim(),
      branchCodeSnapshot: (data['branchCodeSnapshot'] as String?)?.trim(),
      receiptNumber: data['receiptNumber'] as String? ?? id,
      customerId: data['customerId'] as String?,
      customerName: data['customerName'] as String? ?? 'Walk-in Customer',
      customerPhone: data['customerPhone'] as String?,
      items: rawItems
          .map(
            (raw) =>
                SaleLineItem.fromMap(Map<String, dynamic>.from(raw as Map)),
          )
          .toList(),
      subtotalMinor:
          (data['subtotalMinor'] as num?)?.toInt() ??
          moneyToMinor(data['subtotal']),
      discountMinor:
          (data['discountMinor'] as num?)?.toInt() ??
          moneyToMinor(data['discount']),
      taxMinor:
          (data['taxMinor'] as num?)?.toInt() ?? moneyToMinor(data['tax']),
      totalMinor:
          (data['totalMinor'] as num?)?.toInt() ?? moneyToMinor(data['total']),
      amountPaidMinor:
          (data['amountPaidMinor'] as num?)?.toInt() ??
          moneyToMinor(data['amountPaid']),
      balanceDueMinor: (data['balanceDueMinor'] as num?)?.toInt() ?? 0,
      changeMinor: (data['changeMinor'] as num?)?.toInt() ?? 0,
      currencyCode: data['currencyCode'] as String? ?? 'SLE',
      currencySymbol: data['currencySymbol'] as String? ?? 'Le',
      paymentMethod: PaymentMethod.values.firstWhere(
        (method) => method.storedValue == data['paymentMethod'],
        orElse: () => PaymentMethod.cash,
      ),
      paymentStatus: PaymentStatus.values.firstWhere(
        (status) => status.name == data['paymentStatus'],
        orElse: () => PaymentStatus.paid,
      ),
      saleStatus: SaleStatus.values.firstWhere(
        (status) => status.name == (data['saleStatus'] ?? data['status']),
        orElse: () => SaleStatus.completed,
      ),
      cashierName: data['createdByName'] as String?,
      note: data['note'] as String?,
      receiptTemplateSnapshot: data['receiptTemplateSnapshot'] is Map
          ? Map<String, dynamic>.from(data['receiptTemplateSnapshot'] as Map)
          : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String businessId;
  final String? branchId;
  final String? branchNameSnapshot;
  final String? branchCodeSnapshot;
  final String receiptNumber;
  final String? customerId;
  final String customerName;
  final String? customerPhone;
  final List<SaleLineItem> items;
  final int subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int totalMinor;
  final int amountPaidMinor;
  final int balanceDueMinor;
  final int changeMinor;
  final String currencyCode;
  final String currencySymbol;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final SaleStatus saleStatus;
  final String? cashierName;
  final String? note;
  final Map<String, dynamic>? receiptTemplateSnapshot;
  final DateTime? createdAt;

  bool get isVoided => saleStatus == SaleStatus.voided;
}

class SaleLineItem {
  const SaleLineItem({
    required this.name,
    required this.quantity,
    required this.unitPriceMinor,
    required this.lineTotalMinor,
    this.productId,
    this.costPriceMinor,
    this.unit = 'unit',
    this.quantityInput,
    this.unitPriceInput,
    this.sku,
    this.actualNetRevenueMinor,
    this.costOfGoodsSoldMinor,
    this.grossProfitMinor,
    this.profitIsExact = true,
  });

  factory SaleLineItem.fromMap(Map<String, dynamic> data) => SaleLineItem(
    productId: data['productId'] as String?,
    name: data['name'] as String? ?? 'Item',
    quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
    unitPriceMinor:
        (data['unitPriceMinor'] as num?)?.toInt() ??
        moneyToMinor(data['unitPrice']),
    lineTotalMinor:
        (data['lineTotalMinor'] as num?)?.toInt() ??
        moneyToMinor(data['lineTotal']),
    costPriceMinor: (data['costPriceMinor'] as num?)?.toInt(),
    unit: data['unit'] as String? ?? 'unit',
    quantityInput: data['quantityInput'] as String?,
    unitPriceInput: data['unitPriceInput'] as String?,
    sku: data['sku'] as String?,
    actualNetRevenueMinor: (data['actualNetRevenueMinor'] as num?)?.toInt(),
    costOfGoodsSoldMinor: (data['costOfGoodsSoldMinor'] as num?)?.toInt(),
    grossProfitMinor: (data['grossProfitMinor'] as num?)?.toInt(),
    profitIsExact: data['profitIsExact'] as bool? ?? true,
  );

  final String? productId;
  final String name;
  final double quantity;
  final int unitPriceMinor;
  final int lineTotalMinor;

  /// Cost captured at checkout. Null means older/custom data cannot support
  /// an exact COGS calculation.
  final int? costPriceMinor;
  final String unit;
  final String? quantityInput;
  final String? unitPriceInput;
  final String? sku;
  final int? actualNetRevenueMinor;
  final int? costOfGoodsSoldMinor;
  final int? grossProfitMinor;
  final bool profitIsExact;
}
