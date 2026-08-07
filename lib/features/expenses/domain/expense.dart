import 'package:cloud_firestore/cloud_firestore.dart';

import '../../sales/domain/sale_models.dart';

enum ExpenseStatus {
  active,
  voided;

  String get storedValue => name;

  static ExpenseStatus fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return ExpenseStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => ExpenseStatus.active,
    );
  }
}

enum ExpensePaymentMethod {
  cash,
  mobileMoney,
  bankTransfer,
  card,
  credit,
  other;

  String get storedValue => switch (this) {
    ExpensePaymentMethod.cash => 'cash',
    ExpensePaymentMethod.mobileMoney => 'mobile_money',
    ExpensePaymentMethod.bankTransfer => 'bank_transfer',
    ExpensePaymentMethod.card => 'card',
    ExpensePaymentMethod.credit => 'credit',
    ExpensePaymentMethod.other => 'other',
  };

  String get label => switch (this) {
    ExpensePaymentMethod.cash => 'Cash',
    ExpensePaymentMethod.mobileMoney => 'Mobile Money',
    ExpensePaymentMethod.bankTransfer => 'Bank Transfer',
    ExpensePaymentMethod.card => 'Card',
    ExpensePaymentMethod.credit => 'Credit',
    ExpensePaymentMethod.other => 'Other',
  };

  static ExpensePaymentMethod fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return ExpensePaymentMethod.values.firstWhere(
      (m) => m.storedValue == raw || m.name == raw,
      orElse: () => ExpensePaymentMethod.cash,
    );
  }
}

class Expense {
  const Expense({
    required this.id,
    required this.businessId,
    required this.expenseNumber,
    required this.categoryId,
    required this.categoryName,
    required this.amountMinor,
    required this.currencyCode,
    required this.description,
    required this.paymentMethod,
    required this.expenseDate,
    required this.status,
    this.paymentReference,
    this.supplierId,
    this.supplierName,
    this.attachmentUrl,
    this.attachmentCid,
    this.attachmentFileName,
    this.notes,
    this.createdBy,
    this.createdByName,
    this.createdAt,
    this.updatedAt,
    this.voidedAt,
    this.voidedBy,
    this.voidReason,
  });

  factory Expense.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final amountMinor =
        (data['amountMinor'] as num?)?.toInt() ?? moneyToMinor(data['amount']);
    return Expense(
      id: snapshot.id,
      businessId: data['businessId'] as String? ?? '',
      expenseNumber: data['expenseNumber'] as String? ?? snapshot.id,
      categoryId: data['categoryId'] as String? ?? '',
      categoryName: data['categoryName'] as String? ?? '',
      amountMinor: amountMinor,
      currencyCode: data['currencyCode'] as String? ?? 'SLE',
      description: data['description'] as String? ?? '',
      paymentMethod: ExpensePaymentMethod.fromStorage(data['paymentMethod']),
      paymentReference: data['paymentReference'] as String?,
      supplierId: data['supplierId'] as String?,
      supplierName: data['supplierName'] as String?,
      expenseDate:
          (data['expenseDate'] as Timestamp?)?.toDate() ??
          (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
      attachmentUrl: data['attachmentUrl'] as String?,
      attachmentCid: data['attachmentCid'] as String?,
      attachmentFileName: data['attachmentFileName'] as String?,
      notes: data['notes'] as String?,
      status: ExpenseStatus.fromStorage(data['status']),
      createdBy: data['createdBy'] as String?,
      createdByName: data['createdByName'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      voidedAt: (data['voidedAt'] as Timestamp?)?.toDate(),
      voidedBy: data['voidedBy'] as String?,
      voidReason: data['voidReason'] as String?,
    );
  }

  final String id;
  final String businessId;
  final String expenseNumber;
  final String categoryId;
  final String categoryName;
  final int amountMinor;
  final String currencyCode;
  final String description;
  final ExpensePaymentMethod paymentMethod;
  final String? paymentReference;
  final String? supplierId;
  final String? supplierName;
  final DateTime expenseDate;
  final String? attachmentUrl;
  final String? attachmentCid;
  final String? attachmentFileName;
  final String? notes;
  final ExpenseStatus status;
  final String? createdBy;
  final String? createdByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? voidedAt;
  final String? voidedBy;
  final String? voidReason;

  double get amount => minorToMoney(amountMinor);
  bool get isVoided => status == ExpenseStatus.voided;
}

class ExpenseDraft {
  const ExpenseDraft({
    required this.amountMinor,
    required this.categoryId,
    required this.categoryName,
    required this.description,
    required this.paymentMethod,
    required this.expenseDate,
    this.paymentReference,
    this.supplierId,
    this.supplierName,
    this.attachmentUrl,
    this.attachmentCid,
    this.attachmentFileName,
    this.notes,
    this.currencyCode = 'SLE',
  });

  final int amountMinor;
  final String categoryId;
  final String categoryName;
  final String description;
  final ExpensePaymentMethod paymentMethod;
  final DateTime expenseDate;
  final String? paymentReference;
  final String? supplierId;
  final String? supplierName;
  final String? attachmentUrl;
  final String? attachmentCid;
  final String? attachmentFileName;
  final String? notes;
  final String currencyCode;
}

class ExpenseException implements Exception {
  const ExpenseException(this.code, {this.message});

  final String code;
  final String? message;

  @override
  String toString() => message ?? code;

  String get userMessage => switch (code) {
    'permission-denied' => 'You do not have permission to perform this action.',
    'failed-precondition' => message ?? 'This expense cannot be updated.',
    'not-found' => 'The expense could not be found.',
    'unauthenticated' => 'Please sign in again.',
    'already-voided' => 'This expense is already voided.',
    'duplicate' => 'This transaction is already being processed.',
    _ => message ?? 'Something went wrong. Please try again.',
  };
}

/// Period helpers for expense filters.
enum ExpensePeriod {
  all,
  today,
  yesterday,
  last7Days,
  last30Days,
  thisWeek,
  thisMonth,
  thisYear,
  lastYear,
  custom,
}

({DateTime start, DateTime end}) expensePeriodRange(
  ExpensePeriod period, {
  DateTime? now,
  DateTime? customStart,
  DateTime? customEnd,
}) {
  final local = (now ?? DateTime.now()).toLocal();
  final today = DateTime(local.year, local.month, local.day);
  return switch (period) {
    ExpensePeriod.all => (
      start: DateTime(2000),
      end: today.add(const Duration(days: 1)),
    ),
    ExpensePeriod.today => (
      start: today,
      end: today.add(const Duration(days: 1)),
    ),
    ExpensePeriod.yesterday => (
      start: today.subtract(const Duration(days: 1)),
      end: today,
    ),
    ExpensePeriod.last7Days => (
      start: today.subtract(const Duration(days: 6)),
      end: today.add(const Duration(days: 1)),
    ),
    ExpensePeriod.last30Days => (
      start: today.subtract(const Duration(days: 29)),
      end: today.add(const Duration(days: 1)),
    ),
    ExpensePeriod.thisWeek => () {
      final monday = today.subtract(
        Duration(days: today.weekday - DateTime.monday),
      );
      return (start: monday, end: monday.add(const Duration(days: 7)));
    }(),
    ExpensePeriod.thisMonth => (
      start: DateTime(local.year, local.month),
      end: DateTime(local.year, local.month + 1),
    ),
    ExpensePeriod.thisYear => (
      start: DateTime(local.year),
      end: DateTime(local.year + 1),
    ),
    ExpensePeriod.lastYear => (
      start: DateTime(local.year - 1),
      end: DateTime(local.year),
    ),
    ExpensePeriod.custom => (
      start: customStart ?? today,
      end: (customEnd ?? today).add(const Duration(days: 1)),
    ),
  };
}

String formatExpenseNumber(String yyyymmdd, int nextNumber) =>
    'EXP-$yyyymmdd-${nextNumber.toString().padLeft(4, '0')}';
