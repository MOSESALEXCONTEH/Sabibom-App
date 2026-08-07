import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight on-device memory of successful Sabi asks.
///
/// This is not model fine-tuning — it remembers which phrasings worked for
/// this merchant so similar future asks route to records faster.
class SabiLearningStore {
  SabiLearningStore({SharedPreferences? prefs}) : _prefsOverride = prefs;

  final SharedPreferences? _prefsOverride;

  static const _prefix = 'sabi_learn_v1_';
  static const _maxEntries = 80;

  Future<SharedPreferences> _prefs() async =>
      _prefsOverride ?? SharedPreferences.getInstance();

  String _key(String businessId) => '$_prefix$businessId';

  /// Records a verified answer so similar questions can reuse the routing.
  Future<void> rememberVerifiedAsk({
    required String businessId,
    required String question,
    String? metric,
    String? kind,
  }) async {
    final q = question.trim().toLowerCase();
    if (businessId.trim().isEmpty || q.length < 4) return;
    final resolved =
        _normalizeKind(kind) ??
        _kindFromMetric(metric) ??
        _kindFromQuestion(q);
    if (resolved == null) return;

    final prefs = await _prefs();
    final entries = await _load(businessId);
    entries.removeWhere((e) => e.question == q);
    entries.insert(
      0,
      _LearnedAsk(
        question: q,
        kind: resolved,
        hits: 1,
        updatedAtMs: _nowMs(),
      ),
    );
    while (entries.length > _maxEntries) {
      entries.removeLast();
    }
    await prefs.setString(
      _key(businessId),
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  /// Returns a local answer kind when a past successful ask is similar.
  Future<String?> suggestKind({
    required String businessId,
    required String question,
  }) async {
    final q = question.trim().toLowerCase();
    if (businessId.trim().isEmpty || q.length < 4) return null;
    final direct = _kindFromQuestion(q);
    if (direct != null) return direct;

    final entries = await _load(businessId);
    _LearnedAsk? best;
    var bestScore = 0.0;
    for (final entry in entries) {
      final score = _similarity(q, entry.question);
      if (score > bestScore) {
        bestScore = score;
        best = entry;
      }
    }
    if (best == null || bestScore < 0.55) return null;
    return best.kind;
  }

  Future<List<_LearnedAsk>> _load(String businessId) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key(businessId));
    if (raw == null || raw.isEmpty) return <_LearnedAsk>[];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return <_LearnedAsk>[];
      return list
          .whereType<Map>()
          .map((m) => _LearnedAsk.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return <_LearnedAsk>[];
    }
  }

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  static const _knownKinds = <String>{
    'sales',
    'expenses',
    'customer_count',
    'product_count',
    'customer_debt',
    'supplier_debt',
    'low_stock',
    'expiry',
  };

  static String? _normalizeKind(String? value) {
    final v = value?.trim().toLowerCase();
    if (v == null || v.isEmpty) return null;
    if (_knownKinds.contains(v)) return v;
    return _kindFromMetric(v);
  }

  static String? _kindFromMetric(String? metric) {
    switch (metric) {
      case 'sales_total':
      case 'sales_count':
      case 'recent_sales':
      case 'best_sellers':
      case 'cash_paid':
        return 'sales';
      case 'expense_total':
        return 'expenses';
      case 'customer_count':
        return 'customer_count';
      case 'product_count':
        return 'product_count';
      case 'customer_balances':
        return 'customer_debt';
      case 'supplier_balances':
        return 'supplier_debt';
      case 'low_stock':
        return 'low_stock';
      case 'products_expiring':
      case 'expired_products':
        return 'expiry';
      default:
        return null;
    }
  }

  static String? _kindFromQuestion(String q) {
    if (q.contains('expir') || q.contains('spoil') || q.contains('best before')) {
      return 'expiry';
    }
    if (q.contains('low stock') ||
        q.contains('out of stock') ||
        q.contains('running low')) {
      return 'low_stock';
    }
    if (q.contains('who owes') || q.contains('owes me') || q.contains('customer debt')) {
      return 'customer_debt';
    }
    if (q.contains('supplier') &&
        (q.contains('owe') || q.contains('debt') || q.contains('balance'))) {
      return 'supplier_debt';
    }
    if (q.contains('expense') || q.contains('spent') || q.contains('spend')) {
      return 'expenses';
    }
    if ((q.contains('sell') || q.contains('sold') || q.contains('sales')) &&
        (q.contains('today') ||
            q.contains('week') ||
            q.contains('month') ||
            q.contains('yesterday') ||
            q.contains('how much') ||
            q.contains('how many'))) {
      return 'sales';
    }
    if (q.contains('how many') && q.contains('customer')) return 'customer_count';
    if (q.contains('how many') && q.contains('product')) return 'product_count';
    return null;
  }

  static double _similarity(String a, String b) {
    if (a == b) return 1;
    if (a.contains(b) || b.contains(a)) return 0.85;
    final ta = a.split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();
    final tb = b.split(RegExp(r'\s+')).where((t) => t.length > 2).toSet();
    if (ta.isEmpty || tb.isEmpty) return 0;
    final inter = ta.intersection(tb).length;
    final union = ta.union(tb).length;
    return inter / union;
  }
}

class _LearnedAsk {
  const _LearnedAsk({
    required this.question,
    required this.kind,
    required this.hits,
    required this.updatedAtMs,
  });

  factory _LearnedAsk.fromJson(Map<String, dynamic> json) => _LearnedAsk(
        question: '${json['q'] ?? ''}',
        kind: '${json['k'] ?? ''}',
        hits: (json['h'] as num?)?.toInt() ?? 1,
        updatedAtMs: (json['t'] as num?)?.toInt() ?? 0,
      );

  final String question;
  final String kind;
  final int hits;
  final int updatedAtMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'q': question,
        'k': kind,
        'h': hits,
        't': updatedAtMs,
      };
}
