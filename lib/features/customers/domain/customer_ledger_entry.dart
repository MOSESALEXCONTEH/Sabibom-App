import 'package:cloud_firestore/cloud_firestore.dart';

enum CustomerLedgerType {
  saleCredit,
  customerPayment,
  creditReversal,
  openingBalance,
  adjustment;

  String get storedValue => switch (this) {
    CustomerLedgerType.saleCredit => 'sale_credit',
    CustomerLedgerType.customerPayment => 'customer_payment',
    CustomerLedgerType.creditReversal => 'credit_reversal',
    CustomerLedgerType.openingBalance => 'opening_balance',
    CustomerLedgerType.adjustment => 'adjustment',
  };

  String get label => switch (this) {
    CustomerLedgerType.saleCredit => 'Sale credit',
    CustomerLedgerType.customerPayment => 'Customer payment',
    CustomerLedgerType.creditReversal => 'Credit reversal',
    CustomerLedgerType.openingBalance => 'Opening balance',
    CustomerLedgerType.adjustment => 'Adjustment',
  };

  static CustomerLedgerType fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return CustomerLedgerType.values.firstWhere(
      (type) => type.storedValue == raw || type.name == raw,
      orElse: () => CustomerLedgerType.adjustment,
    );
  }
}

class CustomerLedgerEntry {
  const CustomerLedgerEntry({
    required this.id,
    required this.type,
    required this.debitMinor,
    required this.creditMinor,
    required this.balanceAfterMinor,
    this.saleId,
    this.receiptNumber,
    this.balanceBeforeMinor,
    this.paymentMethod,
    this.note,
    this.createdBy,
    this.createdAt,
  });

  factory CustomerLedgerEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return CustomerLedgerEntry(
      id: snapshot.id,
      type: CustomerLedgerType.fromStorage(data['type']),
      saleId: data['saleId'] as String?,
      receiptNumber: data['receiptNumber'] as String?,
      debitMinor: (data['debitMinor'] as num?)?.toInt() ?? 0,
      creditMinor: (data['creditMinor'] as num?)?.toInt() ?? 0,
      balanceBeforeMinor: (data['balanceBeforeMinor'] as num?)?.toInt(),
      balanceAfterMinor: (data['balanceAfterMinor'] as num?)?.toInt() ?? 0,
      paymentMethod: data['paymentMethod'] as String?,
      note: data['note'] as String?,
      createdBy: data['createdBy'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final CustomerLedgerType type;
  final String? saleId;
  final String? receiptNumber;
  final int debitMinor;
  final int creditMinor;
  final int? balanceBeforeMinor;
  final int balanceAfterMinor;
  final String? paymentMethod;
  final String? note;
  final String? createdBy;
  final DateTime? createdAt;
}
