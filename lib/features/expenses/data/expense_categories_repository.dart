import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/expense.dart';
import '../domain/expense_category.dart';

abstract class ExpenseCategoriesRepository {
  Stream<List<ExpenseCategory>> watchCategories(
    String businessId, {
    bool includeInactive = false,
  });
  Future<void> ensureDefaults(String businessId);
  Future<String> createCategory(
    String businessId, {
    required String name,
    String iconName,
    String? description,
  });
  Future<void> updateCategory(
    String businessId,
    String categoryId, {
    required String name,
    String iconName,
    String? description,
  });
  Future<void> setActive(
    String businessId,
    String categoryId, {
    required bool isActive,
  });

  /// Permanently deletes a non-system expense category.
  Future<void> deleteCategory(String businessId, String categoryId);
}

class FirestoreExpenseCategoriesRepository
    implements ExpenseCategoriesRepository {
  FirestoreExpenseCategoriesRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _col(String businessId) =>
      _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('expense_categories');

  @override
  Stream<List<ExpenseCategory>> watchCategories(
    String businessId, {
    bool includeInactive = false,
  }) {
    if (businessId.trim().isEmpty) {
      return Stream.value(const <ExpenseCategory>[]);
    }
    return _col(businessId).orderBy('name').snapshots().map((snap) {
      final list = snap.docs.map(ExpenseCategory.fromFirestore).toList();
      if (includeInactive) return list;
      return list.where((c) => c.isActive).toList();
    });
  }

  @override
  Future<void> ensureDefaults(String businessId) async {
    if (businessId.trim().isEmpty) return;
    final user = _auth.currentUser;
    if (user == null) throw const ExpenseException('unauthenticated');

    final existing = await _col(businessId).limit(1).get();
    if (existing.docs.isNotEmpty) return;

    final batch = _firestore.batch();
    for (final def in ExpenseCategory.defaultCategories) {
      final ref = _col(businessId).doc();
      batch.set(ref, <String, Object?>{
        'businessId': businessId,
        'name': def.name,
        'iconName': def.iconName,
        'description': null,
        'isSystemCategory': true,
        'isActive': true,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  @override
  Future<String> createCategory(
    String businessId, {
    required String name,
    String iconName = 'payments',
    String? description,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const ExpenseException('unauthenticated');
    final trimmed = name.trim();
    if (trimmed.length < 2) {
      throw const ExpenseException(
        'failed-precondition',
        message: 'Category name must be at least 2 characters.',
      );
    }
    final ref = _col(businessId).doc();
    await ref.set(<String, Object?>{
      'businessId': businessId,
      'name': trimmed,
      'iconName': iconName,
      'description': description?.trim().isEmpty == true
          ? null
          : description?.trim(),
      'isSystemCategory': false,
      'isActive': true,
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  @override
  Future<void> updateCategory(
    String businessId,
    String categoryId, {
    required String name,
    String iconName = 'payments',
    String? description,
  }) async {
    final trimmed = name.trim();
    if (trimmed.length < 2) {
      throw const ExpenseException(
        'failed-precondition',
        message: 'Category name must be at least 2 characters.',
      );
    }
    await _col(businessId).doc(categoryId).update(<String, Object?>{
      'name': trimmed,
      'iconName': iconName,
      'description': description?.trim().isEmpty == true
          ? null
          : description?.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> setActive(
    String businessId,
    String categoryId, {
    required bool isActive,
  }) async {
    await _col(businessId).doc(categoryId).update(<String, Object?>{
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> deleteCategory(String businessId, String categoryId) async {
    final ref = _col(businessId).doc(categoryId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final category = ExpenseCategory.fromFirestore(snap);
    if (category.isSystemCategory) {
      throw const ExpenseException(
        'failed-precondition',
        message: 'Built-in expense categories cannot be deleted. Disable them instead.',
      );
    }
    await ref.delete();
  }
}
