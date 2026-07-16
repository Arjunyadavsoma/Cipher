import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';


Future<void> firebaseMessagingBackgroundHandler(
    RemoteMessage message) async {


  await Firebase.initializeApp();


  debugPrint(
    "Background notification received: ${message.messageId}",
  );

}