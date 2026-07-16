import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserRepository {
  UserRepository._();

  static final instance = UserRepository._();

  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;

  Future<void> createUserIfNeeded() async {
    final user = auth.currentUser;

    if (user == null) return;

    final doc = firestore.collection("users").doc(user.uid);

    if (!(await doc.get()).exists) {
      await doc.set({
        "uid": user.uid,
        "name": user.displayName ?? "",
        "email": user.email,
        "photoUrl": user.photoURL,
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      });
    }
  }
}