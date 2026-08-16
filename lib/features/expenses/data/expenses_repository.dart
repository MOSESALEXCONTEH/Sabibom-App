import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/firestore/query_pagination.dart';
import 'package:intl/intl.dart';

import '../../branches/domain/business_branch.dart';
import '../../notifications/application/operational_alert_service.dart';
import '../../sales/domain/sale_models.dart';
import '../domain/expense.dart';

abstract class ExpensesRepository {
  Stream<List<Expense>> watchExpenses(
    String businessId, {
    DateTime? start,
    DateTime? end,
    String? branchId,
    int limit = 100,
  });
  Future<Expense?> getExpense(
    String businessId,
    String expenseId, {
    String? branchId,
  });
  Future<String> createExpense(
    String businessId,
    ExpenseDraft draft, {
    String? branchId,
    bool queueWhenOffline = false,
  });
  Future<void> updateExpense(
    String businessId,
    String expenseId,
    ExpenseDraft draft, {
    String? branchId,
  });
  Future<void> voidExpense(
    String businessId,
    String expenseId, {
    required String reason,
    String? branchId,
  });
  Future<int> totalActiveMinor(
    String businessId, {
    DateTime? start,
    DateTime? end,
    String? branchId,
  });
}

class FirestoreExpensesRepository implements ExpensesRepository {
  FirestoreExpensesRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _expenses(String businessId) =>
      _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('expenses');

  DocumentReference<Map<String, dynamic>> _business(String businessId) =>
      _firestore.collection('businesses').doc(businessId);

  void _validateDraft(ExpenseDraft draft) {
    if (draft.amountMinor <= 0) {
      throw const ExpenseException(
        'failed-precondition',
        message: 'Amount must be greater than zero.',
      );
    }
    if (draft.categoryId.trim().isEmpty) {
      throw const ExpenseException(
        'failed-precondition',
        message: 'Select a category.',
      );
    }
    if (draft.description.trim().length < 2) {
      throw const ExpenseException(
        'failed-precondition',
        message: 'Description must be at least 2 characters.',
      );
    }
  }

  Map<String, Object?> _draftMap(
    ExpenseDraft draft, {
    required String businessId,
    required String expenseNumber,
    required String uid,
    required String? displayName,
    String? branchId,
    bool includeCreate = true,
  }) {
    return <String, Object?>{
      'businessId': businessId,
      'branchId': normalizeBranchId(branchId),
      'expenseNumber': expenseNumber,
      'categoryId': draft.categoryId,
      'categoryName': draft.categoryName,
      'amountMinor': draft.amountMinor,
      'amount': minorToMoney(draft.amountMinor),
      'currencyCode': draft.currencyCode,
      'description': draft.description.trim(),
      'paymentMethod': draft.paymentMethod.storedValue,
      'paymentReference': draft.paymentReference?.trim().isEmpty == true
          ? null
          : draft.paymentReference?.trim(),
      'supplierId': draft.supplierId,
      'supplierName': draft.supplierName,
      'expenseDate': Timestamp.fromDate(draft.expenseDate),
      'attachmentUrl': draft.attachmentUrl,
      'attachmentCid': draft.attachmentCid,
      'attachmentFileName': draft.attachmentFileName,
      'notes': draft.notes?.trim().isEmpty == true ? null : draft.notes?.trim(),
      'status': ExpenseStatus.active.storedValue,
      if (includeCreate) 'createdBy': uid,
      if (includeCreate) 'createdByName': displayName,
      if (includeCreate) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  @override
  Stream<List<Expense>> watchExpenses(
    String businessId, {
    DateTime? start,
    DateTime? end,
    String? branchId,
    int limit = 100,
  }) {
    if (businessId.trim().isEmpty) {
      return Stream.value(const <Expense>[]);
    }
    Query<Map<String, dynamic>> query = _expenses(
      businessId,
    ).orderBy('expenseDate', descending: true);
    if (start != null) {
      query = query.where(
        'expenseDate',
        isGreaterThanOrEqualTo: Timestamp.fromDate(start),
      );
    }
    if (end != null) {
      query = query.where('expenseDate', isLessThan: Timestamp.fromDate(end));
    }
    return query
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .where((doc) => matchesBranchScope(doc.data(), branchId))
              .map(Expense.fromFirestore)
              .toList(),
        );
  }

  @override
  Future<Expense?> getExpense(
    String businessId,
    String expenseId, {
    String? branchId,
  }) async {
    if (businessId.trim().isEmpty || expenseId.trim().isEmpty) return null;
    final snap = await _expenses(businessId).doc(expenseId).get();
    if (!snap.exists) return null;
    if (!matchesBranchScope(
      snap.data() ?? const <String, dynamic>{},
      branchId,
    )) {
      return null;
    }
    return Expense.fromFirestore(snap);
  }

  @override
  Future<String> createExpense(
    String businessId,
    ExpenseDraft draft, {
    String? branchId,
    bool queueWhenOffline = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const ExpenseException('unauthenticated');
    if (businessId.trim().isEmpty) {
      throw const ExpenseException('failed-precondition');
    }
    _validateDraft(draft);
    final writableBranchId = _requireBranchId(branchId);
    if (queueWhenOffline) {
      return _createExpenseOffline(
        businessId: businessId,
        draft: draft,
        branchId: writableBranchId,
        user: user,
      );
    }

    final business = _business(businessId);
    final expenseRef = _expenses(businessId).doc();
    final counter = business
        .collection('counters')
        .doc('expenses_$writableBranchId');
    final activity = business.collection('activity').doc();
    final dateKey = DateFormat('yyyyMMdd').format(draft.expenseDate.toLocal());
    final analytics = business
        .collection('analytics')
        .doc('daily_${dateKey}_$writableBranchId');

    try {
      await _firestore.runTransaction((tx) async {
        final businessSnap = await tx.get(business);
        if (!businessSnap.exists) {
          throw const ExpenseException('not-found');
        }
        final counterSnap = await tx.get(counter);
        final next =
            ((counterSnap.data()?['nextNumber'] as num?)?.toInt() ?? 1);
        final number = formatExpenseNumber(dateKey, next);

        tx.set(counter, <String, Object?>{
          'businessId': businessId,
          'branchId': writableBranchId,
          'nextNumber': next + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        tx.set(
          expenseRef,
          _draftMap(
            draft,
            businessId: businessId,
            expenseNumber: number,
            uid: user.uid,
            displayName: user.displayName,
            branchId: writableBranchId,
          ),
        );

        tx.set(analytics, <String, Object?>{
          'dateKey': dateKey,
          'branchId': writableBranchId,
          'expenseMinor': FieldValue.increment(draft.amountMinor),
          'expenseCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        tx.set(activity, <String, Object?>{
          'businessId': businessId,
          'branchId': writableBranchId,
          'type': 'expense',
          'title': 'Expense recorded',
          'subtitle': '${draft.categoryName}: ${draft.description.trim()}',
          'amountMinor': draft.amountMinor,
          'referenceId': expenseRef.id,
          'createdBy': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      try {
        final bizSnap = await business.get();
        await OperationalAlertService().onLargeExpense(
          businessId: businessId,
          businessName: (bizSnap.data()?['name'] as String?) ?? 'Business',
          branchId: writableBranchId,
          expenseId: expenseRef.id,
          categoryName: draft.categoryName,
          amountMinor: draft.amountMinor,
          recordedBy: user.displayName ?? user.uid,
        );
      } catch (_) {}

      return expenseRef.id;
    } on ExpenseException {
      rethrow;
    } on FirebaseException catch (e) {
      throw ExpenseException(e.code, message: e.message);
    }
  }

  Future<String> _createExpenseOffline({
    required String businessId,
    required ExpenseDraft draft,
    required String branchId,
    required User user,
  }) async {
    final business = _business(businessId);
    final expenseRef = _expenses(businessId).doc();
    final activity = business.collection('activity').doc();
    final localNow = DateTime.now();
    final dateKey = DateFormat('yyyyMMdd').format(draft.expenseDate.toLocal());
    final analytics = business
        .collection('analytics')
        .doc('daily_${dateKey}_$branchId');
    final expenseNumber =
        'EXP-OFFLINE-${DateFormat('yyyyMMddHHmmss').format(localNow)}';
    final batch = _firestore.batch();
    batch.set(
      expenseRef,
      _draftMap(
        draft,
        businessId: businessId,
        expenseNumber: expenseNumber,
        uid: user.uid,
        displayName: user.displayName ?? user.email,
        branchId: branchId,
      ),
    );
    batch.set(analytics, <String, Object?>{
      'dateKey': dateKey,
      'branchId': branchId,
      'expenseMinor': FieldValue.increment(draft.amountMinor),
      'expenseCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(activity, <String, Object?>{
      'businessId': businessId,
      'branchId': branchId,
      'type': 'expense',
      'title': 'Expense recorded',
      'subtitle': '${draft.categoryName}: ${draft.description.trim()}',
      'amountMinor': draft.amountMinor,
      'referenceId': expenseRef.id,
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return expenseRef.id;
  }

  @override
  Future<void> updateExpense(
    String businessId,
    String expenseId,
    ExpenseDraft draft, {
    String? branchId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const ExpenseException('unauthenticated');
    _validateDraft(draft);
    final writableBranchId = _requireBranchId(branchId);

    final expenseRef = _expenses(businessId).doc(expenseId);
    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(expenseRef);
        if (!snap.exists) throw const ExpenseException('not-found');
        final data = snap.data()!;
        if (!matchesBranchScope(data, writableBranchId)) {
          throw const ExpenseException('not-found');
        }
        final status = ExpenseStatus.fromStorage(data['status']);
        if (status == ExpenseStatus.voided) {
          throw const ExpenseException(
            'failed-precondition',
            message: 'Cannot edit a voided expense.',
          );
        }
        final oldMinor =
            (data['amountMinor'] as num?)?.toInt() ??
            moneyToMinor(data['amount']);
        final oldDate =
            (data['expenseDate'] as Timestamp?)?.toDate() ?? DateTime.now();
        final oldKey = DateFormat('yyyyMMdd').format(oldDate.toLocal());
        final newKey = DateFormat(
          'yyyyMMdd',
        ).format(draft.expenseDate.toLocal());
        final business = _business(businessId);

        tx.update(expenseRef, <String, Object?>{
          'categoryId': draft.categoryId,
          'categoryName': draft.categoryName,
          'amountMinor': draft.amountMinor,
          'amount': minorToMoney(draft.amountMinor),
          'currencyCode': draft.currencyCode,
          'description': draft.description.trim(),
          'branchId': writableBranchId,
          'paymentMethod': draft.paymentMethod.storedValue,
          'paymentReference': draft.paymentReference?.trim().isEmpty == true
              ? null
              : draft.paymentReference?.trim(),
          'supplierId': draft.supplierId,
          'supplierName': draft.supplierName,
          'expenseDate': Timestamp.fromDate(draft.expenseDate),
          'attachmentUrl': draft.attachmentUrl,
          'attachmentCid': draft.attachmentCid,
          'attachmentFileName': draft.attachmentFileName,
          'notes': draft.notes?.trim().isEmpty == true
              ? null
              : draft.notes?.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': user.uid,
          'updatedByName': user.displayName ?? user.email,
        });

        if (oldKey == newKey) {
          final delta = draft.amountMinor - oldMinor;
          if (delta != 0) {
            tx.set(
              business
                  .collection('analytics')
                  .doc('daily_${oldKey}_$writableBranchId'),
              {
                'dateKey': oldKey,
                'branchId': writableBranchId,
                'expenseMinor': FieldValue.increment(delta),
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          }
        } else {
          tx.set(
            business
                .collection('analytics')
                .doc('daily_${oldKey}_$writableBranchId'),
            {
              'dateKey': oldKey,
              'branchId': writableBranchId,
              'expenseMinor': FieldValue.increment(-oldMinor),
              'expenseCount': FieldValue.increment(-1),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          tx.set(
            business
                .collection('analytics')
                .doc('daily_${newKey}_$writableBranchId'),
            {
              'dateKey': newKey,
              'branchId': writableBranchId,
              'expenseMinor': FieldValue.increment(draft.amountMinor),
              'expenseCount': FieldValue.increment(1),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      });
    } on ExpenseException {
      rethrow;
    } on FirebaseException catch (e) {
      throw ExpenseException(e.code, message: e.message);
    }
  }

  @override
  Future<void> voidExpense(
    String businessId,
    String expenseId, {
    required String reason,
    String? branchId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const ExpenseException('unauthenticated');
    final writableBranchId = _requireBranchId(branchId);
    final trimmed = reason.trim();
    if (trimmed.length < 2) {
      throw const ExpenseException(
        'failed-precondition',
        message: 'Enter a void reason.',
      );
    }

    final business = _business(businessId);
    final expenseRef = _expenses(businessId).doc(expenseId);
    final activity = business.collection('activity').doc();

    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(expenseRef);
        if (!snap.exists) throw const ExpenseException('not-found');
        final data = snap.data()!;
        if (!matchesBranchScope(data, writableBranchId)) {
          throw const ExpenseException('not-found');
        }
        final status = ExpenseStatus.fromStorage(data['status']);
        if (status == ExpenseStatus.voided) {
          throw const ExpenseException('already-voided');
        }
        final amountMinor =
            (data['amountMinor'] as num?)?.toInt() ??
            moneyToMinor(data['amount']);
        final expenseDate =
            (data['expenseDate'] as Timestamp?)?.toDate() ?? DateTime.now();
        final dateKey = DateFormat('yyyyMMdd').format(expenseDate.toLocal());

        tx.update(expenseRef, <String, Object?>{
          'status': ExpenseStatus.voided.storedValue,
          'branchId': writableBranchId,
          'voidReason': trimmed,
          'voidedBy': user.uid,
          'voidedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        tx.set(
          business
              .collection('analytics')
              .doc('daily_${dateKey}_$writableBranchId'),
          {
            'dateKey': dateKey,
            'branchId': writableBranchId,
            'expenseMinor': FieldValue.increment(-amountMinor),
            'expenseCount': FieldValue.increment(-1),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        tx.set(activity, <String, Object?>{
          'businessId': businessId,
          'branchId': writableBranchId,
          'type': 'expense',
          'title': 'Expense voided',
          'subtitle': trimmed,
          'amountMinor': amountMinor,
          'referenceId': expenseId,
          'createdBy': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
    } on ExpenseException {
      rethrow;
    } on FirebaseException catch (e) {
      throw ExpenseException(e.code, message: e.message);
    }
  }

  @override
  Future<int> totalActiveMinor(
    String businessId, {
    DateTime? start,
    DateTime? end,
    String? branchId,
  }) async {
    if (businessId.trim().isEmpty) return 0;
    Query<Map<String, dynamic>> query = _expenses(businessId);
    if (start != null) {
      query = query.where(
        'expenseDate',
        isGreaterThanOrEqualTo: Timestamp.fromDate(start),
      );
    }
    if (end != null) {
      query = query.where('expenseDate', isLessThan: Timestamp.fromDate(end));
    }
    final documents = await readAllQueryPages(query);
    var total = 0;
    for (final doc in documents) {
      if (!matchesBranchScope(doc.data(), branchId)) continue;
      final expense = Expense.fromFirestore(doc);
      if (expense.isVoided) continue;
      total += expense.amountMinor;
    }
    return total;
  }

  String _requireBranchId(String? branchId) {
    final value = normalizeBranchId(branchId);
    if (value == null) {
      throw const ExpenseException(
        'failed-precondition',
        message: 'Select an active branch before saving the expense.',
      );
    }
    return value;
  }
}
