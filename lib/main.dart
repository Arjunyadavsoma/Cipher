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

// NEW: Import the DebugLogger
import 'package:cipher_ai/core/services/debug_logger.dart'; 

import 'app/app.dart';
import 'core/services/supabase/supabase_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ┌─────────────────────────────────────────────────────────┐
  // │ GLOBAL LOG INTERCEPTOR: Route all prints to the UI      │
  // └─────────────────────────────────────────────────────────┘
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    // 1. Send to the in-app Debug Console
    DebugLogger.instance.log(message ?? '');
    // 2. Also print to the system console (IDX)
    originalDebugPrint(message, wrapWidth: wrapWidth);
  };

  // Intercept Flutter framework errors (red screens of death)
  FlutterError.onError = (FlutterErrorDetails details) {
    DebugLogger.instance.log("🔥 FLUTTER ERROR: ${details.exceptionAsString()}");
    FlutterError.dumpErrorToConsole(details);
  };

  await dotenv.load(fileName: ".env");

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await NotificationService.initialize();
  } catch (e) {
    debugPrint("Notification initialization skipped: $e");
  }

  try {
    await BackgroundTaskService.instance.init();
    await SupabaseService.initialize();
  } catch (e) {
    debugPrint("Background/Supabase initialization skipped: $e");
  }

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    _handleNotificationTap(message.data);
  });

  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    _handleNotificationTap(initialMessage.data);
  }

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint("❌ PLATFORM ERROR: $error");
    debugPrint(stack.toString());
    return true;
  };

  // Log app startup
  debugPrint("🚀 App Starting Up...");

  runApp(
    const ProviderScope(
      child: MimirAIApp(),
    ),
  );
}

void _handleNotificationTap(Map<String, dynamic> data) {
  final type = data['type'];
  final chatId = data['chatId'];

  if (type == 'research_complete' && chatId != null) {
    rootNavigatorKey.currentContext?.push('/chat/$chatId');
  }
}