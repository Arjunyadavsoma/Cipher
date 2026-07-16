import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:firebase_auth/firebase_auth.dart';

import '../../home/models/chat_message.dart';

class ChatRepository {
  ChatRepository._();

  static final ChatRepository instance = ChatRepository._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User get currentUser {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception("User is not logged in.");
    }

    return user;
  }

  CollectionReference<Map<String, dynamic>> get conversations =>
      _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('conversations');

  Future<String> createConversation() async {
    final doc = conversations.doc();

    await doc.set({
      "title": "New Chat",
      "createdAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
      "lastMessage": "",
    });

    return doc.id;
  }

  Future<void> saveMessage({
    required String conversationId,
    required ChatMessage message,
  }) async {
    final conversation = conversations.doc(conversationId);

    await conversation.collection("messages").add({
      "id": message.id,
      "text": message.text,
      "sender": message.sender.name,
      "timestamp": FieldValue.serverTimestamp(),
    });

    await conversation.update({
      "lastMessage": message.text,
      "updatedAt": FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getConversationHistory() {
    return conversations
        .orderBy("updatedAt", descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getMessages(
      String conversationId) {
    return conversations
        .doc(conversationId)
        .collection("messages")
        .orderBy("timestamp")
        .snapshots();
  }
}