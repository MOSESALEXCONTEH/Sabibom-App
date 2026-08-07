import 'package:cloud_firestore/cloud_firestore.dart';

import '../../sales/domain/sale_models.dart';

enum SupplierStatus {
  active,
  archived;

  static SupplierStatus fromStorage(Object? value) =>
      '$value'.trim().toLowerCase() == archived.name ? archived : active;
}

class Supplier {
  const Supplier({
    required this.id,
    required this.businessId,
    required this.name,
    required this.balanceMinor,
    required this.totalPurchasesMinor,
    required this.totalPaidMinor,
    required this.purchaseCount,
    required this.status,
    this.contactPerson,
    this.phone,
    this.email,
    this.address,
    this.productsSupplied = const <String>[],
    this.lastPurchaseAt,
    this.notes,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Supplier.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return Supplier.fromMap(snapshot.id, data);
  }

  factory Supplier.fromMap(String id, Map<String, dynamic> data) {
    final balance = data['balanceMinor'] ?? data['balance'];
    return Supplier(
      id: id,
      businessId: data['businessId'] as String? ?? '',
      name: data['name'] as String? ?? 'Unnamed supplier',
      contactPerson: data['contactPerson'] as String?,
      phone: data['phone'] as String? ?? data['phoneNumber'] as String?,
      email: data['email'] as String?,
      address: data['address'] as String?,
      productsSupplied: (data['productsSupplied'] as List<Object?>? ?? const [])
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .toList(),
      balanceMinor: balance is int ? balance : moneyToMinor(balance),
      totalPurchasesMinor:
          (data['totalPurchasesMinor'] as num?)?.toInt() ??
          moneyToMinor(data['totalPurchases']),
      totalPaidMinor:
          (data['totalPaidMinor'] as num?)?.toInt() ??
          moneyToMinor(data['totalPaid']),
      purchaseCount: (data['purchaseCount'] as num?)?.toInt() ?? 0,
      lastPurchaseAt: (data['lastPurchaseAt'] as Timestamp?)?.toDate(),
      notes: data['notes'] as String?,
      status: SupplierStatus.fromStorage(data['status']),
      createdBy: data['createdBy'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String businessId;
  final String name;
  final String? contactPerson;
  final String? phone;
  final String? email;
  final String? address;
  final List<String> productsSupplied;
  final int balanceMinor;
  final int totalPurchasesMinor;
  final int totalPaidMinor;
  final int purchaseCount;
  final DateTime? lastPurchaseAt;
  final String? notes;
  final SupplierStatus status;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == SupplierStatus.active;
  bool get isArchived => status == SupplierStatus.archived;
  bool get hasBalance => balanceMinor > 0;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  static String normalizePhone(String? phone) {
    if (phone == null) return '';
    return phone.replaceAll(RegExp(r'[^\d+]'), '');
  }
}

class SupplierDraft {
  const SupplierDraft({
    required this.name,
    this.contactPerson,
    this.phone,
    this.email,
    this.address,
    this.productsSupplied = const <String>[],
    this.notes,
  });

  final String name;
  final String? contactPerson;
  final String? phone;
  final String? email;
  final String? address;
  final List<String> productsSupplied;
  final String? notes;
}

class SupplierException implements Exception {
  const SupplierException(this.code, {this.message, this.requestId});

  final String code;
  final String? message;
  final String? requestId;

  String get userMessage {
    final safeMessage =
        message ??
        switch (code) {
          'permission-denied' =>
            'You do not have permission to access this business information.',
          'unavailable' => 'This information is temporarily unavailable.',
          'not-found' => 'This supplier could not be found.',
          'failed-precondition' => 'This action cannot be completed.',
          'unauthenticated' => 'Your session expired. Please sign in again.',
          _ => 'Something went wrong. Please try again.',
        };
    return requestId == null ? safeMessage : '$safeMessage Ref: $requestId';
  }
}

enum SupplierLedgerType {
  purchaseCredit,
  supplierPayment,
  openingBalance,
  adjustment;

  String get storedValue => switch (this) {
    purchaseCredit => 'purchase_credit',
    supplierPayment => 'supplier_payment',
    openingBalance => 'opening_balance',
    adjustment => 'adjustment',
  };

  String get label => switch (this) {
    purchaseCredit => 'Purchase credit',
    supplierPayment => 'Supplier payment',
    openingBalance => 'Opening balance',
    adjustment => 'Adjustment',
  };

  static SupplierLedgerType fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return values.firstWhere(
      (type) => type.storedValue == raw || type.name == raw,
      orElse: () => adjustment,
    );
  }
}

class SupplierLedgerEntry {
  const SupplierLedgerEntry({
    required this.id,
    required this.type,
    required this.debitMinor,
    required this.creditMinor,
    required this.balanceAfterMinor,
    this.balanceBeforeMinor,
    this.purchaseId,
    this.paymentMethod,
    this.reference,
    this.note,
    this.paymentDate,
    this.createdBy,
    this.createdAt,
  });

  factory SupplierLedgerEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return SupplierLedgerEntry(
      id: snapshot.id,
      type: SupplierLedgerType.fromStorage(data['type']),
      debitMinor: (data['debitMinor'] as num?)?.toInt() ?? 0,
      creditMinor: (data['creditMinor'] as num?)?.toInt() ?? 0,
      balanceBeforeMinor: (data['balanceBeforeMinor'] as num?)?.toInt(),
      balanceAfterMinor: (data['balanceAfterMinor'] as num?)?.toInt() ?? 0,
      purchaseId: data['purchaseId'] as String?,
      paymentMethod: data['paymentMethod'] as String?,
      reference: data['reference'] as String?,
      note: data['note'] as String?,
      paymentDate: (data['paymentDate'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final SupplierLedgerType type;
  final int debitMinor;
  final int creditMinor;
  final int? balanceBeforeMinor;
  final int balanceAfterMinor;
  final String? purchaseId;
  final String? paymentMethod;
  final String? reference;
  final String? note;
  final DateTime? paymentDate;
  final String? createdBy;
  final DateTime? createdAt;
}

enum SupplierListFilter { all, active, hasBalance, archived }
