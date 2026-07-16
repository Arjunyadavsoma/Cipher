import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    FirebaseAuth.instance,
  );
});


class AuthRepository {

  final FirebaseAuth _auth;


  AuthRepository(this._auth);



  Stream<User?> get authStateChanges =>
      _auth.authStateChanges();



  User? get currentUser =>
      _auth.currentUser;



  Future<UserCredential> signUp({
    required String email,
    required String password,
  }) async {

    return await _auth
        .createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }



  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {

    return await _auth
        .signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }



  Future<void> sendPasswordResetEmail(
      String email,
      ) async {

    await _auth.sendPasswordResetEmail(
      email: email,
    );
  }



  Future<void> sendEmailVerification() async {

    final user = _auth.currentUser;

    if(user != null && !user.emailVerified){

      await user.sendEmailVerification();

    }
  }



  Future<void> signOut() async {

    await _auth.signOut();

  }



  Future<void> updatePassword(
      String password,
      ) async {

    final user = _auth.currentUser;

    if(user == null){
      throw FirebaseAuthException(
        code: "no-user",
        message: "No logged in user",
      );
    }


    await user.updatePassword(
      password,
    );
  }



  Future<void> updateDisplayName(
      String name,
      ) async {

    final user = _auth.currentUser;

    if(user != null){

      await user.updateDisplayName(
        name,
      );

      await user.reload();

    }
  }



  Future<void> deleteAccount() async {

    final user = _auth.currentUser;

    if(user != null){

      await user.delete();

    }
  }


}