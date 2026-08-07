import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/sale_calculator.dart';
import '../domain/sale_models.dart';

class SaleCartState {
  const SaleCartState({
    this.items = const <SaleItem>[],
    this.customer,
    this.orderDiscountType,
    this.orderDiscountValue = 0,
    this.paymentMethod = PaymentMethod.cash,
    this.amountReceivedMinor = 0,
    this.note = '',
    this.isSubmitting = false,
    this.submissionSaleId,
  });

  final List<SaleItem> items;
  final SaleCustomer? customer;
  final DiscountType? orderDiscountType;
  final double orderDiscountValue;
  final PaymentMethod paymentMethod;
  final int amountReceivedMinor;
  final String note;
  final bool isSubmitting;
  final String? submissionSaleId;

  SaleCartState copyWith({
    List<SaleItem>? items,
    SaleCustomer? customer,
    bool clearCustomer = false,
    DiscountType? orderDiscountType,
    bool clearOrderDiscount = false,
    double? orderDiscountValue,
    PaymentMethod? paymentMethod,
    int? amountReceivedMinor,
    String? note,
    bool? isSubmitting,
    String? submissionSaleId,
    bool clearSubmissionSaleId = false,
  }) => SaleCartState(
    items: items ?? this.items,
    customer: clearCustomer ? null : (customer ?? this.customer),
    orderDiscountType: clearOrderDiscount
        ? null
        : (orderDiscountType ?? this.orderDiscountType),
    orderDiscountValue: clearOrderDiscount
        ? 0
        : (orderDiscountValue ?? this.orderDiscountValue),
    paymentMethod: paymentMethod ?? this.paymentMethod,
    amountReceivedMinor: amountReceivedMinor ?? this.amountReceivedMinor,
    note: note ?? this.note,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    submissionSaleId: clearSubmissionSaleId
        ? null
        : (submissionSaleId ?? this.submissionSaleId),
  );

  SaleTotals totals({
    required bool taxEnabled,
    required double taxPercentage,
  }) => SaleCalculator.calculate(
    items: items,
    taxEnabled: taxEnabled,
    taxPercentage: taxPercentage,
    orderDiscountType: orderDiscountType,
    orderDiscountValue: orderDiscountValue,
    amountPaidMinor: amountReceivedMinor,
  );
}

class SaleCartController extends Notifier<SaleCartState> {
  static const _uuid = Uuid();

  @override
  SaleCartState build() => const SaleCartState();

  void addProduct(SaleProduct product) {
    if (!product.isActive || product.isOutOfStock || state.isSubmitting) return;
    final index = state.items.indexWhere(
      (item) => item.productId == product.productId && !item.isCustomItem,
    );
    if (index < 0) {
      state = state.copyWith(
        items: <SaleItem>[
          ...state.items,
          SaleItem.fromProduct(product, itemId: _uuid.v4()),
        ],
      );
      return;
    }
    final item = state.items[index];
    final nextQuantity = item.quantity + 1;
    if (product.trackStock && nextQuantity > product.quantity) return;
    _replaceItem(index, item.copyWith(quantity: nextQuantity));
  }

  String? addCustomItem({
    required String name,
    required double quantity,
    required double unitPrice,
    String unit = 'unit',
    String? quantityInput,
    String? unitPriceInput,
    double discount = 0,
    String? note,
  }) {
    final trimmedName = name.trim();
    if (trimmedName.length < 2) {
      return 'Enter an item name with at least two characters.';
    }
    if (!quantity.isFinite || quantity <= 0) {
      return 'Quantity must include a number greater than zero (e.g. 2 bags).';
    }
    if (!unitPrice.isFinite || unitPrice < 0) {
      return 'Unit price cannot be negative.';
    }
    final priceText = unitPriceInput?.trim();
    if ((priceText == null || priceText.isEmpty) && unitPrice < 0) {
      return 'Enter a unit price, or text like paid.';
    }
    if (!discount.isFinite || discount < 0) {
      return 'Discount cannot be negative.';
    }
    final recordedQty = quantityInput?.trim();
    final recordedPrice = priceText == null || priceText.isEmpty
        ? null
        : priceText;
    final item = SaleItem(
      saleItemId: _uuid.v4(),
      productId: null,
      isCustomItem: true,
      name: trimmedName,
      unit: unit.trim().isEmpty ? 'unit' : unit.trim(),
      quantityInput: recordedQty == null || recordedQty.isEmpty
          ? null
          : recordedQty,
      unitPriceInput: recordedPrice,
      quantity: quantity,
      unitPriceMinor: moneyToMinor(unitPrice),
      trackStock: false,
      discountType: discount > 0 ? DiscountType.fixed : null,
      discountValue: discount,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
    );
    state = state.copyWith(items: <SaleItem>[...state.items, item]);
    return null;
  }

  void setQuantity(
    String itemId,
    double quantity, {
    String? unit,
    String? quantityInput,
  }) {
    if (!quantity.isFinite || quantity <= 0) {
      removeItem(itemId);
      return;
    }
    final index = state.items.indexWhere((item) => item.saleItemId == itemId);
    if (index >= 0) {
      final current = state.items[index];
      final nextUnit = (unit ?? current.unit).trim();
      final recorded = quantityInput?.trim();
      final nextInput = recorded != null && recorded.isNotEmpty
          ? recorded
          : (nextUnit.isEmpty || nextUnit.toLowerCase() == 'unit'
                ? (quantity == quantity.roundToDouble()
                      ? '${quantity.toInt()}'
                      : quantity.toStringAsFixed(2))
                : (quantity == quantity.roundToDouble()
                      ? '${quantity.toInt()} $nextUnit'
                      : '${quantity.toStringAsFixed(2)} $nextUnit'));
      _replaceItem(
        index,
        current.copyWith(
          quantity: quantity,
          unit: nextUnit.isEmpty ? 'unit' : nextUnit,
          quantityInput: nextInput,
        ),
      );
    }
  }

  void increaseQuantity(String itemId) {
    final item = state.items
        .where((item) => item.saleItemId == itemId)
        .firstOrNull;
    if (item != null) setQuantity(itemId, item.quantity + 1);
  }

  void decreaseQuantity(String itemId) {
    final item = state.items
        .where((item) => item.saleItemId == itemId)
        .firstOrNull;
    if (item != null) setQuantity(itemId, item.quantity - 1);
  }

  void removeItem(String itemId) => state = state.copyWith(
    items: state.items.where((item) => item.saleItemId != itemId).toList(),
  );

  void selectCustomer(SaleCustomer? customer) => state = state.copyWith(
    customer: customer,
    clearCustomer: customer == null,
  );

  void setOrderDiscount(DiscountType? type, double value) =>
      state = state.copyWith(
        orderDiscountType: type,
        orderDiscountValue: value.isFinite && value > 0 ? value : 0,
        clearOrderDiscount: type == null,
      );

  void setPaymentMethod(PaymentMethod method) =>
      state = state.copyWith(paymentMethod: method);

  void setAmountReceived(double amount) =>
      state = state.copyWith(amountReceivedMinor: moneyToMinor(amount));

  void setNote(String note) => state = state.copyWith(note: note.trim());

  String beginSubmission() {
    if (state.isSubmitting && state.submissionSaleId != null) {
      return state.submissionSaleId!;
    }
    final saleId = _uuid.v4();
    state = state.copyWith(isSubmitting: true, submissionSaleId: saleId);
    return saleId;
  }

  void finishSubmission({required bool succeeded}) {
    state = state.copyWith(isSubmitting: false);
    if (succeeded) state = const SaleCartState();
  }

  void clear() => state = const SaleCartState();

  void _replaceItem(int index, SaleItem replacement) {
    final items = List<SaleItem>.from(state.items)..[index] = replacement;
    state = state.copyWith(items: items);
  }
}

final saleCartProvider = NotifierProvider<SaleCartController, SaleCartState>(
  SaleCartController.new,
);
