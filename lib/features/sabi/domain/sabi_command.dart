import 'sabi_action.dart';

class SabiCommandItem {
  const SabiCommandItem({
    required this.spokenName,
    required this.quantity,
    required this.action,
    this.spokenUnit,
    this.quantityInput,
    this.spokenUnitPriceMinor,
    this.spokenUnitPriceText,
  });

  factory SabiCommandItem.fromMap(Map<String, dynamic> data) {
    final quantity = (data['quantity'] as num?)?.toDouble() ?? 1;
    final spokenUnit = (data['spokenUnit'] as String?)?.trim();
    final quantityInput = (data['quantityInput'] as String?)?.trim();
    final priceText = (data['spokenUnitPriceText'] as String?)?.trim();
    final unit = spokenUnit == null || spokenUnit.isEmpty ? null : spokenUnit;
    final recorded = quantityInput == null || quantityInput.isEmpty
        ? null
        : quantityInput;
    final recordedPrice = priceText == null || priceText.isEmpty
        ? null
        : priceText;
    return SabiCommandItem(
      spokenName: data['spokenName'] as String? ?? '',
      quantity: quantity,
      spokenUnit: unit,
      quantityInput: recorded,
      spokenUnitPriceMinor: (data['spokenUnitPriceMinor'] as num?)?.toInt(),
      spokenUnitPriceText: recordedPrice,
      action: data['action'] as String? ?? 'add',
    );
  }

  final String spokenName;
  final double quantity;
  final String? spokenUnit;
  final String? quantityInput;
  final int? spokenUnitPriceMinor;

  /// Exact price phrase (e.g. `paid`, `50 Le`). Math uses [spokenUnitPriceMinor].
  final String? spokenUnitPriceText;
  final String action;

  /// True when the merchant gave a price number or a text price like `paid`.
  bool get hasSpokenPrice =>
      spokenUnitPriceMinor != null ||
      (spokenUnitPriceText != null && spokenUnitPriceText!.isNotEmpty);
}

class SabiCommand {
  const SabiCommand({
    required this.intent,
    required this.confidence,
    required this.items,
    required this.requiresConfirmation,
    required this.warnings,
    this.customerQuery,
    this.paymentMethod,
    this.amountPaidMinor,
    this.isCredit = false,
    this.discountType,
    this.discountValue,
    this.receiptTemplateQuery,
    this.clarifyingQuestion,
  });

  factory SabiCommand.fromMap(Map<String, dynamic> data) {
    final payment = Map<String, dynamic>.from(
      (data['payment'] as Map?) ?? const <String, dynamic>{},
    );
    final discount = Map<String, dynamic>.from(
      (data['discount'] as Map?) ?? const <String, dynamic>{},
    );
    final items = (data['items'] as List<dynamic>? ?? const <dynamic>[])
        .map(
          (raw) =>
              SabiCommandItem.fromMap(Map<String, dynamic>.from(raw as Map)),
        )
        .toList();
    return SabiCommand(
      intent: data['intent'] as String? ?? 'unknown',
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0,
      items: items,
      customerQuery: data['customerQuery'] as String?,
      paymentMethod: payment['method'] as String?,
      amountPaidMinor: (payment['amountPaidMinor'] as num?)?.toInt(),
      isCredit: payment['isCredit'] as bool? ?? false,
      discountType: discount['type'] as String?,
      discountValue: (discount['value'] as num?)?.toDouble(),
      receiptTemplateQuery: data['receiptTemplateQuery'] as String?,
      requiresConfirmation: data['requiresConfirmation'] as bool? ?? true,
      clarifyingQuestion: data['clarifyingQuestion'] as String?,
      warnings: (data['warnings'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => '$item')
          .toList(),
    );
  }

  final String intent;
  final double confidence;
  final List<SabiCommandItem> items;
  final String? customerQuery;
  final String? paymentMethod;
  final int? amountPaidMinor;
  final bool isCredit;
  final String? discountType;
  final double? discountValue;
  final String? receiptTemplateQuery;
  final bool requiresConfirmation;
  final String? clarifyingQuestion;
  final List<String> warnings;
}

class SabiBusinessAnswer {
  const SabiBusinessAnswer({
    required this.verified,
    required this.answer,
    this.metric,
    this.action,
    this.sabiAction,
  });

  factory SabiBusinessAnswer.fromMap(Map<String, dynamic> data) =>
      SabiBusinessAnswer(
        verified: data['verified'] as bool? ?? false,
        answer: data['answer'] as String? ?? '',
        metric: data['metric'] is Map
            ? Map<String, dynamic>.from(data['metric'] as Map)
            : null,
        action: data['action'] as String?,
        sabiAction: data['sabiAction'] is Map
            ? SabiAction.fromMap(
                Map<String, dynamic>.from(data['sabiAction'] as Map),
              )
            : null,
      );

  final bool verified;
  final String answer;
  final Map<String, dynamic>? metric;
  final String? action;
  final SabiAction? sabiAction;
}
