import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/business_repository.dart';
import '../data/firestore_business_repository.dart';

final businessRepositoryProvider = Provider<BusinessRepository>((ref) {
  return FirestoreBusinessRepository();
});

final currentUserSetupStatusProvider =
    FutureProvider.autoDispose<UserSetupStatus?>((ref) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      return ref.read(businessRepositoryProvider).getUserSetupStatus(user.uid);
    });

final activeBusinessIdProvider = StreamProvider<String?>((ref) {
  final auth = FirebaseAuth.instance;
  return auth.authStateChanges().asyncExpand((user) {
    if (user == null) return Stream<String?>.value(null);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .map((snapshot) => snapshot.data()?['activeBusinessId'] as String?);
  });
});
