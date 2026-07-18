import 'package:firebase_auth/firebase_auth.dart';

/// A presentation-safe authentication failure. Raw provider errors stay private.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.isCancellation = false});

  factory AuthFailure.fromFirebase(FirebaseAuthException exception) {
    const messages = <String, String>{
      'network-request-failed': 'Check your internet connection and try again.',
      'account-exists-with-different-credential':
          'An account already exists using another sign-in method. Sign in using that method first, then connect Facebook from Settings.',
        'credential-already-in-use':
          'This Facebook account is already connected to another account.',
      'invalid-credential': 'Your sign-in details are not valid. Try again.',
      'user-disabled':
          'This account has been disabled. Contact support for help.',
      'too-many-requests':
          'Too many attempts. Please wait before trying again.',
        'operation-not-allowed':
          'This sign-in method is not enabled yet. Please try again later.',
      'email-already-in-use':
          'An account already exists with this email address.',
      'weak-password': 'Use a password with at least six characters.',
      'invalid-email': 'Enter a valid email address.',
      'user-not-found': 'No account was found with those details.',
      'wrong-password': 'Your email or password is incorrect.',
    };
    return AuthFailure(
      messages[exception.code] ?? 'Authentication failed. Please try again.',
    );
  }

  final String message;
  final bool isCancellation;
}
