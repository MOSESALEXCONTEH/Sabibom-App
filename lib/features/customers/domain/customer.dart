import 'package:cloud_firestore/cloud_firestore.dart';

import '../../sales/domain/sale_models.dart';

enum CustomerStatus {
  active,
  archived;

  static CustomerStatus fromStorage(Object? value) {
    final raw = '$value'.trim().toLowerCase();
    return raw == CustomerStatus.archived.name
        ? CustomerStatus.archived
        : CustomerStatus.active;
  }
}

class Customer {
  const Customer({
    required this.id,
    required this.businessId,
    required this.name,
    required this.balanceMinor,
    required this.totalSalesMinor,
    required this.totalPaidMinor,
    required this.purchaseCount,
    required this.status,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.usesWhatsApp = false,
    this.lastPurchaseAt,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory Customer.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final storedId = (data['customerId'] as String?)?.trim();
    final id = snapshot.id.trim().isNotEmpty ? snapshot.id : (storedId ?? '');
    return Customer.fromMap(id, data);
  }

  factory Customer.fromMap(String id, Map<String, dynamic> data) {
    final balance = data['balanceMinor'] ?? data['balance'];
    return Customer(
      id: id,
      businessId: data['businessId'] as String? ?? '',
      name: data['name'] as String? ?? 'Unnamed customer',
      phone: data['phone'] as String? ?? data['phoneNumber'] as String?,
      email: data['email'] as String?,
      address: data['address'] as String?,
      notes: data['notes'] as String?,
      usesWhatsApp: data['usesWhatsApp'] as bool? ?? false,
      balanceMinor: balance is int ? balance : moneyToMinor(balance),
      totalSalesMinor:
          (data['totalSalesMinor'] as num?)?.toInt() ??
          moneyToMinor(data['totalSales']),
      totalPaidMinor:
          (data['totalPaidMinor'] as num?)?.toInt() ??
          moneyToMinor(data['totalPaid']),
      purchaseCount: (data['purchaseCount'] as num?)?.toInt() ?? 0,
      lastPurchaseAt: (data['lastPurchaseAt'] as Timestamp?)?.toDate(),
      status: CustomerStatus.fromStorage(data['status']),
      createdBy: data['createdBy'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String businessId;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final bool usesWhatsApp;
  final int balanceMinor;
  final int totalSalesMinor;
  final int totalPaidMinor;
  final int purchaseCount;
  final DateTime? lastPurchaseAt;
  final CustomerStatus status;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == CustomerStatus.active;
  bool get isArchived => status == CustomerStatus.archived;
  bool get hasBalance => balanceMinor > 0;
  bool get hasPhone => (phone ?? '').trim().isNotEmpty;

  bool get showWhatsAppBadge => hasPhone && usesWhatsApp;

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

enum CustomerListFilter { all, active, hasBalance, noBalance, archived }
