import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:cipher_ai/core/services/notification_service.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(FirebaseAuth.instance, FirebaseFirestore.instance);
});

class AuthRepository {
  AuthRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;

  final FirebaseFirestore _firestore;

  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> _createUserDocument(User user) async {
    final doc = _firestore.collection("users").doc(user.uid);

    final snapshot = await doc.get();

    if (!snapshot.exists) {
      await doc.set({
        "uid": user.uid,

        "name": user.displayName ?? "",

        "email": user.email,

        "photoUrl": user.photoURL,

        "createdAt": FieldValue.serverTimestamp(),

        "updatedAt": FieldValue.serverTimestamp(),
      });
    } else {
      await doc.update({"updatedAt": FieldValue.serverTimestamp()});
    }

    await _saveNotificationToken(user.uid);
  }

  Future<void> _saveNotificationToken(String uid) async {
    final token = await NotificationService.getDeviceToken();

    if (token == null) {
      return;
    }

    await _firestore.collection("users").doc(uid).set({
      "fcmToken": token,

      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<User?> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email,

      password: password,
    );

    if (result.user != null) {
      await _createUserDocument(result.user!);
    }

    return result.user;
  }

  Future<User?> createUserWithEmailAndPassword(
    String email,
    String password,
  ) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email,

      password: password,
    );

    if (result.user != null) {
      await _createUserDocument(result.user!);
    }

    return result.user;
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<User?> signInWithGoogle() async {
    final GoogleSignInAccount? account = await _googleSignIn.signIn();

    if (account == null) {
      return null;
    }

    final googleAuth = await account.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,

      idToken: googleAuth.idToken,
    );

    final result = await _auth.signInWithCredential(credential);

    if (result.user != null) {
      await _createUserDocument(result.user!);
    }

    return result.user;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();

    await _auth.signOut();
  }
}
