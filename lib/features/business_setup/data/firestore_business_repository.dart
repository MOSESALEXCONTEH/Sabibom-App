import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../domain/business.dart';
import '../domain/business_member.dart';
import '../domain/business_setup_data.dart';
import 'business_repository.dart';

class BusinessSetupException implements Exception {
  const BusinessSetupException(this.code, {this.message, this.operation});

  final String code;
  final String? message;
  final String? operation;
}

class FirestoreBusinessRepository implements BusinessRepository {
  FirestoreBusinessRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<UserSetupStatus> getUserSetupStatus(String uid) async {
    final snapshot = await _userDocument(uid).get();
    final data = snapshot.data();
    return UserSetupStatus(
      businessSetupCompleted: data?['businessSetupCompleted'] == true,
      activeBusinessId: data?['activeBusinessId'] as String?,
      fullName: data?['fullName'] as String?,
      phoneNumber: data?['phoneNumber'] as String?,
    );
  }

  @override
  Future<BusinessSetupResult> createBusinessSetup({
    required String uid,
    required String businessId,
    required BusinessSetupData data,
  }) async {
    final userDoc = _userDocument(uid);
    final businessDoc = _businessDocument(businessId);
    final memberDoc = businessDoc.collection('members').doc(uid);

    try {
      // Check for existing business inside the transaction for consistency.
      final result = await _firestore.runTransaction((transaction) async {
        final userSnapshot = await transaction.get(userDoc);
        final activeBusinessId =
            (userSnapshot.data()?['activeBusinessId'] as String?)?.trim();

        if (activeBusinessId != null && activeBusinessId.isNotEmpty) {
          final existingBusinessSnapshot =
              await transaction.get(_businessDocument(activeBusinessId));
          if (existingBusinessSnapshot.exists) {
            // Business already exists, return early.
            return BusinessSetupResult(
              businessId: activeBusinessId,
              wasExisting: true,
            );
          }
        }

        // No existing business, proceed with creation.
        final business = Business.fromSetupData(
          businessId: businessId,
          ownerId: uid,
          data: data,
        );
        final ownerMember = BusinessMember.owner(uid);

        // 1. Create business document
        transaction.set(businessDoc, {
          ...business.toMap(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // 2. Create owner membership document
        transaction.set(memberDoc, {
          ...ownerMember.toMap(),
          'joinedAt': FieldValue.serverTimestamp(),
        });

        // 3. Update user document
        transaction.set(
          userDoc,
          <String, Object?>{
            'activeBusinessId': businessId,
            'businessName': business.name,
            'businessSetupStatus': 'completed',
            'businessSetupCompleted': true,
            'businessSetupPromptSeen': true,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        return BusinessSetupResult(businessId: businessId, wasExisting: false);
      });

      return result;
    } on FirebaseException catch (error, stackTrace) {
      _logFirestoreError(
        operation: 'createBusinessSetupTransaction',
        uid: uid,
        businessId: businessId,
        error: error,
        stackTrace: stackTrace,
      );
      throw BusinessSetupException(
        error.code,
        message: error.message,
        operation: 'createBusinessSetup',
      );
    }
  }

  DocumentReference<Map<String, dynamic>> _userDocument(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  DocumentReference<Map<String, dynamic>> _businessDocument(String businessId) {
    return _firestore.collection('businesses').doc(businessId);
  }

  void _logFirestoreError({
    required String operation,
    required String uid,
    required String businessId,
    required FirebaseException error,
    required StackTrace stackTrace,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      'Firestore $operation failed: code=${error.code}, message=${error.message}, uid=$uid, businessId=$businessId',
    );
    debugPrint('$stackTrace');
  }
}
