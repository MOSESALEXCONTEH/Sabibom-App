import 'dart:math' as math;

import '../../sales/domain/sale_models.dart';
import 'purchase.dart';

class PurchaseTotals {
  const PurchaseTotals({
    required this.subtotalMinor,
    required this.itemDiscountMinor,
    required this.orderDiscountMinor,
    required this.taxMinor,
    required this.deliveryMinor,
    required this.totalMinor,
    required this.amountPaidMinor,
    required this.balanceDueMinor,
  });

  final int subtotalMinor;
  final int itemDiscountMinor;
  final int orderDiscountMinor;
  final int taxMinor;
  final int deliveryMinor;
  final int totalMinor;
  final int amountPaidMinor;
  final int balanceDueMinor;
}

class PurchaseCalculator {
  const PurchaseCalculator._();

  static int lineSubtotal(PurchaseItem item) {
    _validateItem(item);
    return (item.quantity * item.unitCostMinor).round();
  }

  static int lineDiscount(PurchaseItem item) {
    final subtotal = lineSubtotal(item);
    return _discount(
      subtotal: subtotal,
      type: item.discountType,
      value: item.discountValue,
    );
  }

  static PurchaseTotals calculate({
    required List<PurchaseItem> items,
    DiscountType? orderDiscountType,
    double orderDiscountValue = 0,
    double taxPercentage = 0,
    int deliveryMinor = 0,
    int amountPaidMinor = 0,
  }) {
    if (!taxPercentage.isFinite || taxPercentage < 0 || taxPercentage > 100) {
      throw const PurchaseException(
        'failed-precondition',
        message: 'Tax percentage must be between 0 and 100.',
      );
    }
    if (deliveryMinor < 0 || amountPaidMinor < 0) {
      throw const PurchaseException(
        'failed-precondition',
        message: 'Delivery and amount paid cannot be negative.',
      );
    }
    final subtotal = items.fold<int>(
      0,
      (sum, item) => sum + lineSubtotal(item),
    );
    final itemDiscount = items.fold<int>(
      0,
      (sum, item) => sum + lineDiscount(item),
    );
    final afterItems = math.max(0, subtotal - itemDiscount);
    final orderDiscount = _discount(
      subtotal: afterItems,
      type: orderDiscountType,
      value: orderDiscountValue,
    );
    final taxable = math.max(0, afterItems - orderDiscount);
    final tax = (taxable * (taxPercentage / 100)).round();
    final total = math.max(0, taxable + tax + deliveryMinor);
    final paid = math.min(amountPaidMinor, total);
    return PurchaseTotals(
      subtotalMinor: subtotal,
      itemDiscountMinor: itemDiscount,
      orderDiscountMinor: orderDiscount,
      taxMinor: tax,
      deliveryMinor: deliveryMinor,
      totalMinor: total,
      amountPaidMinor: paid,
      balanceDueMinor: math.max(0, total - paid),
    );
  }

  static void _validateItem(PurchaseItem item) {
    if (!item.quantity.isFinite || item.quantity <= 0) {
      throw const PurchaseException(
        'failed-precondition',
        message: 'Each purchase quantity must be greater than zero.',
      );
    }
    if (item.unitCostMinor < 0) {
      throw const PurchaseException(
        'failed-precondition',
        message: 'Unit cost cannot be negative.',
      );
    }
    if (!item.discountValue.isFinite) {
      throw const PurchaseException(
        'failed-precondition',
        message: 'Discount must be a valid number.',
      );
    }
    if (item.discountType == DiscountType.percentage &&
        (item.discountValue < 0 || item.discountValue > 100)) {
      throw const PurchaseException(
        'failed-precondition',
        message: 'Percentage discount must be between 0 and 100.',
      );
    }
  }

  static int _discount({
    required int subtotal,
    required DiscountType? type,
    required double value,
  }) {
    if (type == null || value <= 0) return 0;
    if (!value.isFinite) {
      throw const PurchaseException(
        'failed-precondition',
        message: 'Discount must be a valid number.',
      );
    }
    if (type == DiscountType.percentage && value > 100) {
      throw const PurchaseException(
        'failed-precondition',
        message: 'Percentage discount must be between 0 and 100.',
      );
    }
    final discount = switch (type) {
      DiscountType.fixed => moneyToMinor(value),
      DiscountType.percentage => (subtotal * (value / 100)).round(),
    };
    return math.min(subtotal, math.max(0, discount));
  }
}
