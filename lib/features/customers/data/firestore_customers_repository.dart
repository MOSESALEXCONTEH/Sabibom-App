import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/firestore/query_pagination.dart';
import '../../branches/domain/business_branch.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/sale_models.dart';
import '../domain/customer.dart';
import '../domain/customer_ledger_entry.dart';
import 'customers_repository.dart';

class FirestoreCustomersRepository implements CustomersRepository {
  FirestoreCustomersRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _customers(String businessId) =>
      _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('customers');

  CollectionReference<Map<String, dynamic>> _activity(String businessId) =>
      _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('activity');

  @override
  Stream<List<Customer>> watchCustomers(String businessId, {String? branchId}) {
    if (businessId.trim().isEmpty) {
      return Stream<List<Customer>>.value(const <Customer>[]);
    }
    return _customers(businessId)
        .orderBy('name')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => matchesBranchScope(doc.data(), branchId))
              .map(Customer.fromFirestore)
              .toList(),
        );
  }

  @override
  Future<Customer?> getCustomer(
    String businessId,
    String customerId, {
    String? branchId,
  }) async {
    if (businessId.trim().isEmpty || customerId.trim().isEmpty) return null;
    final snapshot = await _customers(businessId).doc(customerId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    if (!matchesBranchScope(data, branchId)) return null;
    return Customer.fromFirestore(snapshot);
  }

  @override
  Future<Customer?> findByNormalizedPhone(
    String businessId,
    String phone, {
    String? branchId,
  }) async {
    final normalized = Customer.normalizePhone(phone);
    if (normalized.isEmpty) return null;
    final documents = await readAllQueryPages(_customers(businessId));
    for (final doc in documents) {
      final customer = Customer.fromFirestore(doc);
      if (matchesBranchScope(doc.data(), branchId) &&
          Customer.normalizePhone(customer.phone) == normalized) {
        return customer;
      }
    }
    return null;
  }

  @override
  Future<String> createCustomer(
    String businessId,
    CustomerDraft draft, {
    bool allowDuplicatePhone = false,
    String? branchId,
    bool queueWhenOffline = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const CustomerException('unauthenticated');
    _validateDraft(draft);
    final writableBranchId = _requireBranchId(branchId);

    final phone = draft.phone?.trim();
    if (queueWhenOffline &&
        !allowDuplicatePhone &&
        phone != null &&
        phone.isNotEmpty) {
      try {
        final cached = await _customers(businessId)
            .where('phoneNormalized', isEqualTo: Customer.normalizePhone(phone))
            .get(const GetOptions(source: Source.cache));
        for (final document in cached.docs) {
          if (matchesBranchScope(document.data(), writableBranchId)) {
            throw DuplicateCustomerException(Customer.fromFirestore(document));
          }
        }
      } on FirebaseException {
        // No cached index is available. The write can still be safely queued.
      }
    }
    if (!queueWhenOffline &&
        !allowDuplicatePhone &&
        phone != null &&
        phone.isNotEmpty) {
      final existing = await findByNormalizedPhone(
        businessId,
        phone,
        branchId: writableBranchId,
      );
      if (existing != null) {
        throw DuplicateCustomerException(existing);
      }
    }

    if (!queueWhenOffline) {
      final branchSnapshot = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('branches')
          .doc(writableBranchId)
          .get();
      if (!branchSnapshot.exists ||
          branchSnapshot.data()?['status'] != 'active') {
        throw const CustomerException(
          'failed-precondition',
          message: 'This branch is inactive and cannot create customers.',
        );
      }
    }

    final reference = _customers(businessId).doc();
    await reference.set(<String, Object?>{
      'customerId': reference.id,
      'businessId': businessId,
      'branchId': writableBranchId,
      'name': draft.name.trim(),
      'phone': phone?.isEmpty == true ? null : phone,
      'phoneNormalized': Customer.normalizePhone(phone),
      'email': draft.email?.trim().isEmpty == true ? null : draft.email?.trim(),
      'address': draft.address?.trim().isEmpty == true
          ? null
          : draft.address?.trim(),
      'notes': draft.notes?.trim().isEmpty == true ? null : draft.notes?.trim(),
      'photoUrl': draft.photoUrl,
      'photoCid': draft.photoCid,
      'usesWhatsApp': draft.usesWhatsApp,
      'balanceMinor': 0,
      'balance': 0,
      'totalSalesMinor': 0,
      'totalPaidMinor': 0,
      'purchaseCount': 0,
      'status': CustomerStatus.active.name,
      'createdBy': user.uid,
      'createdByName': user.displayName ?? user.email,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return reference.id;
  }

  @override
  Future<void> updateCustomer(
    String businessId,
    String customerId,
    CustomerDraft draft, {
    String? branchId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const CustomerException('unauthenticated');
    _validateDraft(draft);
    final phone = draft.phone?.trim();
    await _customers(businessId).doc(customerId).update(<String, Object?>{
      'name': draft.name.trim(),
      'phone': phone?.isEmpty == true ? null : phone,
      'phoneNormalized': Customer.normalizePhone(phone),
      'email': draft.email?.trim().isEmpty == true ? null : draft.email?.trim(),
      'address': draft.address?.trim().isEmpty == true
          ? null
          : draft.address?.trim(),
      'notes': draft.notes?.trim().isEmpty == true ? null : draft.notes?.trim(),
      'photoUrl': draft.photoUrl,
      'photoCid': draft.photoCid,
      'usesWhatsApp': draft.usesWhatsApp,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });
  }

  @override
  Future<void> setCustomerStatus(
    String businessId,
    String customerId,
    CustomerStatus status, {
    String? branchId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const CustomerException('unauthenticated');
    await _customers(businessId).doc(customerId).update(<String, Object?>{
      'status': status.name,
      'branchId': normalizeBranchId(branchId),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    });
  }

  @override
  Future<void> recordPayment(
    String businessId,
    CustomerPaymentRequest request, {
    String? branchId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const CustomerException('unauthenticated');
    final writableBranchId = _requireBranchId(branchId);
    if (request.amountMinor <= 0) {
      throw const CustomerException(
        'failed-precondition',
        message: 'Enter a payment amount greater than zero.',
      );
    }

    final customerRef = _customers(businessId).doc(request.customerId);
    final businessRef = _firestore.collection('businesses').doc(businessId);
    final branchRef = _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('branches')
        .doc(writableBranchId);
    final ledgerRef = customerRef.collection('ledger').doc();
    final activityRef = _activity(businessId).doc();

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(customerRef);
      final branchSnapshot = await transaction.get(branchRef);
      final businessSnapshot = await transaction.get(businessRef);
      if (!snapshot.exists) throw const CustomerException('not-found');
      if (!branchSnapshot.exists ||
          branchSnapshot.data()?['status'] != 'active') {
        throw const CustomerException(
          'failed-precondition',
          message: 'This branch is inactive and cannot receive payments.',
        );
      }
      final customer = Customer.fromFirestore(snapshot);
      final currencyCode =
          businessSnapshot.data()?['currencyCode'] as String? ?? 'SLE';
      if (request.amountMinor > customer.balanceMinor) {
        throw const CustomerException(
          'failed-precondition',
          message: 'Payment cannot be greater than the outstanding balance.',
        );
      }

      final before = customer.balanceMinor;
      final after = before - request.amountMinor;
      transaction.update(customerRef, <String, Object?>{
        'branchId': writableBranchId,
        'balanceMinor': after,
        'balance': minorToMoney(after),
        'totalPaidMinor': FieldValue.increment(request.amountMinor),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
      });
      transaction.set(ledgerRef, <String, Object?>{
        'type': CustomerLedgerType.customerPayment.storedValue,
        'saleId': null,
        'receiptNumber': null,
        'debitMinor': 0,
        'creditMinor': request.amountMinor,
        'branchId': writableBranchId,
        'balanceBeforeMinor': before,
        'balanceAfterMinor': after,
        'paymentMethod': request.paymentMethod,
        'note': request.note?.trim().isEmpty == true
            ? request.reference
            : request.note?.trim(),
        'reference': request.reference,
        'createdBy': user.uid,
        'createdByName': user.displayName ?? user.email,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(activityRef, <String, Object?>{
        'activityId': activityRef.id,
        'businessId': businessId,
        'type': 'customerPayment',
        'title': 'Customer payment',
        'subtitle': customer.name,
        'amount': minorToMoney(request.amountMinor),
        'amountMinor': request.amountMinor,
        'branchId': writableBranchId,
        'currencyCode': currencyCode,
        'referenceId': customer.id,
        'createdBy': user.uid,
        'createdByName': user.displayName ?? user.email,
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Stream<List<CustomerLedgerEntry>> watchLedger(
    String businessId,
    String customerId, {
    String? branchId,
    int limit = 25,
  }) {
    if (businessId.trim().isEmpty || customerId.trim().isEmpty) {
      return Stream<List<CustomerLedgerEntry>>.value(
        const <CustomerLedgerEntry>[],
      );
    }
    return _customers(businessId)
        .doc(customerId)
        .collection('ledger')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => matchesBranchScope(doc.data(), branchId))
              .map(CustomerLedgerEntry.fromFirestore)
              .toList(),
        );
  }

  @override
  Stream<List<SaleHistoryItem>> watchCustomerSales(
    String businessId,
    String customerId, {
    String? branchId,
    int limit = 20,
  }) {
    if (businessId.trim().isEmpty || customerId.trim().isEmpty) {
      return Stream<List<SaleHistoryItem>>.value(const <SaleHistoryItem>[]);
    }
    return _firestore
        .collection('businesses')
        .doc(businessId)
        .collection('sales')
        .where('customerId', isEqualTo: customerId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => matchesBranchScope(doc.data(), branchId))
              .map((doc) => SaleHistoryItem.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  String _requireBranchId(String? branchId) {
    final value = normalizeBranchId(branchId);
    if (value == null || value == 'all' || value == 'all_branches') {
      throw const CustomerException(
        'failed-precondition',
        message: 'Switch to a single active branch before saving this record.',
      );
    }
    return value;
  }

  void _validateDraft(CustomerDraft draft) {
    if (draft.name.trim().length < 2) {
      throw const CustomerException(
        'failed-precondition',
        message: 'Customer name must be at least 2 characters.',
      );
    }
    final email = draft.email?.trim() ?? '';
    if (email.isNotEmpty && !email.contains('@')) {
      throw const CustomerException(
        'failed-precondition',
        message: 'Enter a valid email address.',
      );
    }
    final phone = draft.phone?.trim() ?? '';
    if (phone.isNotEmpty && phone.replaceAll(RegExp(r'\D'), '').length < 7) {
      throw const CustomerException(
        'failed-precondition',
        message: 'Enter a valid phone number.',
      );
    }
  }
}
