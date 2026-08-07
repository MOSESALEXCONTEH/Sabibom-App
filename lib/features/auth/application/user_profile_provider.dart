import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.businessSetupStatus,
    required this.businessSetupPromptSeen,
    required this.activeBusinessId,
    required this.businessName,
    required this.fullName,
  });

  final String uid;
  final String businessSetupStatus;
  final bool businessSetupPromptSeen;
  final String? activeBusinessId;
  final String? businessName;
  final String? fullName;

  factory UserProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? {};
    final legacyCompleted = data['businessSetupCompleted'] == true;
    return UserProfile(
      uid: snapshot.id,
      businessSetupStatus:
          (data['businessSetupStatus'] as String?) ??
          (legacyCompleted ? 'completed' : 'not_started'),
      businessSetupPromptSeen: data['businessSetupPromptSeen'] == true,
      activeBusinessId: data['activeBusinessId'] as String?,
      businessName: data['businessName'] as String?,
      fullName: data['fullName'] as String?,
    );
  }

  bool get hasActiveBusiness =>
      activeBusinessId != null && activeBusinessId!.trim().isNotEmpty;
}

final currentUserProfileProvider = StreamProvider<UserProfile?>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream<UserProfile?>.value(null);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.exists ? UserProfile.fromFirestore(snapshot) : null,
      );
});

Future<void> updateBusinessSetupPreference({
  required String status,
  required bool promptSeen,
}) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Future<void>.value();
  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .set(<String, Object?>{
        'businessSetupStatus': status,
        'businessSetupPromptSeen': promptSeen,
        if (status == 'skipped') 'businessSetupCompleted': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}
