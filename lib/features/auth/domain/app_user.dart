import 'package:firebase_auth/firebase_auth.dart';

/// Safe account information needed by the application layer.
class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.phoneNumber,
    required this.profileExists,
  });

  factory AppUser.fromFirebase(User user, {required bool profileExists}) {
    return AppUser(
      uid: user.uid,
      email: user.email,
      phoneNumber: user.phoneNumber,
      profileExists: profileExists,
    );
  }

  final String uid;
  final String? email;
  final String? phoneNumber;
  final bool profileExists;
}
