import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sabibom/features/auth/domain/auth_failure.dart';

void main() {
  test('maps Google credential conflicts to a safe explanation', () {
    final failure = AuthFailure.fromFirebase(
      FirebaseAuthException(code: 'account-exists-with-different-credential'),
    );

    expect(failure.message, contains('another sign-in method'));
  });

  test('maps Firebase network failures without exposing raw exceptions', () {
    final failure = AuthFailure.fromFirebase(
      FirebaseAuthException(code: 'network-request-failed'),
    );

    expect(failure.message, 'Check your internet connection and try again.');
  });
}
