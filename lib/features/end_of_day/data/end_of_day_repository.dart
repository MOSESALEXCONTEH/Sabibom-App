import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../expenses/domain/expense.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../sales/domain/sale.dart';
import '../../sales/domain/sale_models.dart';
import '../domain/end_of_day_summary.dart';

export '../domain/end_of_day_summary.dart';

class EndOfDayRepository {
  EndOfDayRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _col(String businessId) =>
      _db.collection('businesses').doc(businessId).collection('end_of_day');

  static String dateKeyFor(DateTime date) =>
      DateFormat('yyyy-MM-dd').format(date.toLocal());

  Future<EndOfDaySummary?> get(String businessId, String dateKey) async {
    final snap = await _col(businessId).doc(dateKey).get();
    if (!snap.exists || snap.data() == null) return null;
    return EndOfDaySummary.fromMap(snap.id, snap.data()!);
  }

  Future<EndOfDayCashBreakdown> loadCashBreakdown({
    required String businessId,
    required String dateKey,
  }) async {
    final day = DateTime.tryParse(dateKey)?.toLocal() ?? DateTime.now();
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final business = _db.collection('businesses').doc(businessId);

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
      business
          .collection('supplier_payments')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('createdAt', isLessThan: Timestamp.fromDate(end))
          .get()
          .catchError((_) => business.collection('supplier_payments').limit(0).get()),
    ]);

    var cashSales = 0;
    for (final doc in results[0].docs) {
      final sale = Sale.fromFirestore(doc);
      if (sale.saleStatus != SaleStatus.completed || sale.isVoided) continue;
      if (sale.paymentMethod == PaymentMethod.cash) {
        cashSales += sale.amountPaidMinor;
      }
    }

    var cashExpenses = 0;
    for (final doc in results[1].docs) {
      final expense = Expense.fromFirestore(doc);
      if (expense.isVoided) continue;
      if (expense.paymentMethod == ExpensePaymentMethod.cash) {
        cashExpenses += expense.amountMinor;
      }
    }

    var cashSupplier = 0;
    for (final doc in results[2].docs) {
      final data = doc.data();
      final method = '${data['paymentMethod'] ?? ''}'.toLowerCase();
      if (method == 'cash') {
        cashSupplier += (data['amountMinor'] as num?)?.toInt() ?? 0;
      }
    }

    // Customer cash payments live under each customer ledger; bounded scan.
    var cashCustomer = 0;
    final customers = await business.collection('customers').limit(200).get();
    for (final customer in customers.docs) {
      final ledger = await customer.reference
          .collection('ledger')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('createdAt', isLessThan: Timestamp.fromDate(end))
          .limit(50)
          .get();
      for (final entry in ledger.docs) {
        final data = entry.data();
        final type = '${data['type'] ?? ''}';
        if (type != 'payment' && type != 'customer_payment') continue;
        final method = '${data['paymentMethod'] ?? 'cash'}'.toLowerCase();
        if (method != 'cash') continue;
        cashCustomer += (data['creditMinor'] as num?)?.toInt() ??
            (data['amountMinor'] as num?)?.toInt() ??
            0;
      }
    }

    return EndOfDayCashBreakdown(
      cashSalesMinor: cashSales,
      cashExpensesMinor: cashExpenses,
      cashSupplierPaymentsMinor: cashSupplier,
      cashCustomerPaymentsMinor: cashCustomer,
    );
  }

  Future<EndOfDaySummary> saveDraft({
    required String businessId,
    required String dateKey,
    required int openingCashMinor,
    required int countedCashMinor,
    String? notes,
  }) async {
    final breakdown = await loadCashBreakdown(
      businessId: businessId,
      dateKey: dateKey,
    );
    final expected = EndOfDayCalculator.expectedCashMinor(
      openingCashMinor: openingCashMinor,
      cashSalesMinor: breakdown.cashSalesMinor,
      cashCustomerPaymentsMinor: breakdown.cashCustomerPaymentsMinor,
      cashExpensesMinor: breakdown.cashExpensesMinor,
      cashSupplierPaymentsMinor: breakdown.cashSupplierPaymentsMinor,
    );
    final diff = EndOfDayCalculator.differenceMinor(
      countedCashMinor: countedCashMinor,
      expectedCashMinor: expected,
    );
    final summary = EndOfDaySummary(
      id: dateKey,
      businessId: businessId,
      dateKey: dateKey,
      status: EndOfDayStatus.draft,
      openingCashMinor: openingCashMinor,
      countedCashMinor: countedCashMinor,
      expectedCashMinor: expected,
      cashSalesMinor: breakdown.cashSalesMinor,
      cashExpensesMinor: breakdown.cashExpensesMinor,
      cashSupplierPaymentsMinor: breakdown.cashSupplierPaymentsMinor,
      cashCustomerPaymentsMinor: breakdown.cashCustomerPaymentsMinor,
      differenceMinor: diff,
      differenceKind: CashDifferenceKind.fromDifference(diff),
      notes: notes,
    );

    final existing = await get(businessId, dateKey);
    if (existing?.isFinalized == true) {
      throw StateError('Today’s End of Day is already finalized.');
    }

    await _col(businessId).doc(dateKey).set({
      ...summary.toMap(),
      'createdAt': existing?.createdAt == null
          ? FieldValue.serverTimestamp()
          : null,
    }..removeWhere((k, v) => v == null), SetOptions(merge: true));

    await _syncDailySummary(businessId, dateKey, summary);
    return summary;
  }

  Future<EndOfDaySummary> finalize({
    required String businessId,
    required String dateKey,
    required int openingCashMinor,
    required int countedCashMinor,
    String? notes,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Sign in to finalize End of Day.');

    final draft = await saveDraft(
      businessId: businessId,
      dateKey: dateKey,
      openingCashMinor: openingCashMinor,
      countedCashMinor: countedCashMinor,
      notes: notes,
    );

    await _col(businessId).doc(dateKey).set({
      'status': EndOfDayStatus.finalized.storedValue,
      'finalizedAt': FieldValue.serverTimestamp(),
      'finalizedBy': user.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final finalized = draft;
    await _syncDailySummary(
      businessId,
      dateKey,
      EndOfDaySummary(
        id: finalized.id,
        businessId: finalized.businessId,
        dateKey: finalized.dateKey,
        status: EndOfDayStatus.finalized,
        openingCashMinor: finalized.openingCashMinor,
        countedCashMinor: finalized.countedCashMinor,
        expectedCashMinor: finalized.expectedCashMinor,
        cashSalesMinor: finalized.cashSalesMinor,
        cashExpensesMinor: finalized.cashExpensesMinor,
        cashSupplierPaymentsMinor: finalized.cashSupplierPaymentsMinor,
        cashCustomerPaymentsMinor: finalized.cashCustomerPaymentsMinor,
        differenceMinor: finalized.differenceMinor,
        differenceKind: finalized.differenceKind,
        notes: finalized.notes,
        finalizedBy: user.uid,
      ),
    );

    // Resolve incomplete reminder cycle.
    try {
      final members = await _db
          .collection('businesses')
          .doc(businessId)
          .collection('members')
          .where('status', isEqualTo: 'active')
          .limit(30)
          .get();
      for (final doc in members.docs) {
        await NotificationsRepository().resolveEvent(
          'end_of_day_${businessId}_${dateKey}_incomplete_${doc.id}',
        );
      }
    } catch (_) {}

    return (await get(businessId, dateKey))!;
  }

  Future<EndOfDaySummary> reopen({
    required String businessId,
    required String dateKey,
  }) async {
    final existing = await get(businessId, dateKey);
    if (existing == null) {
      throw StateError('No End of Day summary found.');
    }
    await _col(businessId).doc(dateKey).set({
      'status': EndOfDayStatus.draft.storedValue,
      'finalizedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return (await get(businessId, dateKey))!;
  }

  Future<void> _syncDailySummary(
    String businessId,
    String dateKey,
    EndOfDaySummary summary,
  ) async {
    await _db
        .collection('businesses')
        .doc(businessId)
        .collection('daily_summaries')
        .doc(dateKey)
        .set({
      'endOfDayStatus': summary.status.storedValue,
      'cashDifferenceMinor': summary.differenceMinor,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

class EndOfDayCashBreakdown {
  const EndOfDayCashBreakdown({
    required this.cashSalesMinor,
    required this.cashExpensesMinor,
    required this.cashSupplierPaymentsMinor,
    required this.cashCustomerPaymentsMinor,
  });

  final int cashSalesMinor;
  final int cashExpensesMinor;
  final int cashSupplierPaymentsMinor;
  final int cashCustomerPaymentsMinor;
}
