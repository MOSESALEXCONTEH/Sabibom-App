import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firestore/query_pagination.dart';
import '../domain/sabi_intent.dart';

/// On-device verified answers from Firestore so Sabi can answer business
/// questions even when the cloud metric API is unavailable or outdated.
class LocalBusinessAnswers {
  LocalBusinessAnswers({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Returns a verified answer, or null when this question should go to the API.
  Future<String?> tryAnswer({
    required String businessId,
    required String question,
    required String? branchId,
    required bool isMainBranch,
    String? forcedKind,
  }) async {
    final q = normalizeSabiInput(question).toLowerCase().trim();
    if (q.isEmpty || businessId.trim().isEmpty) return null;
    final scope = SabiBranchScope(
      branchId: branchId,
      isMainBranch: isMainBranch,
    );

    if (_looksLikeBusinessReport(q)) {
      return _businessReportAnswer(businessId, q, scope);
    }

    if (_asksForList(q, 'customer', 'client')) {
      return _customerListAnswer(businessId, scope);
    }
    if (_asksForList(q, 'supplier')) {
      return _supplierListAnswer(businessId, scope);
    }
    if (_asksForList(q, 'product', 'item') &&
        !q.contains('low') &&
        !q.contains('expir')) {
      return _productListAnswer(businessId, scope);
    }

    final expiryAsk =
        forcedKind == 'expiry' ||
        q.contains('expir') ||
        q.contains('shelf life') ||
        q.contains('best before') ||
        q.contains('going bad') ||
        q.contains('spoil') ||
        q.contains('near date') ||
        q.contains('use by');
    if (expiryAsk) {
      return _expiryAnswer(
        businessId,
        scope: scope,
        expiredOnly: q.contains('expired') && !q.contains('expiring'),
      );
    }

    if (forcedKind == 'low_stock' ||
        q.contains('low stock') ||
        q.contains('low in stock') ||
        q.contains('out of stock') ||
        q.contains('running low') ||
        ((q.contains('look') ||
                q.contains('find') ||
                q.contains('check') ||
                q.contains('show')) &&
            (q.contains('low') || q.contains('out of')) &&
            q.contains('stock'))) {
      return _lowStockAnswer(businessId, scope);
    }

    if (forcedKind == 'customer_debt' ||
        q.contains('who owes') ||
        q.contains('customer debt') ||
        q.contains('owes me') ||
        (q.contains('customer') &&
            (q.contains('balance') || q.contains('owe')))) {
      return _customerDebtAnswer(businessId, scope);
    }

    if (forcedKind == 'supplier_debt' ||
        (q.contains('supplier') &&
            (q.contains('owe') ||
                q.contains('debt') ||
                q.contains('balance')))) {
      return _supplierDebtAnswer(businessId, scope);
    }

    if (forcedKind == 'customer_count' ||
        (_asksCount(q) &&
            (q.contains('customer') || q.contains('client')) &&
            !q.contains('owe') &&
            !q.contains('balance'))) {
      return _customerCountAnswer(businessId, scope);
    }

    if (forcedKind == 'product_count' ||
        (_asksCount(q) &&
            (q.contains('product') || q.contains('item')) &&
            !q.contains('sale') &&
            !q.contains('stock'))) {
      return _productCountAnswer(businessId, scope);
    }

    if (forcedKind == 'sales' || _looksLikeSalesAsk(q)) {
      return _salesAnswer(businessId, q, scope);
    }

    if (forcedKind == 'expenses' || _looksLikeExpenseAsk(q)) {
      return _expensesAnswer(businessId, q, scope);
    }

    return null;
  }

  bool _asksCount(String q) =>
      q.contains('how many') ||
      q.contains('number of') ||
      q.contains('count of') ||
      q.contains('do i have');

  bool _asksForList(String q, String word, [String? alternative]) {
    final mentions =
        q.contains(word) || (alternative != null && q.contains(alternative));
    return mentions &&
        (q.contains('list') ||
            q.contains('names') ||
            q.contains('name of') ||
            q.contains('show me') ||
            q.contains('who are') ||
            q.contains('what are my'));
  }

  bool _looksLikeSalesAsk(String q) {
    if (q.contains('best selling') || q.contains('top selling')) return false;
    final salesWord =
        q.contains('sell') ||
        q.contains('sold') ||
        q.contains('sales') ||
        q.contains('revenue') ||
        q.contains('order');
    if (!salesWord) return false;
    return q.contains('how much') ||
        q.contains('how many') ||
        q.contains('today') ||
        q.contains('week') ||
        q.contains('month') ||
        q.contains('yesterday') ||
        q.contains('did i') ||
        q.contains('have i') ||
        q.contains('total');
  }

  bool _looksLikeExpenseAsk(String q) {
    return q.contains('expense') ||
        q.contains('spent') ||
        (q.contains('how much') && q.contains('spend'));
  }

  bool _looksLikeBusinessReport(String q) =>
      q.contains('end of day') ||
      q.contains('end-of-day') ||
      q.contains('business report') ||
      q.contains('sales report') ||
      q.contains('profit report') ||
      q.contains('profit and loss') ||
      q.contains('p&l') ||
      (q.contains('profit') &&
          !q.contains('product') &&
          !q.contains('stock')) ||
      (q.contains('daily') && q.contains('report'));

  ({DateTime start, DateTime end, String label}) _period(String q) {
    final now = DateTime.now().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    if (q.contains('yesterday')) {
      final start = today.subtract(const Duration(days: 1));
      return (start: start, end: today, label: 'yesterday');
    }
    if (q.contains('week')) {
      final monday = today.subtract(Duration(days: today.weekday - 1));
      return (
        start: monday,
        end: monday.add(const Duration(days: 7)),
        label: 'this week',
      );
    }
    if (q.contains('month')) {
      final start = DateTime(today.year, today.month);
      return (
        start: start,
        end: DateTime(today.year, today.month + 1),
        label: 'this month',
      );
    }
    return (
      start: today,
      end: today.add(const Duration(days: 1)),
      label: 'today',
    );
  }

  bool _inRange(DateTime? value, DateTime start, DateTime end) {
    if (value == null) return false;
    return !value.isBefore(start) && value.isBefore(end);
  }

  DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  Future<String> _expiryAnswer(
    String businessId, {
    SabiBranchScope? scope,
    required bool expiredOnly,
  }) async {
    final documents = await readAllQueryPages(
      _db.collection('businesses').doc(businessId).collection('products'),
    );
    final resolvedScope =
        scope ?? const SabiBranchScope(branchId: null, isMainBranch: false);
    final inventory = await _loadInventory(businessId, resolvedScope);

    final rows = <String>[];
    for (final doc in documents) {
      final data = doc.data();
      final status = (data['status'] as String?) ?? 'active';
      if (status != 'active' || data['tracksExpiry'] != true) continue;
      final branchRows = inventory[doc.id] ?? const <Map<String, dynamic>>[];
      if (branchRows.isEmpty && !resolvedScope.isMainBranch) continue;
      final source = branchRows.isEmpty
          ? <Map<String, dynamic>>[data]
          : branchRows;
      final expiryStatus = source
          .map((row) => '${row['expiryStatus'] ?? 'not_tracked'}')
          .firstWhere(
            (value) => value != 'not_tracked',
            orElse: () => 'not_tracked',
          );
      final expiringQty = source.fold<double>(
        0,
        (total, row) =>
            total + ((row['expiringQuantity'] as num?)?.toDouble() ?? 0),
      );
      final expiredQty = source.fold<double>(
        0,
        (total, row) =>
            total + ((row['expiredQuantity'] as num?)?.toDouble() ?? 0),
      );
      final relevant = expiredOnly
          ? (expiryStatus == 'expired' || expiredQty > 0)
          : (expiryStatus == 'expiring_soon' ||
                expiryStatus == 'expires_today' ||
                expiryStatus == 'expired' ||
                expiryStatus == 'mixed' ||
                expiringQty > 0 ||
                expiredQty > 0);
      if (!relevant) continue;
      final name = (data['name'] as String?)?.trim().isNotEmpty == true
          ? data['name'] as String
          : 'Product';
      final parts = <String>[name, expiryStatus.replaceAll('_', ' ')];
      if (expiredQty > 0) parts.add('expired $expiredQty');
      if (expiringQty > 0) parts.add('expiring $expiringQty');
      rows.add(parts.join(' · '));
    }

    if (rows.isEmpty) {
      return expiredOnly
          ? 'I checked your products. None are marked expired right now.'
          : 'I checked your products. None need expiry attention right now.';
    }

    final title = expiredOnly
        ? 'I found ${rows.length} expired product${rows.length == 1 ? '' : 's'}:'
        : 'I found ${rows.length} product${rows.length == 1 ? '' : 's'} with expiry attention:';
    final listed = rows.take(8).map((r) => '• $r').join('\n');
    final more = rows.length > 8 ? '\n…and ${rows.length - 8} more.' : '';
    return '$title\n$listed$more';
  }

  Future<String> _lowStockAnswer(
    String businessId,
    SabiBranchScope scope,
  ) async {
    final products = await readAllQueryPages(
      _db.collection('businesses').doc(businessId).collection('products'),
    );
    final inventory = await _loadInventory(businessId, scope);
    final rows = <String>[];
    for (final doc in products) {
      final data = doc.data();
      final status = (data['status'] as String?) ?? 'active';
      if (status != 'active') continue;
      final trackStock = data['trackStock'] != false;
      if (!trackStock) continue;
      final branchRows = inventory[doc.id] ?? const <Map<String, dynamic>>[];
      final hasBranchInventory = branchRows.isNotEmpty;
      if (!hasBranchInventory && !scope.isMainBranch) continue;
      final qty = hasBranchInventory
          ? branchRows.fold<double>(
              0,
              (total, row) =>
                  total + ((row['quantity'] as num?)?.toDouble() ?? 0),
            )
          : (data['quantity'] as num?)?.toDouble() ?? 0;
      final reorder = hasBranchInventory
          ? (branchRows.first['lowStockThreshold'] as num?)?.toDouble() ?? 0
          : (data['reorderLevel'] as num?)?.toDouble() ??
                (data['lowStockThreshold'] as num?)?.toDouble() ??
                0;
      final isLow =
          data['isLowStock'] == true ||
          qty <= 0 ||
          (reorder > 0 && qty <= reorder);
      if (!isLow) continue;
      final name = (data['name'] as String?)?.trim().isNotEmpty == true
          ? data['name'] as String
          : 'Product';
      rows.add('$name (${qty % 1 == 0 ? qty.toInt() : qty})');
    }
    if (rows.isEmpty) {
      return 'I checked your stock. Nothing looks low right now.';
    }
    final listed = rows.take(8).map((r) => '• $r').join('\n');
    final more = rows.length > 8 ? '\n…and ${rows.length - 8} more.' : '';
    return 'I found ${rows.length} low-stock item${rows.length == 1 ? '' : 's'}:\n$listed$more';
  }

  Future<String> _customerDebtAnswer(
    String businessId,
    SabiBranchScope scope,
  ) async {
    final documents = await readAllQueryPages(
      _db.collection('businesses').doc(businessId).collection('customers'),
    );
    final rows = <({String name, int balance})>[];
    for (final doc in documents) {
      final data = doc.data();
      if (!scope.matches(data)) continue;
      final status = (data['status'] as String?) ?? 'active';
      if (status == 'archived') continue;
      final balance = (data['balanceMinor'] as num?)?.round() ?? 0;
      if (balance <= 0) continue;
      final name = (data['name'] as String?)?.trim().isNotEmpty == true
          ? data['name'] as String
          : 'Customer';
      rows.add((name: name, balance: balance));
    }
    rows.sort((a, b) => b.balance.compareTo(a.balance));
    if (rows.isEmpty) {
      return 'I checked your customers. Nobody currently owes a balance.';
    }
    final currencySymbol = await _currencySymbol(businessId);
    final listed = rows
        .take(8)
        .map(
          (r) =>
              '• ${r.name} — $currencySymbol ${(r.balance / 100).toStringAsFixed(2)}',
        )
        .join('\n');
    final more = rows.length > 8 ? '\n…and ${rows.length - 8} more.' : '';
    return 'I found ${rows.length} customer${rows.length == 1 ? '' : 's'} with balances:\n$listed$more';
  }

  Future<String> _supplierDebtAnswer(
    String businessId,
    SabiBranchScope scope,
  ) async {
    final documents = await readAllQueryPages(
      _db.collection('businesses').doc(businessId).collection('suppliers'),
    );
    final rows = <({String name, int balance})>[];
    for (final doc in documents) {
      final data = doc.data();
      if (!scope.matches(data)) continue;
      final status = (data['status'] as String?) ?? 'active';
      if (status == 'archived') continue;
      final balance = (data['balanceMinor'] as num?)?.round() ?? 0;
      if (balance <= 0) continue;
      final name = (data['name'] as String?)?.trim().isNotEmpty == true
          ? data['name'] as String
          : 'Supplier';
      rows.add((name: name, balance: balance));
    }
    rows.sort((a, b) => b.balance.compareTo(a.balance));
    if (rows.isEmpty) {
      return 'I checked your suppliers. You do not currently owe any supplier balances.';
    }
    final currencySymbol = await _currencySymbol(businessId);
    final listed = rows
        .take(8)
        .map(
          (r) =>
              '• ${r.name} — $currencySymbol ${(r.balance / 100).toStringAsFixed(2)}',
        )
        .join('\n');
    final more = rows.length > 8 ? '\n…and ${rows.length - 8} more.' : '';
    return 'I found ${rows.length} supplier${rows.length == 1 ? '' : 's'} you owe:\n$listed$more';
  }

  Future<String> _customerCountAnswer(
    String businessId,
    SabiBranchScope scope,
  ) async {
    final documents = await readAllQueryPages(
      _db.collection('businesses').doc(businessId).collection('customers'),
    );
    final count = documents.where((doc) {
      if (!scope.matches(doc.data())) return false;
      final status = doc.data()['status'] as String? ?? 'active';
      return status != 'archived';
    }).length;
    return 'You have $count active customer${count == 1 ? '' : 's'}.';
  }

  Future<String> _productCountAnswer(
    String businessId,
    SabiBranchScope scope,
  ) async {
    final documents = await readAllQueryPages(
      _db.collection('businesses').doc(businessId).collection('products'),
    );
    final inventory = await _loadInventory(businessId, scope);
    final count = documents.where((doc) {
      final status = doc.data()['status'] as String? ?? 'active';
      return status == 'active' &&
          (scope.isMainBranch ||
              scope.isAllBranches ||
              inventory.containsKey(doc.id));
    }).length;
    return 'You have $count active product${count == 1 ? '' : 's'}.';
  }

  Future<String> _salesAnswer(
    String businessId,
    String q,
    SabiBranchScope scope,
  ) async {
    final period = _period(q);
    final documents = await readAllQueryPages(
      _db
          .collection('businesses')
          .doc(businessId)
          .collection('sales')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(period.start),
          )
          .where('createdAt', isLessThan: Timestamp.fromDate(period.end)),
    );
    var count = 0;
    var totalMinor = 0;
    for (final doc in documents) {
      final data = doc.data();
      if (!scope.matches(data)) continue;
      final status =
          (data['saleStatus'] as String?) ??
          (data['status'] as String?) ??
          'completed';
      if (status != 'completed') continue;
      if (!_inRange(_asDate(data['createdAt']), period.start, period.end)) {
        continue;
      }
      count++;
      totalMinor +=
          (data['totalMinor'] as num?)?.round() ??
          (((data['total'] as num?)?.toDouble() ?? 0) * 100).round();
    }
    final wantsCount = q.contains('how many') || q.contains('number of');
    if (wantsCount) {
      return 'You completed $count sale${count == 1 ? '' : 's'} ${period.label}.';
    }
    final currencySymbol = await _currencySymbol(businessId);
    return 'You sold $currencySymbol ${(totalMinor / 100).toStringAsFixed(2)} across $count sale${count == 1 ? '' : 's'} ${period.label}.';
  }

  Future<String> _expensesAnswer(
    String businessId,
    String q,
    SabiBranchScope scope,
  ) async {
    final period = _period(q);
    final documents = await readAllQueryPages(
      _db.collection('businesses').doc(businessId).collection('expenses'),
    );
    var count = 0;
    var totalMinor = 0;
    for (final doc in documents) {
      final data = doc.data();
      if (!scope.matches(data)) continue;
      final status = data['status'] as String? ?? 'active';
      if (status == 'voided' || status == 'cancelled') continue;
      final when = _asDate(data['expenseDate']) ?? _asDate(data['createdAt']);
      if (!_inRange(when, period.start, period.end)) continue;
      count++;
      totalMinor +=
          (data['amountMinor'] as num?)?.round() ??
          (((data['amount'] as num?)?.toDouble() ?? 0) * 100).round();
    }
    final currencySymbol = await _currencySymbol(businessId);
    return 'You recorded $count expense${count == 1 ? '' : 's'} totaling $currencySymbol ${(totalMinor / 100).toStringAsFixed(2)} ${period.label}.';
  }

  Future<String> _businessReportAnswer(
    String businessId,
    String q,
    SabiBranchScope scope,
  ) async {
    final period = _period(q);
    final business = _db.collection('businesses').doc(businessId);
    final results = await Future.wait([
      readAllQueryPages(
        business
            .collection('sales')
            .where(
              'createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(period.start),
            )
            .where('createdAt', isLessThan: Timestamp.fromDate(period.end)),
      ),
      readAllQueryPages(business.collection('expenses')),
      readAllQueryPages(business.collection('purchases')),
    ]);

    var salesCount = 0;
    var grossSalesMinor = 0;
    var discountMinor = 0;
    var amountPaidMinor = 0;
    var creditMinor = 0;
    var cogsMinor = 0;
    var cogsEstimated = false;
    for (final doc in results[0]) {
      final data = doc.data();
      if (!scope.matches(data) ||
          !_inRange(_asDate(data['createdAt']), period.start, period.end)) {
        continue;
      }
      final status = '${data['saleStatus'] ?? data['status'] ?? 'completed'}';
      if (status != 'completed') continue;
      salesCount++;
      grossSalesMinor +=
          (data['subtotalMinor'] as num?)?.round() ??
          (data['totalMinor'] as num?)?.round() ??
          0;
      discountMinor += (data['discountMinor'] as num?)?.round() ?? 0;
      amountPaidMinor += (data['amountPaidMinor'] as num?)?.round() ?? 0;
      creditMinor += (data['balanceDueMinor'] as num?)?.round() ?? 0;
      final items = data['items'];
      if (items is! List) {
        cogsEstimated = true;
        continue;
      }
      for (final raw in items) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final cost = (item['costPriceMinor'] as num?)?.round();
        final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
        if (cost == null) {
          cogsEstimated = true;
        } else {
          cogsMinor += (quantity * cost).round();
        }
      }
    }

    var expenseCount = 0;
    var expenseMinor = 0;
    for (final doc in results[1]) {
      final data = doc.data();
      if (!scope.matches(data)) continue;
      final status = '${data['status'] ?? 'active'}';
      if (status == 'voided' || status == 'cancelled') continue;
      final when = _asDate(data['expenseDate']) ?? _asDate(data['createdAt']);
      if (!_inRange(when, period.start, period.end)) continue;
      expenseCount++;
      expenseMinor += (data['amountMinor'] as num?)?.round() ?? 0;
    }

    var purchaseCount = 0;
    var purchaseMinor = 0;
    for (final doc in results[2]) {
      final data = doc.data();
      if (!scope.matches(data)) continue;
      final status = '${data['status'] ?? data['purchaseStatus'] ?? ''}';
      if (status == 'voided' || status == 'cancelled') continue;
      final when = _asDate(data['purchaseDate']) ?? _asDate(data['createdAt']);
      if (!_inRange(when, period.start, period.end)) continue;
      purchaseCount++;
      purchaseMinor += (data['totalMinor'] as num?)?.round() ?? 0;
    }

    final netSalesMinor = grossSalesMinor - discountMinor;
    final grossProfitMinor = netSalesMinor - cogsMinor;
    final netProfitMinor = grossProfitMinor - expenseMinor;
    final heading = q.contains('end of day') || q.contains('end-of-day')
        ? 'End-of-day report'
        : q.contains('profit')
        ? 'Profit report'
        : q.contains('sales report')
        ? 'Sales report'
        : 'Business report';
    final profitNote = cogsEstimated
        ? ' (estimated because some item costs are missing)'
        : '';
    final currencySymbol = await _currencySymbol(businessId);

    return '$heading for ${period.label}:\n'
        '• Sales: $salesCount totaling ${_money(netSalesMinor, currencySymbol)}\n'
        '• Received: ${_money(amountPaidMinor, currencySymbol)}\n'
        '• Credit sales: ${_money(creditMinor, currencySymbol)}\n'
        '• Expenses: $expenseCount totaling ${_money(expenseMinor, currencySymbol)}\n'
        '• Purchases: $purchaseCount totaling ${_money(purchaseMinor, currencySymbol)}\n'
        '• Gross profit: ${_money(grossProfitMinor, currencySymbol)}$profitNote\n'
        '• Net profit: ${_money(netProfitMinor, currencySymbol)}$profitNote';
  }

  Future<String> _currencySymbol(String businessId) async {
    final snapshot = await _db.collection('businesses').doc(businessId).get();
    final symbol = (snapshot.data()?['currencySymbol'] as String?)?.trim();
    return symbol == null || symbol.isEmpty ? 'Le' : symbol;
  }

  String _money(int minor, String currencySymbol) =>
      '$currencySymbol ${(minor / 100).toStringAsFixed(2)}';

  Future<String> _customerListAnswer(
    String businessId,
    SabiBranchScope scope,
  ) async {
    final documents = await readAllQueryPages(
      _db.collection('businesses').doc(businessId).collection('customers'),
    );
    final names =
        documents
            .where(
              (doc) =>
                  scope.matches(doc.data()) &&
                  (doc.data()['status'] as String? ?? 'active') != 'archived',
            )
            .map((doc) => '${doc.data()['name'] ?? 'Customer'}'.trim())
            .where((name) => name.isNotEmpty)
            .toList()
          ..sort();
    return _nameList('customer', names);
  }

  Future<String> _supplierListAnswer(
    String businessId,
    SabiBranchScope scope,
  ) async {
    final documents = await readAllQueryPages(
      _db.collection('businesses').doc(businessId).collection('suppliers'),
    );
    final names =
        documents
            .where(
              (doc) =>
                  scope.matches(doc.data()) &&
                  (doc.data()['status'] as String? ?? 'active') != 'archived',
            )
            .map((doc) => '${doc.data()['name'] ?? 'Supplier'}'.trim())
            .where((name) => name.isNotEmpty)
            .toList()
          ..sort();
    return _nameList('supplier', names);
  }

  Future<String> _productListAnswer(
    String businessId,
    SabiBranchScope scope,
  ) async {
    final products = await readAllQueryPages(
      _db.collection('businesses').doc(businessId).collection('products'),
    );
    final inventory = await _loadInventory(businessId, scope);
    final names =
        products
            .where((doc) {
              final active =
                  (doc.data()['status'] as String? ?? 'active') == 'active';
              return active &&
                  (scope.isMainBranch ||
                      scope.isAllBranches ||
                      inventory.containsKey(doc.id));
            })
            .map((doc) => '${doc.data()['name'] ?? 'Product'}'.trim())
            .where((name) => name.isNotEmpty)
            .toList()
          ..sort();
    return _nameList('product', names);
  }

  String _nameList(String label, List<String> names) {
    final pluralLabel = '${label}s';
    if (names.isEmpty) return 'I found no active $pluralLabel in this branch.';
    final listed = names.take(12).map((name) => '• $name').join('\n');
    final more = names.length > 12 ? '\n…and ${names.length - 12} more.' : '';
    return 'I found ${names.length} active $label${names.length == 1 ? '' : 's'}:\n$listed$more';
  }

  Future<Map<String, List<Map<String, dynamic>>>> _loadInventory(
    String businessId,
    SabiBranchScope scope,
  ) async {
    if (scope.isAllBranches) {
      final snap = await _db
          .collectionGroup('inventory')
          .where('businessId', isEqualTo: businessId)
          .get();
      final result = <String, List<Map<String, dynamic>>>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final productId = '${data['productId'] ?? doc.id}'.trim();
        result.putIfAbsent(productId, () => []).add(data);
      }
      return result;
    }
    final branchId = scope.branchId;
    if (branchId == null) return const {};
    final snap = await _db
        .collection('businesses')
        .doc(businessId)
        .collection('branches')
        .doc(branchId)
        .collection('inventory')
        .get();
    return {
      for (final doc in snap.docs)
        '${doc.data()['productId'] ?? doc.id}': [doc.data()],
    };
  }
}

class SabiBranchScope {
  const SabiBranchScope({required this.branchId, required this.isMainBranch});

  final String? branchId;
  final bool isMainBranch;

  bool get isAllBranches => branchId == null;

  bool matches(Map<String, dynamic> data) {
    if (isAllBranches) return true;
    final recordBranch = '${data['branchId'] ?? ''}'.trim();
    if (recordBranch.isEmpty) return isMainBranch;
    return recordBranch == branchId;
  }
}
