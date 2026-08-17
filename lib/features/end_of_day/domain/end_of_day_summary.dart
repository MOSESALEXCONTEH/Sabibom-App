import 'package:cloud_firestore/cloud_firestore.dart';

enum EndOfDayStatus {
  draft,
  finalized;

  String get storedValue => name;

  static EndOfDayStatus fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return EndOfDayStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => EndOfDayStatus.draft,
    );
  }
}

enum CashDifferenceKind {
  balanced,
  shortage,
  surplus;

  String get storedValue => name;
  String get label => switch (this) {
    CashDifferenceKind.balanced => 'Balanced',
    CashDifferenceKind.shortage => 'Shortage',
    CashDifferenceKind.surplus => 'Surplus',
  };

  static CashDifferenceKind fromDifference(int differenceMinor) {
    if (differenceMinor == 0) return CashDifferenceKind.balanced;
    if (differenceMinor < 0) return CashDifferenceKind.shortage;
    return CashDifferenceKind.surplus;
  }
}

class EndOfDaySummary {
  const EndOfDaySummary({
    required this.id,
    required this.businessId,
    required this.dateKey,
    required this.status,
    required this.openingCashMinor,
    required this.countedCashMinor,
    required this.expectedCashMinor,
    required this.cashSalesMinor,
    required this.cashExpensesMinor,
    required this.cashSupplierPaymentsMinor,
    required this.cashCustomerPaymentsMinor,
    required this.differenceMinor,
    required this.differenceKind,
    this.notes,
    this.finalizedAt,
    this.finalizedBy,
    this.createdAt,
    this.updatedAt,
    this.calculationVersion = 1,
  });

  final String id;
  final String businessId;
  final String dateKey;
  final EndOfDayStatus status;
  final int openingCashMinor;
  final int countedCashMinor;
  final int expectedCashMinor;
  final int cashSalesMinor;
  final int cashExpensesMinor;
  final int cashSupplierPaymentsMinor;
  final int cashCustomerPaymentsMinor;
  final int differenceMinor;
  final CashDifferenceKind differenceKind;
  final String? notes;
  final DateTime? finalizedAt;
  final String? finalizedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int calculationVersion;

  bool get isFinalized => status == EndOfDayStatus.finalized;

  factory EndOfDaySummary.fromMap(String id, Map<String, dynamic> data) {
    final diff = (data['differenceMinor'] as num?)?.toInt() ?? 0;
    return EndOfDaySummary(
      id: id,
      businessId: (data['businessId'] as String?) ?? '',
      dateKey: (data['dateKey'] as String?) ?? id,
      status: EndOfDayStatus.fromStorage(data['status']),
      openingCashMinor: (data['openingCashMinor'] as num?)?.toInt() ?? 0,
      countedCashMinor: (data['countedCashMinor'] as num?)?.toInt() ?? 0,
      expectedCashMinor: (data['expectedCashMinor'] as num?)?.toInt() ?? 0,
      cashSalesMinor: (data['cashSalesMinor'] as num?)?.toInt() ?? 0,
      cashExpensesMinor: (data['cashExpensesMinor'] as num?)?.toInt() ?? 0,
      cashSupplierPaymentsMinor:
          (data['cashSupplierPaymentsMinor'] as num?)?.toInt() ?? 0,
      cashCustomerPaymentsMinor:
          (data['cashCustomerPaymentsMinor'] as num?)?.toInt() ?? 0,
      differenceMinor: diff,
      differenceKind: CashDifferenceKind.values.firstWhere(
        (k) => k.name == data['differenceKind'],
        orElse: () => CashDifferenceKind.fromDifference(diff),
      ),
      notes: data['notes'] as String?,
      finalizedAt: data['finalizedAt'] is Timestamp
          ? (data['finalizedAt'] as Timestamp).toDate()
          : null,
      finalizedBy: data['finalizedBy'] as String?,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      calculationVersion: (data['calculationVersion'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'businessId': businessId,
    'dateKey': dateKey,
    'status': status.storedValue,
    'openingCashMinor': openingCashMinor,
    'countedCashMinor': countedCashMinor,
    'expectedCashMinor': expectedCashMinor,
    'cashSalesMinor': cashSalesMinor,
    'cashExpensesMinor': cashExpensesMinor,
    'cashSupplierPaymentsMinor': cashSupplierPaymentsMinor,
    'cashCustomerPaymentsMinor': cashCustomerPaymentsMinor,
    'differenceMinor': differenceMinor,
    'differenceKind': differenceKind.storedValue,
    'notes': notes,
    'finalizedBy': finalizedBy,
    'calculationVersion': calculationVersion,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

/// Deterministic expected physical cash for a business day.
class EndOfDayCalculator {
  const EndOfDayCalculator._();

  static int expectedCashMinor({
    required int openingCashMinor,
    required int cashSalesMinor,
    required int cashCustomerPaymentsMinor,
    required int cashExpensesMinor,
    required int cashSupplierPaymentsMinor,
  }) {
    final cashIn = cashSalesMinor + cashCustomerPaymentsMinor;
    final cashOut = cashExpensesMinor + cashSupplierPaymentsMinor;
    return openingCashMinor + cashIn - cashOut;
  }

  static int differenceMinor({
    required int countedCashMinor,
    required int expectedCashMinor,
  }) => countedCashMinor - expectedCashMinor;
}
