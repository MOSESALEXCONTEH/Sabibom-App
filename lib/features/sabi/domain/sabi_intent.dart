// Shared heuristics for routing Sabi utterances (chat + voice).

const _sabiBusinessWords = <String>[
  'customer',
  'customers',
  'supplier',
  'suppliers',
  'product',
  'products',
  'expense',
  'expenses',
  'purchase',
  'purchases',
  'sales',
  'stock',
  'profit',
  'balance',
  'revenue',
  'receipt',
  'invoice',
  'inventory',
];

const _sabiBusinessAliases = <String, String>{
  'client': 'customer',
  'clients': 'customers',
  'vendor': 'supplier',
  'vendors': 'suppliers',
  'merchandise': 'product',
  'expenditure': 'expense',
};

/// Corrects only known business vocabulary. Merchant names, numbers, and
/// free-form descriptions are preserved exactly.
String normalizeSabiInput(String input) {
  return input.replaceAllMapped(RegExp(r'[A-Za-z]+'), (match) {
    final original = match.group(0)!;
    final word = original.toLowerCase();
    final alias = _sabiBusinessAliases[word];
    if (alias != null) return alias;
    if (word.length < 4 || _sabiBusinessWords.contains(word)) return original;

    String? correction;
    var bestDistance = 3;
    for (final candidate in _sabiBusinessWords) {
      if ((candidate.length - word.length).abs() > 2) continue;
      final distance = _editDistance(word, candidate);
      if (distance < bestDistance) {
        bestDistance = distance;
        correction = candidate;
      }
    }
    if (correction == null || bestDistance > (word.length >= 7 ? 2 : 1)) {
      return original;
    }
    return correction;
  });
}

int _editDistance(String left, String right) {
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var i = 0; i < left.length; i++) {
    final current = <int>[i + 1];
    for (var j = 0; j < right.length; j++) {
      final substitution = previous[j] + (left[i] == right[j] ? 0 : 1);
      current.add(
        [
          current[j] + 1,
          previous[j + 1] + 1,
          substitution,
        ].reduce((a, b) => a < b ? a : b),
      );
    }
    previous = current;
  }
  return previous.last;
}

class SabiClarification {
  const SabiClarification({required this.intent, required this.question});

  final String intent;
  final String question;
}

String? sabiCreationIntentFor(String input) {
  final q = normalizeSabiInput(input).toLowerCase();
  final hasCreateVerb = RegExp(
    r'\b(add|create|save|register|record|make|new)\b',
  ).hasMatch(q);
  if ((q.contains('customer') || q.contains('client')) && hasCreateVerb) {
    return 'add_customer';
  }
  if ((q.contains('supplier') || q.contains('vendor')) && hasCreateVerb) {
    return 'create_supplier';
  }
  if (q.contains('product') && hasCreateVerb) return 'add_product';
  if (q.contains('expense') && hasCreateVerb) return 'create_expense';
  if (sabiLooksLikePurchaseDraft(q)) return 'create_purchase';
  if (sabiLooksLikeSaleDraft(q)) return 'create_receipt';
  return null;
}

SabiClarification? sabiClarificationFor(String input) {
  final q = normalizeSabiInput(input).toLowerCase().trim();
  final simplified = q
      .replaceAll(RegExp(r'[^\w\s&-]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool isBare(String entity) {
    final remainder = simplified
        .replaceAll(
          RegExp(
            r'\b(please|can|you|help|me|i|want|need|to|add|create|save|register|record|make|new|a|an|the|only)\b',
          ),
          ' ',
        )
        .replaceAll(RegExp('\\b${RegExp.escape(entity)}s?\\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return remainder.isEmpty;
  }

  if (simplified.contains('customer') && isBare('customer')) {
    return const SabiClarification(
      intent: 'add_customer',
      question:
          'What is the customer name? You can also include their phone, email, address, or notes.',
    );
  }
  if (simplified.contains('supplier') && isBare('supplier')) {
    return const SabiClarification(
      intent: 'create_supplier',
      question:
          'What is the supplier name? You can also include their phone number.',
    );
  }
  if (simplified.contains('product') && isBare('product')) {
    return const SabiClarification(
      intent: 'add_product',
      question:
          'What is the product name and selling price? You can also include cost price, opening stock, unit, and low-stock level.',
    );
  }
  if (simplified.contains('expense') && isBare('expense')) {
    return const SabiClarification(
      intent: 'create_expense',
      question:
          'How much was the expense, and what was it for? You can also include the category and payment method.',
    );
  }
  if ((simplified.contains('purchase') ||
          simplified == 'buy stock' ||
          simplified == 'add stock purchase') &&
      (isBare('purchase') || simplified == 'buy stock')) {
    return const SabiClarification(
      intent: 'create_purchase',
      question:
          'Which supplier and products are in the purchase? Include each quantity and unit cost if you know them.',
    );
  }
  if ((simplified.contains('sale') || simplified.contains('receipt')) &&
      (isBare('sale') || isBare('receipt'))) {
    return const SabiClarification(
      intent: 'create_receipt',
      question:
          'Which products did you sell? Include quantities and prices, and optionally the customer and payment method.',
    );
  }
  return null;
}

String sabiCommandWithClarificationContext({
  required String intent,
  required String answer,
}) {
  final prefix = switch (intent) {
    'add_customer' => 'Add customer',
    'create_supplier' => 'Add supplier',
    'add_product' => 'Add product',
    'create_expense' => 'Record expense',
    'create_purchase' => 'Create purchase draft',
    'create_receipt' => 'Create sale receipt',
    _ => '',
  };
  return prefix.isEmpty ? answer : '$prefix: $answer';
}

class SabiContactInput {
  const SabiContactInput({required this.name, this.phone, this.email});

  final String name;
  final String? phone;
  final String? email;
}

SabiContactInput? parseSabiContactInput(String input) {
  var remaining = input.trim();
  if (remaining.isEmpty) return null;

  final emailMatch = RegExp(
    r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
    caseSensitive: false,
  ).firstMatch(remaining);
  final email = emailMatch?.group(0);
  if (emailMatch != null) {
    remaining = remaining.replaceRange(emailMatch.start, emailMatch.end, ' ');
  }

  final phoneMatch = RegExp(
    r'(?:phone(?:\s+number)?|tel(?:ephone)?)?\s*[:=-]?\s*(\+?\d[\d\s-]{5,}\d)',
    caseSensitive: false,
  ).firstMatch(remaining);
  final phone = phoneMatch?.group(1)?.replaceAll(RegExp(r'[^\d+]'), '').trim();
  if (phoneMatch != null) {
    remaining = remaining.replaceRange(phoneMatch.start, phoneMatch.end, ' ');
  }

  final name = remaining
      .replaceAll(
        RegExp(
          r'\b(name|called|named|customer|client|supplier|vendor|is|phone|number|email)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[,;:]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (name.isEmpty) return null;
  return SabiContactInput(
    name: name,
    phone: phone?.isEmpty == true ? null : phone,
    email: email,
  );
}

String resolveSabiFollowUp(
  String question,
  Iterable<String> recentUserQuestions,
) {
  final lower = normalizeSabiInput(question).toLowerCase();
  final isListFollowUp =
      lower.contains('their names') ||
      lower.contains('list them') ||
      lower.contains('show them') ||
      lower.contains('who are they');
  if (!isListFollowUp) return question;

  for (final text in recentUserQuestions) {
    final previous = normalizeSabiInput(text).toLowerCase();
    if (previous.contains('customer') || previous.contains('client')) {
      return 'List my customers and give me their names';
    }
    if (previous.contains('supplier')) {
      return 'List my suppliers and give me their names';
    }
    if (previous.contains('product') || previous.contains('item')) {
      return 'List my products and give me their names';
    }
  }
  return question;
}

/// True when the merchant is asking for business metrics / insights,
/// not trying to create a sale.
bool sabiLooksLikeMetricQuestion(String text) {
  final q = normalizeSabiInput(text).toLowerCase().trim();
  if (q.isEmpty) return false;
  if (q.contains('needs my attention') ||
      q.contains('what needs attention') ||
      q.contains('unread notification') ||
      q.contains('pending approval')) {
    return true;
  }
  if (q.contains('expir') ||
      q.contains('shelf life') ||
      q.contains('best before') ||
      q.contains('going bad') ||
      q.contains('spoil') ||
      q.contains('expire soon') ||
      q.contains('expires today') ||
      q.contains('expired stock') ||
      q.contains('profit remain') ||
      q.contains('potential profit') ||
      q.contains('how much profit') ||
      q.contains('product profit')) {
    return true;
  }
  if (q.contains('look for') ||
      q.contains('find ') ||
      q.contains('check ') ||
      q.contains('show me') ||
      q.contains('list ')) {
    if (q.contains('product') ||
        q.contains('stock') ||
        q.contains('customer') ||
        q.contains('sale') ||
        q.contains('expir') ||
        q.contains('owe') ||
        q.contains('expense') ||
        q.contains('supplier')) {
      return true;
    }
  }
  if (q.contains('how many') ||
      q.contains('how much') ||
      q.contains('who owes') ||
      q.contains('which products') ||
      q.contains('running low') ||
      q.contains('low stock') ||
      q.contains('out of stock') ||
      q.contains('best selling') ||
      q.contains('top selling') ||
      q.contains('do i have') ||
      q.contains('what are my') ||
      q.contains('what is my') ||
      q.contains('profit') ||
      q.contains('expense') ||
      q.contains('spent') ||
      q.contains('stock value') ||
      q.contains('value of my stock') ||
      q.contains('owe')) {
    return true;
  }
  if ((q.contains('customer') || q.contains('client')) &&
      (q.contains('balance') || q.contains('debt'))) {
    return true;
  }
  // Supplier balance questions only — not "buy from supplier".
  if (q.contains('supplier') &&
      (q.contains('owe') ||
          q.contains('debt') ||
          q.contains('balance') ||
          q.contains('how much') ||
          q.contains('how many') ||
          q.contains('what do i'))) {
    return true;
  }
  // "How much did I sell today?" style — metric, not create-sale.
  if ((q.contains('sell') || q.contains('sold') || q.contains('sales')) &&
      (q.contains('today') ||
          q.contains('week') ||
          q.contains('month') ||
          q.contains('yesterday') ||
          q.contains('did i') ||
          q.contains('have i'))) {
    return true;
  }
  return false;
}

/// True when the instruction is about saving a customer, product, expense,
/// supplier, or purchase (data actions that need confirmation drafts).
bool sabiLooksLikeDataAction(String text) {
  if (sabiLooksLikePurchaseDraft(text)) return true;
  final lower = normalizeSabiInput(text).toLowerCase();
  final mentionsCustomer =
      lower.contains('customer') || lower.contains('client');
  final mentionsProduct =
      lower.contains('product') ||
      lower.contains('inventory') ||
      lower.contains('stock item');
  final mentionsExpense =
      lower.contains('expense') ||
      lower.contains('rent') ||
      lower.contains('electricity') ||
      lower.contains('transport') ||
      (lower.contains('paid') &&
          (lower.contains('for') || lower.contains('transport')));
  final mentionsSupplier = lower.contains('supplier');
  final wantsToAdd =
      lower.contains('add') ||
      lower.contains('save') ||
      lower.contains('create') ||
      lower.contains('register') ||
      lower.contains('record') ||
      lower.contains('new ');
  return wantsToAdd &&
      (mentionsCustomer ||
          mentionsProduct ||
          mentionsExpense ||
          mentionsSupplier);
}

/// True when the merchant wants to draft a purchase / stock buy.
/// Bare "buy"/"bought" alone is not enough — need stock/supplier context.
bool sabiLooksLikePurchaseDraft(String text) {
  if (sabiLooksLikeMetricQuestion(text)) return false;
  final lower = normalizeSabiInput(text).toLowerCase();
  if (lower.contains('purchase') || lower.contains('stock purchase')) {
    return true;
  }
  if (lower.contains('from') && lower.contains('supplier')) {
    return true;
  }
  final buyVerb =
      RegExp(r'\bbuy\b').hasMatch(lower) ||
      RegExp(r'\bbought\b').hasMatch(lower);
  if (buyVerb &&
      (lower.contains('stock') ||
          lower.contains('supplier') ||
          lower.contains('from ') ||
          lower.contains('inventory'))) {
    return true;
  }
  return false;
}

/// True when the merchant wants to draft a sale/receipt (not ask about sales).
/// Bare buy/bought is never a sale unless sell/sold/receipt language is present.
bool sabiLooksLikeSaleDraft(String text) {
  if (sabiLooksLikeMetricQuestion(text)) return false;
  if (sabiLooksLikePurchaseDraft(text)) return false;
  final lower = normalizeSabiInput(text).toLowerCase();
  return lower.contains('receipt') ||
      lower.contains('invoice') ||
      lower.contains('add sale') ||
      lower.contains('create sale') ||
      lower.contains('make a sale') ||
      lower.contains('make a receipt') ||
      lower.contains('new sale') ||
      RegExp(r'\bsell\b').hasMatch(lower) ||
      RegExp(r'\bsold\b').hasMatch(lower);
}
