import 'package:cloud_firestore/cloud_firestore.dart';

import '../../sales/domain/sale_models.dart';

enum ProductStatus {
  active,
  archived;

  static ProductStatus fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return raw == ProductStatus.archived.name
        ? ProductStatus.archived
        : ProductStatus.active;
  }
}

enum ProductExpiryStatus {
  notTracked('not_tracked'),
  safe('safe'),
  expiringSoon('expiring_soon'),
  expiresToday('expires_today'),
  expired('expired'),
  mixed('mixed');

  const ProductExpiryStatus(this.storedValue);

  final String storedValue;

  static ProductExpiryStatus fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return ProductExpiryStatus.values.firstWhere(
      (status) => status.storedValue == raw || status.name == raw,
      orElse: () => ProductExpiryStatus.notTracked,
    );
  }
}

class Product {
  const Product({
    required this.id,
    required this.businessId,
    required this.name,
    required this.sellingPriceMinor,
    required this.costPriceMinor,
    required this.quantity,
    required this.lowStockThreshold,
    required this.trackStock,
    required this.unit,
    required this.status,
    this.sku,
    this.barcode,
    this.description,
    this.categoryId,
    this.categoryName,
    this.imageUrl,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.tracksExpiry = false,
    this.defaultExpiryReminderDays = 30,
    this.nextExpiryDate,
    this.nextExpiryBatchId,
    this.nextExpiryBatchQuantity = 0,
    this.expiringQuantity = 0,
    this.expiredQuantity = 0,
    this.unknownExpiryQuantity = 0,
    this.expiryStatus = ProductExpiryStatus.notTracked,
    this.unitPotentialProfitMinor,
    this.stockCostValueMinor = 0,
    this.expectedStockRevenueMinor = 0,
    this.potentialProfitRemainingMinor = 0,
    this.realizedGrossProfitMinor = 0,
    this.profitIsEstimated = false,
  });

  factory Product.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final storedId = (data['productId'] as String?)?.trim();
    final id = snapshot.id.trim().isNotEmpty ? snapshot.id : (storedId ?? '');
    return Product.fromMap(id, data);
  }

  factory Product.fromMap(String id, Map<String, dynamic> data) {
    return Product(
      id: id,
      businessId: data['businessId'] as String? ?? '',
      name: data['name'] as String? ?? 'Unnamed product',
      sku: data['sku'] as String?,
      barcode: data['barcode'] as String?,
      description: data['description'] as String?,
      categoryId: data['categoryId'] as String?,
      categoryName: data['categoryName'] as String?,
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
      unit: data['unit'] as String? ?? 'Piece',
      imageUrl: data['imageUrl'] as String?,
      status: ProductStatus.fromStorage(data['status']),
      createdBy: data['createdBy'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      tracksExpiry: data['tracksExpiry'] as bool? ?? false,
      defaultExpiryReminderDays:
          (data['defaultExpiryReminderDays'] as num?)?.round() ?? 30,
      nextExpiryDate: (data['nextExpiryDate'] as Timestamp?)?.toDate(),
      nextExpiryBatchId: data['nextExpiryBatchId'] as String?,
      nextExpiryBatchQuantity:
          (data['nextExpiryBatchQuantity'] as num?)?.toDouble() ?? 0,
      expiringQuantity: (data['expiringQuantity'] as num?)?.toDouble() ?? 0,
      expiredQuantity: (data['expiredQuantity'] as num?)?.toDouble() ?? 0,
      unknownExpiryQuantity:
          (data['unknownExpiryQuantity'] as num?)?.toDouble() ?? 0,
      expiryStatus: data['tracksExpiry'] == true
          ? ProductExpiryStatus.fromStorage(data['expiryStatus'])
          : ProductExpiryStatus.notTracked,
      unitPotentialProfitMinor: (data['unitPotentialProfitMinor'] as num?)
          ?.round(),
      stockCostValueMinor: (data['stockCostValueMinor'] as num?)?.round() ?? 0,
      expectedStockRevenueMinor:
          (data['expectedStockRevenueMinor'] as num?)?.round() ?? 0,
      potentialProfitRemainingMinor:
          (data['potentialProfitRemainingMinor'] as num?)?.round() ?? 0,
      realizedGrossProfitMinor:
          (data['realizedGrossProfitMinor'] as num?)?.round() ?? 0,
      profitIsEstimated: data['profitIsEstimated'] as bool? ?? false,
    );
  }

  static int _readPriceMinor({Object? minor, Object? major}) {
    if (minor is num) return minor.round();
    return moneyToMinor(major);
  }

  final String id;
  final String businessId;
  final String name;
  final String? sku;
  final String? barcode;
  final String? description;
  final String? categoryId;
  final String? categoryName;
  final int sellingPriceMinor;
  final int costPriceMinor;
  final double quantity;
  final double lowStockThreshold;
  final bool trackStock;
  final String unit;
  final String? imageUrl;
  final ProductStatus status;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool tracksExpiry;
  final int defaultExpiryReminderDays;
  final DateTime? nextExpiryDate;
  final String? nextExpiryBatchId;
  final double nextExpiryBatchQuantity;
  final double expiringQuantity;
  final double expiredQuantity;
  final double unknownExpiryQuantity;
  final ProductExpiryStatus expiryStatus;
  final int? unitPotentialProfitMinor;
  final int stockCostValueMinor;
  final int expectedStockRevenueMinor;
  final int potentialProfitRemainingMinor;
  final int realizedGrossProfitMinor;
  final bool profitIsEstimated;

  bool get isActive => status == ProductStatus.active;
  bool get isArchived => status == ProductStatus.archived;
  bool get isOutOfStock => trackStock && quantity <= 0;
  bool get isLowStock =>
      trackStock && quantity > 0 && quantity <= lowStockThreshold;
  bool get isUntracked => !trackStock;

  int get profitEstimateMinor =>
      unitPotentialProfitMinor ?? sellingPriceMinor - costPriceMinor;

  int get totalProjectedGrossProfitMinor =>
      realizedGrossProfitMinor + potentialProfitRemainingMinor;

  /// Returns the business-level product definition with branch-owned stock
  /// values overlaid for display and calculations.
  Product withStockSnapshot({
    required double quantity,
    required double lowStockThreshold,
    required int averageUnitCostMinor,
    required int stockCostValueMinor,
    required int expectedStockRevenueMinor,
    required int potentialProfitRemainingMinor,
    required int realizedGrossProfitMinor,
    required double expiringQuantity,
    required double expiredQuantity,
    required double unknownExpiryQuantity,
    required ProductExpiryStatus expiryStatus,
    DateTime? nextExpiryDate,
    String? nextExpiryBatchId,
    double nextExpiryBatchQuantity = 0,
    bool? profitIsEstimated,
  }) {
    return Product(
      id: id,
      businessId: businessId,
      name: name,
      sku: sku,
      barcode: barcode,
      description: description,
      categoryId: categoryId,
      categoryName: categoryName,
      sellingPriceMinor: sellingPriceMinor,
      costPriceMinor: averageUnitCostMinor,
      quantity: quantity,
      lowStockThreshold: lowStockThreshold,
      trackStock: trackStock,
      unit: unit,
      imageUrl: imageUrl,
      status: status,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
      tracksExpiry: tracksExpiry,
      defaultExpiryReminderDays: defaultExpiryReminderDays,
      nextExpiryDate: nextExpiryDate,
      nextExpiryBatchId: nextExpiryBatchId,
      nextExpiryBatchQuantity: nextExpiryBatchQuantity,
      expiringQuantity: expiringQuantity,
      expiredQuantity: expiredQuantity,
      unknownExpiryQuantity: unknownExpiryQuantity,
      expiryStatus: tracksExpiry
          ? expiryStatus
          : ProductExpiryStatus.notTracked,
      unitPotentialProfitMinor: sellingPriceMinor - averageUnitCostMinor,
      stockCostValueMinor: stockCostValueMinor,
      expectedStockRevenueMinor: expectedStockRevenueMinor,
      potentialProfitRemainingMinor: potentialProfitRemainingMinor,
      realizedGrossProfitMinor: realizedGrossProfitMinor,
      profitIsEstimated: profitIsEstimated ?? this.profitIsEstimated,
    );
  }

  Map<String, Object?> toFirestoreMap({required String businessId}) =>
      <String, Object?>{
        'productId': id,
        'businessId': businessId,
        'name': name.trim(),
        'sku': sku?.trim().isEmpty == true ? null : sku?.trim(),
        'barcode': barcode?.trim().isEmpty == true ? null : barcode?.trim(),
        'description': description?.trim().isEmpty == true
            ? null
            : description?.trim(),
        'categoryId': categoryId,
        'categoryName': categoryName,
        'sellingPriceMinor': sellingPriceMinor,
        'costPriceMinor': costPriceMinor,
        // Compatibility fields for existing New Sale / dashboard parsers.
        'sellingPrice': minorToMoney(sellingPriceMinor),
        'price': minorToMoney(sellingPriceMinor),
        'costPrice': minorToMoney(costPriceMinor),
        'quantity': quantity,
        'lowStockThreshold': lowStockThreshold,
        'trackStock': trackStock,
        'unit': unit,
        'imageUrl': imageUrl,
        'status': status.name,
        'tracksExpiry': tracksExpiry,
        'defaultExpiryReminderDays': defaultExpiryReminderDays,
        'nextExpiryDate': nextExpiryDate == null
            ? null
            : Timestamp.fromDate(nextExpiryDate!),
        'nextExpiryBatchId': nextExpiryBatchId,
        'nextExpiryBatchQuantity': nextExpiryBatchQuantity,
        'expiringQuantity': expiringQuantity,
        'expiredQuantity': expiredQuantity,
        'unknownExpiryQuantity': unknownExpiryQuantity,
        'expiryStatus': tracksExpiry
            ? expiryStatus.storedValue
            : ProductExpiryStatus.notTracked.storedValue,
        'unitPotentialProfitMinor': profitEstimateMinor,
        'stockCostValueMinor': stockCostValueMinor,
        'expectedStockRevenueMinor': expectedStockRevenueMinor,
        'potentialProfitRemainingMinor': potentialProfitRemainingMinor,
        'realizedGrossProfitMinor': realizedGrossProfitMinor,
        'profitIsEstimated': profitIsEstimated,
      };
}

enum ProductStockFilter {
  all,
  inStock,
  lowStock,
  outOfStock,
  expiringSoon,
  expiresToday,
  expired,
  expiryUnknown,
  noExpiryTracking,
  untracked,
  archived,
}

enum ProductSort {
  name,
  nearestExpiry,
  stockQuantity,
  potentialProfit,
  realizedProfit,
  stockValue,
  recentlyAdded,
}

const productUnits = <String>[
  'Piece',
  'Pack',
  'Box',
  'Bottle',
  'Bag',
  'Kilogram',
  'Litre',
  'Metre',
  'Service',
  'Other',
];
