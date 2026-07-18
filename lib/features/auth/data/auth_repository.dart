import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/app_user.dart';
import '../domain/auth_failure.dart';

/// Firebase-backed account operations and profile synchronization.
class AuthRepository {
  AuthRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  bool _googleInitialized = false;

  Future<AppUser?> signInWithGoogle() async {
    try {
      if (!_googleInitialized) {
        await GoogleSignIn.instance.initialize();
        _googleInitialized = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthFailure('Google sign-in could not be completed.');
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final result = await _auth.signInWithCredential(credential);
      final user = result.user;
      if (user == null) {
        throw const AuthFailure('Google sign-in could not be completed.');
      }
      await _syncGoogleProfile(user, account);
      return _toAppUser(user);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      throw const AuthFailure('Google sign-in failed. Please try again.');
    } on FirebaseAuthException catch (error) {
      throw AuthFailure.fromFirebase(error);
    }
  }

  Future<AppUser?> signInWithFacebook() async {
    try {
      final loginResult = await FacebookAuth.instance.login(
        permissions: const <String>['public_profile', 'email'],
      );
      if (loginResult.status == LoginStatus.cancelled ||
          loginResult.status == LoginStatus.operationInProgress) {
        return null;
      }
      if (loginResult.status != LoginStatus.success ||
          loginResult.accessToken == null ||
          loginResult.accessToken!.tokenString.isEmpty) {
        throw const AuthFailure('Facebook sign-in failed. Please try again.');
      }

      final credential = FacebookAuthProvider.credential(
        loginResult.accessToken!.tokenString,
      );
      final result = await _auth.signInWithCredential(credential);
      final user = result.user;
      if (user == null) {
        throw const AuthFailure('Facebook sign-in could not be completed.');
      }
      final facebookData = await FacebookAuth.instance.getUserData(
        fields: 'name,email,picture.width(200)',
      );
      await _syncSocialProfile(
        user: user,
        provider: 'facebook.com',
        fullName: facebookData['name'] as String? ?? user.displayName,
        email: facebookData['email'] as String? ?? user.email,
        photoUrl: _facebookPhotoUrl(facebookData) ?? user.photoURL,
      );
      return _toAppUser(user);
    } on FirebaseAuthException catch (error) {
      throw AuthFailure.fromFirebase(error);
    } catch (error) {
      if (error is AuthFailure) rethrow;
      throw const AuthFailure('Facebook sign-in failed. Please try again.');
    }
  }

  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return _toAppUser(result.user!);
    } on FirebaseAuthException catch (error) {
      throw AuthFailure.fromFirebase(error);
    }
  }

  Future<AppUser> registerWithEmail({
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = result.user!;
      await _userDocument(user.uid).set(_newProfile(
        uid: user.uid,
        fullName: fullName.trim(),
        email: user.email,
        phoneNumber: user.phoneNumber,
        photoUrl: user.photoURL,
        provider: 'password',
      ));
      return _toAppUser(user);
    } on FirebaseAuthException catch (error) {
      throw AuthFailure.fromFirebase(error);
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    if (_googleInitialized) {
      await GoogleSignIn.instance.signOut();
    }
    await FacebookAuth.instance.logOut();
  }

  Future<AppUser> _toAppUser(User user) async {
    final document = _userDocument(user.uid);
    final exists = (await document.get()).exists;
    if (exists) {
      await document.set(<String, Object?>{
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    return AppUser.fromFirebase(user, profileExists: exists);
  }

  Future<void> _syncGoogleProfile(User user, GoogleSignInAccount account) {
    return _syncSocialProfile(
      user: user,
      provider: 'google.com',
      fullName: account.displayName,
      email: account.email,
      photoUrl: account.photoUrl,
    );
  }

  Future<void> _syncSocialProfile({
    required User user,
    required String provider,
    required String? fullName,
    required String? email,
    required String? photoUrl,
  }) async {
    final document = _userDocument(user.uid);
    final existing = await document.get();
    if (!existing.exists) {
      await document.set(_newProfile(
        uid: user.uid,
        fullName: fullName?.trim().isNotEmpty == true
            ? fullName!.trim()
            : '',
        email: email,
        phoneNumber: user.phoneNumber,
        photoUrl: photoUrl,
        provider: provider,
      ));
      return;
    }

    final updates = <String, Object?>{
      'updatedAt': FieldValue.serverTimestamp(),
      'authProviders': FieldValue.arrayUnion(<String>[provider]),
    };
    if (photoUrl?.isNotEmpty == true) {
      updates['photoUrl'] = photoUrl;
    }
    await document.set(updates, SetOptions(merge: true));
  }

  Map<String, Object?> _newProfile({
    required String uid,
    required String fullName,
    required String? email,
    required String? phoneNumber,
    required String? photoUrl,
    required String provider,
  }) => <String, Object?>{
    'uid': uid,
    'fullName': fullName,
    'email': email,
    'phoneNumber': phoneNumber,
    'photoUrl': photoUrl,
    'authProviders': <String>[provider],
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'accountStatus': 'active',
    'businessSetupCompleted': false,
    'businessSetupStatus': 'not_started',
    'businessSetupPromptSeen': false,
    'activeBusinessId': null,
  };

  String? _facebookPhotoUrl(Map<String, dynamic> data) {
    final picture = data['picture'];
    if (picture is Map<String, dynamic>) {
      final pictureData = picture['data'];
      if (pictureData is Map<String, dynamic>) return pictureData['url'] as String?;
    }
    return null;
  }

  DocumentReference<Map<String, dynamic>> _userDocument(String uid) =>
      _firestore.collection('users').doc(uid);
}