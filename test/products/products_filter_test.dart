import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/products/application/products_providers.dart';
import 'package:sabibom/features/products/domain/inventory_movement.dart';
import 'package:sabibom/features/products/domain/product.dart';

Product _product({
  required String id,
  required String name,
  double quantity = 10,
  double threshold = 5,
  bool trackStock = true,
  ProductStatus status = ProductStatus.active,
  String? sku,
  String? barcode,
}) {
  return Product(
    id: id,
    businessId: 'biz-1',
    name: name,
    sku: sku,
    barcode: barcode,
    sellingPriceMinor: 1000,
    costPriceMinor: 500,
    quantity: quantity,
    lowStockThreshold: threshold,
    trackStock: trackStock,
    unit: 'Piece',
    status: status,
  );
}

void main() {
  final products = <Product>[
    _product(id: '1', name: 'Rice', quantity: 20, sku: 'RIC-1'),
    _product(id: '2', name: 'Oil', quantity: 2, threshold: 5, barcode: '123'),
    _product(id: '3', name: 'Soap', quantity: 0),
    _product(id: '4', name: 'Service Fee', trackStock: false),
    _product(id: '5', name: 'Old Item', status: ProductStatus.archived),
  ];

  test('products empty filter returns active products', () {
    final result = filterProducts(
      products: products,
      query: '',
      filter: ProductStockFilter.all,
    );
    expect(result.map((p) => p.id), <String>['1', '2', '3', '4']);
  });

  test('low stock filter', () {
    final result = filterProducts(
      products: products,
      query: '',
      filter: ProductStockFilter.lowStock,
    );
    expect(result.map((p) => p.id), <String>['2']);
  });

  test('out of stock filter', () {
    final result = filterProducts(
      products: products,
      query: '',
      filter: ProductStockFilter.outOfStock,
    );
    expect(result.map((p) => p.id), <String>['3']);
  });

  test('product search by sku and barcode', () {
    expect(
      filterProducts(
        products: products,
        query: 'ric-1',
        filter: ProductStockFilter.all,
      ).single.id,
      '1',
    );
    expect(
      filterProducts(
        products: products,
        query: '123',
        filter: ProductStockFilter.all,
      ).single.id,
      '2',
    );
  });

  test('duplicate barcode validation ignores blank and current product', () {
    expect(hasDuplicateBarcode(products: products, barcode: '123'), isTrue);
    expect(
      hasDuplicateBarcode(
        products: products,
        barcode: '123',
        excludingProductId: '2',
      ),
      isFalse,
    );
    expect(hasDuplicateBarcode(products: products, barcode: '  '), isFalse);
  });

  test('stock out signed quantity is negative', () {
    expect(InventoryAdjustmentType.stockIn.signedQuantity(3), 3);
    expect(InventoryAdjustmentType.openingBalance.signedQuantity(3), 3);
    expect(InventoryAdjustmentType.stockOut.signedQuantity(3), -3);
  });

  test('expiry filters use product summary fields', () {
    final tracked = <Product>[
      _product(id: '1', name: 'Milk').copyWithExpiry(
        tracksExpiry: true,
        expiryStatus: ProductExpiryStatus.expiringSoon,
        expiringQuantity: 5,
      ),
      _product(id: '2', name: 'Yoghurt').copyWithExpiry(
        tracksExpiry: true,
        expiryStatus: ProductExpiryStatus.expiresToday,
      ),
      _product(id: '3', name: 'Juice').copyWithExpiry(
        tracksExpiry: true,
        expiryStatus: ProductExpiryStatus.expired,
        expiredQuantity: 2,
      ),
      _product(
        id: '4',
        name: 'Cream',
      ).copyWithExpiry(tracksExpiry: true, unknownExpiryQuantity: 8),
      _product(id: '5', name: 'Shoe'),
    ];

    expect(
      filterProducts(
        products: tracked,
        query: '',
        filter: ProductStockFilter.expiringSoon,
      ).map((p) => p.id),
      <String>['1'],
    );
    expect(
      filterProducts(
        products: tracked,
        query: '',
        filter: ProductStockFilter.expiresToday,
      ).single.id,
      '2',
    );
    expect(
      filterProducts(
        products: tracked,
        query: '',
        filter: ProductStockFilter.expired,
      ).single.id,
      '3',
    );
    expect(
      filterProducts(
        products: tracked,
        query: '',
        filter: ProductStockFilter.expiryUnknown,
      ).single.id,
      '4',
    );
    expect(
      filterProducts(
        products: tracked,
        query: '',
        filter: ProductStockFilter.noExpiryTracking,
      ).map((p) => p.id),
      <String>['5'],
    );
  });
}

extension on Product {
  Product copyWithExpiry({
    bool? tracksExpiry,
    ProductExpiryStatus? expiryStatus,
    double? expiringQuantity,
    double? expiredQuantity,
    double? unknownExpiryQuantity,
  }) {
    return Product(
      id: id,
      businessId: businessId,
      name: name,
      sellingPriceMinor: sellingPriceMinor,
      costPriceMinor: costPriceMinor,
      quantity: quantity,
      lowStockThreshold: lowStockThreshold,
      trackStock: trackStock,
      unit: unit,
      status: status,
      sku: sku,
      barcode: barcode,
      tracksExpiry: tracksExpiry ?? this.tracksExpiry,
      expiryStatus: expiryStatus ?? this.expiryStatus,
      expiringQuantity: expiringQuantity ?? this.expiringQuantity,
      expiredQuantity: expiredQuantity ?? this.expiredQuantity,
      unknownExpiryQuantity:
          unknownExpiryQuantity ?? this.unknownExpiryQuantity,
    );
  }
}
