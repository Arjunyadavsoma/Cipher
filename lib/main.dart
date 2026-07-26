import 'dart:ui';

import 'package:cipher_ai/app/router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cipher_ai/core/services/background_task_service.dart';

import 'package:cipher_ai/core/services/notification_service.dart';
import 'package:cipher_ai/core/services/firebase_background_handler.dart';

import 'app/app.dart';
import 'core/services/supabase/supabase_service.dart';
import 'firebase_options.dart';
// Import the router file to access rootNavigatorKey

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await NotificationService.initialize();
  await BackgroundTaskService.instance.init();
  await SupabaseService.initialize();

  // ┌─────────────────────────────────────────────────────────┐
  // │ DEEP LINKING: Handle Notification Taps                   │
  // └─────────────────────────────────────────────────────────┘
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    _handleNotificationTap(message.data);
  });

  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    _handleNotificationTap(initialMessage.data);
  }

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint(error.toString());
    debugPrint(stack.toString());
    return true;
  };

  runApp(
    const ProviderScope(
      child: MimirAIApp(),
    ),
  );
}

/// Handles routing the user to the correct screen when they tap a notification.
void _handleNotificationTap(Map<String, dynamic> data) {
  final type = data['type'];
  final chatId = data['chatId'];

  if (type == 'research_complete' && chatId != null) {
    // Use the rootNavigatorKey provided by go_router
    rootNavigatorKey.currentContext?.push('/chat/$chatId');
  }
}