import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../branches/domain/business_branch.dart';
import '../../sales/domain/sale_models.dart';
import '../domain/supplier.dart';

class DuplicateSupplierException implements Exception {
  const DuplicateSupplierException(this.existing);

  final Supplier existing;
}

abstract interface class SuppliersRepository {
  Stream<List<Supplier>> watchSuppliers(String businessId, {String? branchId});
  Future<Supplier?> getSupplier(
    String businessId,
    String supplierId, {
    String? branchId,
  });
  Future<Supplier?> findByNormalizedPhone(
    String businessId,
    String phone, {
    String? branchId,
  });
  Future<String> createSupplier(
    String businessId,
    SupplierDraft draft, {
    bool allowDuplicatePhone = false,
    String? branchId,
    bool queueWhenOffline = false,
  });
  Future<void> updateSupplier(
    String businessId,
    String supplierId,
    SupplierDraft draft, {
    String? branchId,
  });
  Future<void> archiveSupplier(
    String businessId,
    String supplierId, {
    String? branchId,
  });
  Future<void> recordPayment(
    String businessId,
    String supplierId,
    int amountMinor,
    String paymentMethod,
    DateTime paymentDate,
    String? reference,
    String? note, {
    String? branchId,
  });
  Stream<List<SupplierLedgerEntry>> watchLedger(
    String businessId,
    String supplierId, {
    int limit = 25,
    String? branchId,
  });
}

class FirestoreSuppliersRepository implements SuppliersRepository {
  FirestoreSuppliersRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> _business(String businessId) =>
      _firestore.collection('businesses').doc(businessId);

  CollectionReference<Map<String, dynamic>> _suppliers(String businessId) =>
      _business(businessId).collection('suppliers');

  @override
  Stream<List<Supplier>> watchSuppliers(String businessId, {String? branchId}) {
    if (businessId.trim().isEmpty) {
      return Stream<List<Supplier>>.value(const <Supplier>[]);
    }
    return _suppliers(businessId)
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map(Supplier.fromFirestore).toList());
  }

  @override
  Future<Supplier?> getSupplier(
    String businessId,
    String supplierId, {
    String? branchId,
  }) async {
    if (businessId.trim().isEmpty || supplierId.trim().isEmpty) return null;
    final snap = await _suppliers(businessId).doc(supplierId).get();
    if (!snap.exists || snap.data() == null) return null;
    return Supplier.fromFirestore(snap);
  }

  @override
  Future<Supplier?> findByNormalizedPhone(
    String businessId,
    String phone, {
    String? branchId,
  }) async {
    final normalized = Supplier.normalizePhone(phone);
    if (businessId.trim().isEmpty || normalized.isEmpty) return null;
    final snap = await _suppliers(
      businessId,
    ).where('phoneNormalized', isEqualTo: normalized).limit(1).get();
    if (snap.docs.isNotEmpty) return Supplier.fromFirestore(snap.docs.first);

    // Supports suppliers created before phoneNormalized was stored.
    final legacy = await _suppliers(businessId).limit(200).get();
    for (final doc in legacy.docs) {
      final supplier = Supplier.fromFirestore(doc);
      if (Supplier.normalizePhone(supplier.phone) == normalized) {
        return supplier;
      }
    }
    return null;
  }

  @override
  Future<String> createSupplier(
    String businessId,
    SupplierDraft draft, {
    bool allowDuplicatePhone = false,
    String? branchId,
    bool queueWhenOffline = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const SupplierException('unauthenticated');
    if (businessId.trim().isEmpty) {
      throw const SupplierException('failed-precondition');
    }
    _validateDraft(draft);
    final phone = _nullable(draft.phone);
    if (!queueWhenOffline && !allowDuplicatePhone && phone != null) {
      final existing = await findByNormalizedPhone(businessId, phone);
      if (existing != null) throw DuplicateSupplierException(existing);
    }
    final ref = _suppliers(businessId).doc();
    try {
      await ref.set(<String, Object?>{
        'supplierId': ref.id,
        'businessId': businessId,
        ..._draftData(draft),
        'balanceMinor': 0,
        'balance': 0,
        'totalPurchasesMinor': 0,
        'totalPaidMinor': 0,
        'purchaseCount': 0,
        'status': SupplierStatus.active.name,
        'createdBy': user.uid,
        'createdByName': user.displayName ?? user.email,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return ref.id;
    } on FirebaseException catch (error) {
      throw _safeSupplierException(error, operation: 'create');
    }
  }

  @override
  Future<void> updateSupplier(
    String businessId,
    String supplierId,
    SupplierDraft draft, {
    String? branchId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const SupplierException('unauthenticated');
    _validateDraft(draft);
    await _suppliers(businessId).doc(supplierId).update(<String, Object?>{
      ..._draftData(draft),
      'updatedBy': user.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> archiveSupplier(
    String businessId,
    String supplierId, {
    String? branchId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const SupplierException('unauthenticated');
    await _suppliers(businessId).doc(supplierId).update(<String, Object?>{
      'status': SupplierStatus.archived.name,
      'updatedBy': user.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> recordPayment(
    String businessId,
    String supplierId,
    int amountMinor,
    String paymentMethod,
    DateTime paymentDate,
    String? reference,
    String? note, {
    String? branchId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const SupplierException('unauthenticated');
    final writableBranchId = _requireBranchId(branchId);
    if (amountMinor <= 0) {
      throw const SupplierException(
        'failed-precondition',
        message: 'Enter a payment amount greater than zero.',
      );
    }
    final business = _business(businessId);
    final supplierRef = _suppliers(businessId).doc(supplierId);
    final ledgerRef = supplierRef.collection('ledger').doc();
    final activityRef = business.collection('activity').doc();
    final dateKey = DateFormat('yyyyMMdd').format(paymentDate.toLocal());
    final analyticsRef = business
        .collection('analytics')
        .doc('daily_${dateKey}_$writableBranchId');

    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(supplierRef);
      if (!snapshot.exists) throw const SupplierException('not-found');
      final supplier = Supplier.fromFirestore(snapshot);
      if (amountMinor > supplier.balanceMinor) {
        throw const SupplierException(
          'failed-precondition',
          message: 'Payment cannot be greater than the outstanding balance.',
        );
      }
      final before = supplier.balanceMinor;
      final after = before - amountMinor;
      tx.update(supplierRef, <String, Object?>{
        'balanceMinor': after,
        'balance': minorToMoney(after),
        'totalPaidMinor': FieldValue.increment(amountMinor),
        'updatedBy': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(ledgerRef, <String, Object?>{
        'branchId': writableBranchId,
        'type': SupplierLedgerType.supplierPayment.storedValue,
        'debitMinor': 0,
        'creditMinor': amountMinor,
        'balanceBeforeMinor': before,
        'balanceAfterMinor': after,
        'paymentMethod': paymentMethod,
        'paymentDate': Timestamp.fromDate(paymentDate),
        'reference': _nullable(reference),
        'note': _nullable(note),
        'createdBy': user.uid,
        'createdByName': user.displayName ?? user.email,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(activityRef, <String, Object?>{
        'activityId': activityRef.id,
        'businessId': businessId,
        'branchId': writableBranchId,
        'type': 'supplierPayment',
        'title': 'Supplier payment',
        'subtitle': supplier.name,
        'amountMinor': amountMinor,
        'amount': minorToMoney(amountMinor),
        'currencyCode': 'SLE',
        'referenceId': supplier.id,
        'createdBy': user.uid,
        'createdByName': user.displayName ?? user.email,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(analyticsRef, <String, Object?>{
        'dateKey': dateKey,
        'branchId': writableBranchId,
        'supplierPaymentsMinor': FieldValue.increment(amountMinor),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  @override
  Stream<List<SupplierLedgerEntry>> watchLedger(
    String businessId,
    String supplierId, {
    int limit = 25,
    String? branchId,
  }) {
    if (businessId.trim().isEmpty || supplierId.trim().isEmpty) {
      return Stream<List<SupplierLedgerEntry>>.value(
        const <SupplierLedgerEntry>[],
      );
    }
    return _suppliers(businessId)
        .doc(supplierId)
        .collection('ledger')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .where((doc) => matchesBranchScope(doc.data(), branchId))
              .map(SupplierLedgerEntry.fromFirestore)
              .toList(),
        );
  }

  Map<String, Object?> _draftData(SupplierDraft draft) => <String, Object?>{
    'name': draft.name.trim(),
    'contactPerson': _nullable(draft.contactPerson),
    'phone': _nullable(draft.phone),
    'phoneNormalized': Supplier.normalizePhone(draft.phone),
    'email': _nullable(draft.email),
    'address': _nullable(draft.address),
    'productsSupplied': draft.productsSupplied
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(),
    'notes': _nullable(draft.notes),
  };

  String? _nullable(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  void _validateDraft(SupplierDraft draft) {
    if (draft.name.trim().length < 2) {
      throw const SupplierException(
        'failed-precondition',
        message: 'Supplier name must be at least 2 characters.',
      );
    }
    final email = draft.email?.trim() ?? '';
    if (email.isNotEmpty && !email.contains('@')) {
      throw const SupplierException(
        'failed-precondition',
        message: 'Enter a valid email address.',
      );
    }
    final phone = draft.phone?.trim() ?? '';
    if (phone.isNotEmpty && phone.replaceAll(RegExp(r'\D'), '').length < 7) {
      throw const SupplierException(
        'failed-precondition',
        message: 'Enter a valid phone number.',
      );
    }
  }

  String _requireBranchId(String? branchId) {
    final value = normalizeBranchId(branchId);
    if (value == null) {
      throw const SupplierException(
        'failed-precondition',
        message: 'Select an active branch before recording supplier activity.',
      );
    }
    return value;
  }

  SupplierException _safeSupplierException(
    FirebaseException error, {
    required String operation,
  }) {
    final requestId =
        'supplier-$operation-${DateTime.now().microsecondsSinceEpoch}';
    debugPrint(
      'Supplier $operation failed: requestId=$requestId code=${error.code}',
    );
    return SupplierException(
      error.code,
      requestId: requestId,
      message: switch (error.code) {
        'permission-denied' =>
          'You do not have permission to manage suppliers.',
        'unavailable' => 'Supplier service is temporarily unavailable.',
        'invalid-argument' => 'The supplier information is invalid.',
        _ => 'The supplier could not be saved.',
      },
    );
  }
}
