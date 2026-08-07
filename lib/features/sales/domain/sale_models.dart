import 'dart:math' as math;

import '../../inventory/domain/inventory_batch.dart';

enum PaymentMethod {
  cash,
  mobileMoney,
  bankTransfer,
  card,
  credit;

  String get storedValue => switch (this) {
    PaymentMethod.cash => 'cash',
    PaymentMethod.mobileMoney => 'mobile_money',
    PaymentMethod.bankTransfer => 'bank_transfer',
    PaymentMethod.card => 'card',
    PaymentMethod.credit => 'credit',
  };

  String get label => switch (this) {
    PaymentMethod.cash => 'Cash',
    PaymentMethod.mobileMoney => 'Mobile Money',
    PaymentMethod.bankTransfer => 'Bank Transfer',
    PaymentMethod.card => 'Card',
    PaymentMethod.credit => 'Credit / Pay Later',
  };
}

enum PaymentStatus { paid, partiallyPaid, unpaid }

enum SaleStatus { draft, completed, voided }

enum DiscountType { fixed, percentage }

class SaleProduct {
  const SaleProduct({
    required this.productId,
    required this.name,
    required this.sellingPriceMinor,
    required this.quantity,
    required this.trackStock,
    required this.status,
    this.sku,
    this.barcode,
    this.unit = 'unit',
    this.lowStockThreshold = 0,
    this.costPriceMinor = 0,
    this.categoryName,
    this.imageUrl,
  });

  factory SaleProduct.fromFirestore(String id, Map<String, dynamic> data) {
    return SaleProduct(
      productId: id,
      name: data['name'] as String? ?? 'Unnamed product',
      sku: data['sku'] as String?,
      barcode: data['barcode'] as String?,
      unit: data['unit'] as String? ?? 'unit',
      sellingPriceMinor: _readPriceMinor(
        minor: data['sellingPriceMinor'],
        major: data['sellingPrice'] ?? data['price'],
      ),
      costPriceMinor: _readPriceMinor(
        minor: data['costPriceMinor'],
        major: data['costPrice'],
      ),
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
      lowStockThreshold: (data['lowStockThreshold'] as num?)?.toDouble() ?? 0,
      trackStock: data['trackStock'] as bool? ?? true,
      status: data['status'] as String? ?? 'active',
      categoryName: data['categoryName'] as String?,
      imageUrl: data['imageUrl'] as String?,
    );
  }

  static int _readPriceMinor({Object? minor, Object? major}) {
    if (minor is num) return minor.round();
    return moneyToMinor(major);
  }

  final String productId;
  final String name;
  final String? sku;
  final String? barcode;
  final String unit;
  final int sellingPriceMinor;
  final int costPriceMinor;
  final double quantity;
  final double lowStockThreshold;
  final bool trackStock;
  final String status;
  final String? categoryName;
  final String? imageUrl;

  bool get isActive => status == 'active';
  bool get isOutOfStock => trackStock && quantity <= 0;
}

class SaleCustomer {
  const SaleCustomer({
    required this.customerId,
    required this.name,
    this.phone,
    this.balanceMinor = 0,
  });

  factory SaleCustomer.fromFirestore(String id, Map<String, dynamic> data) {
    final balance = data['balanceMinor'] ?? data['balance'];
    return SaleCustomer(
      customerId: id,
      name: data['name'] as String? ?? 'Unnamed customer',
      phone: data['phone'] as String? ?? data['phoneNumber'] as String?,
      balanceMinor: balance is int ? balance : moneyToMinor(balance),
    );
  }

  final String customerId;
  final String name;
  final String? phone;
  final int balanceMinor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaleCustomer && other.customerId == customerId;

  @override
  int get hashCode => customerId.hashCode;
}

class SaleItem {
  const SaleItem({
    required this.saleItemId,
    required this.name,
    required this.quantity,
    required this.unitPriceMinor,
    required this.trackStock,
    required this.isCustomItem,
    this.productId,
    this.sku,
    this.barcode,
    this.unit = 'unit',
    this.quantityInput,
    this.unitPriceInput,
    this.costPriceMinor = 0,
    this.discountType,
    this.discountValue = 0,
    this.note,
    this.batchAllocations = const <BatchAllocation>[],
    this.actualNetRevenueMinor,
    this.costOfGoodsSoldMinor,
    this.grossProfitMinor,
    this.profitIsExact = true,
  });

  final String saleItemId;
  final String? productId;
  final bool isCustomItem;
  final String name;
  final String? sku;
  final String? barcode;
  final String unit;
  /// Exact quantity text the merchant typed/spoke (e.g. `2 bags`).
  /// Calculations always use [quantity]; this is for display/persistence.
  final String? quantityInput;
  /// Exact unit-price text (e.g. `paid`, `50 Le`). Math uses [unitPriceMinor].
  final String? unitPriceInput;
  final double quantity;
  final int unitPriceMinor;
  final int costPriceMinor;
  final bool trackStock;
  final DiscountType? discountType;
  final double discountValue;
  final String? note;
  final List<BatchAllocation> batchAllocations;
  final int? actualNetRevenueMinor;
  final int? costOfGoodsSoldMinor;
  final int? grossProfitMinor;
  final bool profitIsExact;

  SaleItem copyWith({
    double? quantity,
    String? unit,
    String? quantityInput,
    bool clearQuantityInput = false,
    String? unitPriceInput,
    bool clearUnitPriceInput = false,
    double? discountValue,
    DiscountType? discountType,
    bool clearDiscount = false,
    List<BatchAllocation>? batchAllocations,
    int? actualNetRevenueMinor,
    int? costOfGoodsSoldMinor,
    int? grossProfitMinor,
    bool? profitIsExact,
  }) => SaleItem(
    saleItemId: saleItemId,
    productId: productId,
    isCustomItem: isCustomItem,
    name: name,
    sku: sku,
    barcode: barcode,
    unit: unit ?? this.unit,
    quantityInput: clearQuantityInput
        ? null
        : (quantityInput ?? this.quantityInput),
    unitPriceInput: clearUnitPriceInput
        ? null
        : (unitPriceInput ?? this.unitPriceInput),
    quantity: quantity ?? this.quantity,
    unitPriceMinor: unitPriceMinor,
    costPriceMinor: costPriceMinor,
    trackStock: trackStock,
    discountType: clearDiscount ? null : (discountType ?? this.discountType),
    discountValue: clearDiscount ? 0 : (discountValue ?? this.discountValue),
    note: note,
    batchAllocations: batchAllocations ?? this.batchAllocations,
    actualNetRevenueMinor:
        actualNetRevenueMinor ?? this.actualNetRevenueMinor,
    costOfGoodsSoldMinor: costOfGoodsSoldMinor ?? this.costOfGoodsSoldMinor,
    grossProfitMinor: grossProfitMinor ?? this.grossProfitMinor,
    profitIsExact: profitIsExact ?? this.profitIsExact,
  );

  factory SaleItem.fromProduct(SaleProduct product, {required String itemId}) =>
      SaleItem(
        saleItemId: itemId,
        productId: product.productId,
        isCustomItem: false,
        name: product.name,
        sku: product.sku,
        barcode: product.barcode,
        unit: product.unit,
        quantity: 1,
        unitPriceMinor: product.sellingPriceMinor,
        costPriceMinor: product.costPriceMinor,
        trackStock: product.trackStock,
      );
}

class SaleTotals {
  const SaleTotals({
    required this.subtotalMinor,
    required this.itemDiscountMinor,
    required this.orderDiscountMinor,
    required this.taxMinor,
    required this.totalMinor,
    required this.amountPaidMinor,
    required this.balanceDueMinor,
    required this.changeMinor,
  });

  final int subtotalMinor;
  final int itemDiscountMinor;
  final int orderDiscountMinor;
  final int taxMinor;
  final int totalMinor;
  final int amountPaidMinor;
  final int balanceDueMinor;
  final int changeMinor;
}

int moneyToMinor(Object? value) {
  final amount = value is num
      ? value.toDouble()
      : double.tryParse('$value') ?? 0;
  if (!amount.isFinite) return 0;
  return (amount * 100).round();
}

double minorToMoney(int value) => value / 100;

int nonNegative(int value) => math.max(0, value);
