import 'dart:math' as math;

import 'sale_models.dart';

class SaleCalculator {
  const SaleCalculator._();

  static int lineSubtotal(SaleItem item) =>
      nonNegative((item.quantity * item.unitPriceMinor).round());

  static int lineDiscount(SaleItem item) {
    final subtotal = lineSubtotal(item);
    final value = item.discountValue;
    if (!value.isFinite || value <= 0 || item.discountType == null) return 0;
    final discount = switch (item.discountType!) {
      DiscountType.fixed => moneyToMinor(value),
      DiscountType.percentage =>
        (subtotal * (value.clamp(0, 100) / 100)).round(),
    };
    return math.min(subtotal, nonNegative(discount));
  }

  static SaleTotals calculate({
    required List<SaleItem> items,
    required bool taxEnabled,
    required double taxPercentage,
    required DiscountType? orderDiscountType,
    required double orderDiscountValue,
    required int amountPaidMinor,
  }) {
    final subtotal = items.fold<int>(
      0,
      (total, item) => total + lineSubtotal(item),
    );
    final itemDiscount = items.fold<int>(
      0,
      (total, item) => total + lineDiscount(item),
    );
    final afterItems = nonNegative(subtotal - itemDiscount);
    final orderDiscount = _discount(
      subtotal: afterItems,
      type: orderDiscountType,
      value: orderDiscountValue,
    );
    final taxable = nonNegative(afterItems - orderDiscount);
    final tax = taxEnabled && taxPercentage.isFinite && taxPercentage > 0
        ? (taxable * (taxPercentage / 100)).round()
        : 0;
    final total = nonNegative(taxable + tax);
    final safePaid = nonNegative(amountPaidMinor);
    return SaleTotals(
      subtotalMinor: subtotal,
      itemDiscountMinor: itemDiscount,
      orderDiscountMinor: orderDiscount,
      taxMinor: tax,
      totalMinor: total,
      amountPaidMinor: math.min(safePaid, total),
      balanceDueMinor: nonNegative(total - safePaid),
      changeMinor: nonNegative(safePaid - total),
    );
  }

  static int _discount({
    required int subtotal,
    required DiscountType? type,
    required double value,
  }) {
    if (!value.isFinite || value <= 0 || type == null) return 0;
    final discount = switch (type) {
      DiscountType.fixed => moneyToMinor(value),
      DiscountType.percentage =>
        (subtotal * (value.clamp(0, 100) / 100)).round(),
    };
    return math.min(subtotal, nonNegative(discount));
  }
}
