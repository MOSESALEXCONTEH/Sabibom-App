import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../../core/formatting/currency_formatter.dart';
import '../../customers/domain/customer.dart';
import '../../expenses/domain/expense.dart';
import '../../products/domain/product.dart';
import '../../reports/domain/profit_calculator.dart';
import '../../sales/domain/sale.dart';
import '../../sales/domain/sale_models.dart';
import '../../suppliers/domain/supplier.dart';
import '../../team/domain/app_permission.dart';
import '../../team/domain/business_membership.dart';
import '../data/notifications_repository.dart';
import '../domain/business_summaries.dart';

class BusinessSummaryService {
  BusinessSummaryService({
    FirebaseFirestore? firestore,
    NotificationsRepository? notifications,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _notifications = notifications ?? NotificationsRepository();

  final FirebaseFirestore _db;
  final NotificationsRepository _notifications;

  static String dateKeyFor(DateTime date) =>
      DateFormat('yyyy-MM-dd').format(date.toLocal());

  static String weekKeyFor(DateTime date) {
    final local = date.toLocal();
    final thursday = local.add(Duration(days: 4 - local.weekday));
    final firstDay = DateTime(thursday.year, 1, 1);
    final week = 1 + ((thursday.difference(firstDay).inDays) / 7).floor();
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  static double percentChange(int current, int previous) {
    if (previous == 0) {
      if (current == 0) return 0;
      return 100;
    }
    final pct = ((current - previous) / previous) * 100;
    if (!pct.isFinite) return 0;
    return pct;
  }

  Future<DailyBusinessSummary> generateDaily({
    required String businessId,
    DateTime? day,
    bool notify = true,
  }) async {
    final date = (day ?? DateTime.now()).toLocal();
    final dateKey = dateKeyFor(date);
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    final business = _db.collection('businesses').doc(businessId);
    final bizSnap = await business.get();
    final businessName = (bizSnap.data()?['name'] as String?) ?? 'Business';
    final timezone =
        (bizSnap.data()?['timezone'] as String?) ?? 'Africa/Freetown';

    final results = await Future.wait([
      business
          .collection('sales')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('createdAt', isLessThan: Timestamp.fromDate(end))
          .get(),
      business
          .collection('expenses')
          .where(
            'expenseDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start),
          )
          .where('expenseDate', isLessThan: Timestamp.fromDate(end))
          .get(),
      business.collection('products').get(),
      business.collection('customers').get(),
      business.collection('suppliers').get(),
    ]);

    final sales = results[0].docs.map(Sale.fromFirestore).toList();
    final expenses = results[1].docs.map(Expense.fromFirestore).toList();
    final products = results[2].docs.map(Product.fromFirestore).toList();
    final customers = results[3].docs.map(Customer.fromFirestore).toList();
    final suppliers = results[4].docs.map(Supplier.fromFirestore).toList();

    final profit = ProfitCalculator.calculate(
      sales: sales,
      expenses: expenses,
      products: products,
      suppliers: suppliers,
      customers: customers,
    );

    var cash = 0, momo = 0, bank = 0, card = 0, credit = 0;
    for (final s in sales) {
      if (s.saleStatus != SaleStatus.completed || s.isVoided) continue;
      switch (s.paymentMethod) {
        case PaymentMethod.cash:
          cash += s.totalMinor;
        case PaymentMethod.mobileMoney:
          momo += s.totalMinor;
        case PaymentMethod.bankTransfer:
          bank += s.totalMinor;
        case PaymentMethod.card:
          card += s.totalMinor;
        case PaymentMethod.credit:
          credit += s.totalMinor;
      }
      if (s.balanceDueMinor > 0) credit += s.balanceDueMinor;
    }

    final completedSales = sales
        .where((s) => s.saleStatus == SaleStatus.completed && !s.isVoided)
        .toList();
    final activeExpenses = expenses.where((e) => !e.isVoided).toList();
    final lowStock = products.where((p) => p.isActive && p.isLowStock).length;
    final outOfStock =
        products.where((p) => p.isActive && p.isOutOfStock).length;

    final summary = DailyBusinessSummary(
      id: dateKey,
      businessId: businessId,
      dateKey: dateKey,
      timezone: timezone,
      status: 'ready',
      grossSalesMinor: profit.grossSalesMinor,
      netSalesMinor: profit.netSalesMinor,
      salesCount: completedSales.length,
      cashSalesMinor: cash,
      mobileMoneySalesMinor: momo,
      bankTransferSalesMinor: bank,
      cardSalesMinor: card,
      creditSalesMinor: credit,
      expenseMinor: profit.expenseMinor,
      expenseCount: activeExpenses.length,
      costOfGoodsSoldMinor: profit.cogsMinor,
      grossProfitMinor: profit.grossProfitMinor,
      netProfitMinor: profit.netProfitMinor,
      profitIsEstimated: profit.cogsEstimated,
      customerCreditCreatedMinor: completedSales.fold<int>(
        0,
        (total, sale) => total + sale.balanceDueMinor,
      ),
      customerPaymentsMinor: 0,
      customerOutstandingMinor: profit.customerDebtMinor,
      supplierCreditCreatedMinor: 0,
      supplierPaymentsMinor: 0,
      supplierOutstandingMinor: profit.supplierDebtMinor,
      lowStockCount: lowStock,
      outOfStockCount: outOfStock,
      topProducts: const [],
      importantEvents: [
        if (outOfStock > 0) '$outOfStock products out of stock',
        if (lowStock > 0) '$lowStock products low in stock',
      ],
      calculationVersion: 1,
    );

    await business.collection('daily_summaries').doc(dateKey).set(
          summary.toMap(),
          SetOptions(merge: true),
        );

    if (notify) {
      await _notifyDaily(summary, businessName);
    }
    return summary;
  }

  Future<void> _notifyDaily(
    DailyBusinessSummary summary,
    String businessName,
  ) async {
    final members = await _db
        .collection('businesses')
        .doc(summary.businessId)
        .collection('members')
        .where('status', isEqualTo: 'active')
        .get();
    final amount = formatCurrency(summary.netSalesMinor / 100);
    for (final doc in members.docs) {
      final m = BusinessMembership.fromMap(
        doc.id,
        summary.businessId,
        doc.data(),
      );
      if (!m.hasPermission(AppPermission.viewDailySummary) &&
          !m.hasPermission(AppPermission.viewSalesReports)) {
        continue;
      }
      final prefs = await _notifications.getPreferences(
        userId: m.uid,
        businessId: summary.businessId,
      );
      if (!prefs.dailySummaryEnabled || !prefs.inAppEnabled) continue;

      var message =
          'Today you recorded $amount in sales from ${summary.salesCount} transactions.';
      if (m.hasPermission(AppPermission.viewProfit)) {
        final expense = formatCurrency(summary.expenseMinor / 100);
        final profitAmt = formatCurrency(summary.netProfitMinor / 100);
        final est = summary.profitIsEstimated ? 'estimated ' : '';
        message =
            '$message Expenses were $expense and ${est}net profit was $profitAmt.';
      }

      await _notifications.createNotification(
        userId: m.uid,
        type: AppNotificationType.dailySummaryReady,
        title: 'Daily summary ready',
        body: message,
        businessId: summary.businessId,
        businessName: businessName,
        entityType: 'daily_summary',
        entityId: summary.dateKey,
        routeName: 'dailySummary',
        routeParameters: {'dateKey': summary.dateKey},
        deduplicationKey:
            'daily_summary_${m.uid}_${summary.businessId}_${summary.dateKey}',
        generatedBy: 'business_summary_service',
      );
    }
  }

  Future<DailyBusinessSummary?> getDaily(
    String businessId,
    String dateKey,
  ) async {
    final snap = await _db
        .collection('businesses')
        .doc(businessId)
        .collection('daily_summaries')
        .doc(dateKey)
        .get();
    if (!snap.exists || snap.data() == null) return null;
    return DailyBusinessSummary.fromMap(snap.id, snap.data()!);
  }

  /// ISO week Monday 00:00 (local) through next Monday exclusive.
  static ({DateTime start, DateTime end}) weekRangeFor(String weekKey) {
    final match = RegExp(r'^(\d{4})-W(\d{2})$').firstMatch(weekKey.trim());
    if (match != null) {
      final year = int.parse(match.group(1)!);
      final week = int.parse(match.group(2)!);
      final jan4 = DateTime(year, 1, 4);
      final mondayOfWeek1 =
          jan4.subtract(Duration(days: jan4.weekday - DateTime.monday));
      final start = mondayOfWeek1.add(Duration(days: (week - 1) * 7));
      return (start: start, end: start.add(const Duration(days: 7)));
    }
    final now = DateTime.now().toLocal();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - DateTime.monday));
    return (start: start, end: start.add(const Duration(days: 7)));
  }

  Future<WeeklyBusinessSummary> generateWeekly({
    required String businessId,
    String? weekKey,
    DateTime? around,
    bool notify = true,
  }) async {
    final key = weekKey ?? weekKeyFor(around ?? DateTime.now());
    final range = weekRangeFor(key);
    final prevStart = range.start.subtract(const Duration(days: 7));
    final prevEnd = range.start;

    final business = _db.collection('businesses').doc(businessId);
    final bizSnap = await business.get();
    final businessName = (bizSnap.data()?['name'] as String?) ?? 'Business';
    final timezone =
        (bizSnap.data()?['timezone'] as String?) ?? 'Africa/Freetown';

    final results = await Future.wait([
      business
          .collection('sales')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
          )
          .where('createdAt', isLessThan: Timestamp.fromDate(range.end))
          .get(),
      business
          .collection('expenses')
          .where(
            'expenseDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
          )
          .where('expenseDate', isLessThan: Timestamp.fromDate(range.end))
          .get(),
      business
          .collection('sales')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(prevStart),
          )
          .where('createdAt', isLessThan: Timestamp.fromDate(prevEnd))
          .get(),
      business
          .collection('expenses')
          .where(
            'expenseDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(prevStart),
          )
          .where('expenseDate', isLessThan: Timestamp.fromDate(prevEnd))
          .get(),
      business.collection('products').get(),
      business.collection('customers').get(),
      business.collection('suppliers').get(),
    ]);

    final sales = results[0].docs.map(Sale.fromFirestore).toList();
    final expenses = results[1].docs.map(Expense.fromFirestore).toList();
    final prevSales = results[2].docs.map(Sale.fromFirestore).toList();
    final prevExpenses = results[3].docs.map(Expense.fromFirestore).toList();
    final products = results[4].docs.map(Product.fromFirestore).toList();
    final customers = results[5].docs.map(Customer.fromFirestore).toList();
    final suppliers = results[6].docs.map(Supplier.fromFirestore).toList();

    var newCustomers = 0;
    for (final c in customers) {
      final created = c.createdAt;
      if (created == null) continue;
      if (!created.isBefore(range.start) && created.isBefore(range.end)) {
        newCustomers++;
      }
    }

    final profit = ProfitCalculator.calculate(
      sales: sales,
      expenses: expenses,
      products: products,
      suppliers: suppliers,
      customers: customers,
    );
    final prevProfit = ProfitCalculator.calculate(
      sales: prevSales,
      expenses: prevExpenses,
      products: products,
      suppliers: suppliers,
      customers: customers,
    );

    final completedSales = sales
        .where((s) => s.saleStatus == SaleStatus.completed && !s.isVoided)
        .toList();

    final productTotals = <String, ({String name, int amountMinor, double qty})>{};
    for (final sale in completedSales) {
      for (final line in sale.items) {
        final keyName = line.name.trim().isEmpty ? 'Item' : line.name.trim();
        final prev = productTotals[keyName];
        productTotals[keyName] = (
          name: keyName,
          amountMinor: (prev?.amountMinor ?? 0) + line.lineTotalMinor,
          qty: (prev?.qty ?? 0) + line.quantity,
        );
      }
    }
    final ranked = productTotals.values.toList()
      ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    final topProducts = ranked
        .take(5)
        .map(
          (e) => <String, Object?>{
            'name': e.name,
            'amountMinor': e.amountMinor,
            'quantity': e.qty,
          },
        )
        .toList();
    final lowPerforming = ranked.length <= 1
        ? <Map<String, Object?>>[]
        : ranked.reversed
            .take(5)
            .where((e) => e.amountMinor > 0)
            .map(
              (e) => <String, Object?>{
                'name': e.name,
                'amountMinor': e.amountMinor,
                'quantity': e.qty,
              },
            )
            .toList();

    final lowStock = products
        .where((p) => p.isActive && p.isLowStock)
        .take(10)
        .map(
          (p) => <String, Object?>{
            'productId': p.id,
            'name': p.name,
            'quantity': p.quantity,
          },
        )
        .toList();
    final outOfStock = products
        .where((p) => p.isActive && p.isOutOfStock)
        .take(10)
        .map(
          (p) => <String, Object?>{
            'productId': p.id,
            'name': p.name,
            'quantity': p.quantity,
          },
        )
        .toList();

    var eodCompleted = 0;
    var shortage = 0;
    var surplus = 0;
    final now = DateTime.now().toLocal();
    final daysElapsed = List.generate(7, (i) => range.start.add(Duration(days: i)))
        .where((d) => !d.isAfter(now))
        .toList();
    for (final day in daysElapsed) {
      final dk = dateKeyFor(day);
      final snap = await business.collection('end_of_day').doc(dk).get();
      final data = snap.data();
      if (data == null) continue;
      if ('${data['status']}' == 'finalized') {
        eodCompleted++;
        final diff = (data['differenceMinor'] as num?)?.toInt() ?? 0;
        if (diff < 0) shortage += -diff;
        if (diff > 0) surplus += diff;
      }
    }
    final eodMissing = (daysElapsed.length - eodCompleted).clamp(0, 7);

    final summary = WeeklyBusinessSummary(
      id: key,
      businessId: businessId,
      weekKey: key,
      timezone: timezone,
      periodStart: range.start,
      periodEnd: range.end.subtract(const Duration(milliseconds: 1)),
      grossSalesMinor: profit.grossSalesMinor,
      netSalesMinor: profit.netSalesMinor,
      salesCount: completedSales.length,
      previousWeekSalesMinor: prevProfit.netSalesMinor,
      salesChangePercentage: percentChange(
        profit.netSalesMinor,
        prevProfit.netSalesMinor,
      ),
      expenseMinor: profit.expenseMinor,
      previousWeekExpenseMinor: prevProfit.expenseMinor,
      expenseChangePercentage: percentChange(
        profit.expenseMinor,
        prevProfit.expenseMinor,
      ),
      costOfGoodsSoldMinor: profit.cogsMinor,
      grossProfitMinor: profit.grossProfitMinor,
      netProfitMinor: profit.netProfitMinor,
      profitIsEstimated: profit.cogsEstimated,
      newCustomers: newCustomers,
      customerOutstandingMinor: profit.customerDebtMinor,
      supplierOutstandingMinor: profit.supplierDebtMinor,
      topProducts: topProducts,
      lowPerformingProducts: lowPerforming,
      lowStockProducts: lowStock,
      outOfStockProducts: outOfStock,
      endOfDayCompletedCount: eodCompleted,
      endOfDayMissingCount: eodMissing,
      cashShortageMinor: shortage,
      cashSurplusMinor: surplus,
      calculationVersion: 1,
    );

    await business.collection('weekly_summaries').doc(key).set(
          summary.toMap(),
          SetOptions(merge: true),
        );

    if (notify) {
      await _notifyWeekly(summary, businessName);
    }
    return summary;
  }

  Future<WeeklyBusinessSummary?> getWeekly(
    String businessId,
    String weekKey,
  ) async {
    final snap = await _db
        .collection('businesses')
        .doc(businessId)
        .collection('weekly_summaries')
        .doc(weekKey)
        .get();
    if (!snap.exists || snap.data() == null) return null;
    return WeeklyBusinessSummary.fromMap(snap.id, snap.data()!);
  }

  Future<void> _notifyWeekly(
    WeeklyBusinessSummary summary,
    String businessName,
  ) async {
    final members = await _db
        .collection('businesses')
        .doc(summary.businessId)
        .collection('members')
        .where('status', isEqualTo: 'active')
        .get();
    final amount = formatCurrency(summary.netSalesMinor / 100);
    final change = summary.salesChangePercentage.toStringAsFixed(1);
    for (final doc in members.docs) {
      final m = BusinessMembership.fromMap(
        doc.id,
        summary.businessId,
        doc.data(),
      );
      if (!m.hasPermission(AppPermission.viewWeeklyReport) &&
          !m.hasPermission(AppPermission.viewSalesReports)) {
        continue;
      }
      final prefs = await _notifications.getPreferences(
        userId: m.uid,
        businessId: summary.businessId,
      );
      if (!prefs.weeklyReportEnabled || !prefs.inAppEnabled) continue;

      var message =
          'This week you recorded $amount in sales ($change% vs last week).';
      if (m.hasPermission(AppPermission.viewProfit)) {
        final profitAmt = formatCurrency(summary.netProfitMinor / 100);
        final est = summary.profitIsEstimated ? 'estimated ' : '';
        message = '$message ${est}Net profit was $profitAmt.';
      }

      await _notifications.createNotification(
        userId: m.uid,
        type: AppNotificationType.weeklyReportReady,
        title: 'Weekly report ready',
        body: message,
        businessId: summary.businessId,
        businessName: businessName,
        entityType: 'weekly_summary',
        entityId: summary.weekKey,
        routeName: 'weeklyReport',
        routeParameters: {'weekKey': summary.weekKey},
        deduplicationKey:
            'weekly_summary_${m.uid}_${summary.businessId}_${summary.weekKey}',
        generatedBy: 'business_summary_service',
      );
    }
  }
}
