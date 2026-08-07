/// Structured action parsed from a merchant instruction, e.g.
/// "add a customer called Aminata, phone 076 123 456".
class SabiAction {
  const SabiAction({
    required this.intent,
    required this.confidence,
    required this.reply,
    required this.requiresConfirmation,
    required this.warnings,
    this.customer,
    this.product,
    this.expense,
    this.supplier,
    this.clarifyingQuestion,
  });

  factory SabiAction.fromMap(Map<String, dynamic> data) {
    final customerData = data['customer'];
    final productData = data['product'];
    final expenseData = data['expense'];
    final supplierData = data['supplier'];
    return SabiAction(
      intent: data['intent'] as String? ?? 'unknown',
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0,
      reply: data['reply'] as String? ?? '',
      requiresConfirmation: data['requiresConfirmation'] as bool? ?? true,
      clarifyingQuestion: data['clarifyingQuestion'] as String?,
      warnings: (data['warnings'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => '$item')
          .toList(),
      customer: customerData is Map
          ? SabiCustomerDetails.fromMap(
              Map<String, dynamic>.from(customerData),
            )
          : null,
      product: productData is Map
          ? SabiProductDetails.fromMap(Map<String, dynamic>.from(productData))
          : null,
      expense: expenseData is Map
          ? SabiExpenseDetails.fromMap(Map<String, dynamic>.from(expenseData))
          : null,
      supplier: supplierData is Map
          ? SabiSupplierDetails.fromMap(
              Map<String, dynamic>.from(supplierData),
            )
          : null,
    );
  }

  final String intent;
  final double confidence;
  final String reply;
  final bool requiresConfirmation;
  final String? clarifyingQuestion;
  final List<String> warnings;
  final SabiCustomerDetails? customer;
  final SabiProductDetails? product;
  final SabiExpenseDetails? expense;
  final SabiSupplierDetails? supplier;

  bool get isAddCustomer => intent == 'add_customer' && customer != null;
  bool get isAddProduct => intent == 'add_product' && product != null;
  bool get isCreateReceipt => intent == 'create_receipt';
  bool get isCreateExpense => intent == 'create_expense';
  bool get isCreateSupplier => intent == 'create_supplier';
  bool get isCreatePurchase => intent == 'create_purchase';

  bool get isAskIntent =>
      intent == 'ask_expenses' ||
      intent == 'ask_profit' ||
      intent == 'ask_supplier_balance' ||
      intent == 'ask_stock_value' ||
      intent.startsWith('ask_');

  /// Expense has enough fields to confirm-and-save in chat.
  bool get canConfirmExpense =>
      isCreateExpense &&
      expense != null &&
      (expense!.amountMinor ?? 0) > 0 &&
      ((expense!.description?.trim().isNotEmpty ?? false) ||
          (expense!.categoryName?.trim().isNotEmpty ?? false));

  /// Supplier has a name to confirm-and-save in chat.
  bool get canConfirmSupplier =>
      isCreateSupplier &&
      supplier != null &&
      (supplier!.name?.trim().isNotEmpty ?? false);
}

class SabiCustomerDetails {
  const SabiCustomerDetails({
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
  });

  factory SabiCustomerDetails.fromMap(Map<String, dynamic> data) =>
      SabiCustomerDetails(
        name: (data['name'] as String? ?? '').trim(),
        phone: _cleanOptional(data['phone']),
        email: _cleanOptional(data['email']),
        address: _cleanOptional(data['address']),
        notes: _cleanOptional(data['notes']),
      );

  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
}

class SabiProductDetails {
  const SabiProductDetails({
    required this.name,
    this.sellingPriceMinor,
    this.costPriceMinor,
    this.quantity,
    this.unit,
    this.lowStockThreshold,
    this.categoryName,
    this.description,
  });

  factory SabiProductDetails.fromMap(Map<String, dynamic> data) =>
      SabiProductDetails(
        name: (data['name'] as String? ?? '').trim(),
        sellingPriceMinor: (data['sellingPriceMinor'] as num?)?.toInt(),
        costPriceMinor: (data['costPriceMinor'] as num?)?.toInt(),
        quantity: (data['quantity'] as num?)?.toDouble(),
        unit: _cleanOptional(data['unit']),
        lowStockThreshold: (data['lowStockThreshold'] as num?)?.toDouble(),
        categoryName: _cleanOptional(data['categoryName']),
        description: _cleanOptional(data['description']),
      );

  final String name;
  final int? sellingPriceMinor;
  final int? costPriceMinor;
  final double? quantity;
  final String? unit;
  final double? lowStockThreshold;
  final String? categoryName;
  final String? description;
}

class SabiExpenseDetails {
  const SabiExpenseDetails({
    this.amountMinor,
    this.categoryName,
    this.description,
    this.paymentMethod,
  });

  factory SabiExpenseDetails.fromMap(Map<String, dynamic> data) =>
      SabiExpenseDetails(
        amountMinor: (data['amountMinor'] as num?)?.toInt(),
        categoryName: _cleanOptional(data['categoryName']),
        description: _cleanOptional(data['description']),
        paymentMethod: _cleanOptional(data['paymentMethod']),
      );

  final int? amountMinor;
  final String? categoryName;
  final String? description;
  final String? paymentMethod;
}

class SabiSupplierDetails {
  const SabiSupplierDetails({this.name, this.phone});

  factory SabiSupplierDetails.fromMap(Map<String, dynamic> data) =>
      SabiSupplierDetails(
        name: _cleanOptional(data['name']),
        phone: _cleanOptional(data['phone']),
      );

  final String? name;
  final String? phone;
}

String? _cleanOptional(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}
