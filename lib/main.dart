import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cipher_ai/core/services/background_task_service.dart';

import 'package:cipher_ai/core/services/notification_service.dart';
import 'package:cipher_ai/core/services/firebase_background_handler.dart';

import 'app/app.dart';
import 'core/services/supabase/supabase_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print("Before dotenv");

  await dotenv.load(fileName: ".env");

  print("Firebase apps before: ${Firebase.apps.length}");

  if (Firebase.apps.isEmpty) {
    print("Initializing Firebase...");

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  print("Firebase apps after: ${Firebase.apps.length}");

  // Background notification handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Notification initialization
  await NotificationService.initialize();

  await BackgroundTaskService.instance.init();

  await SupabaseService.initialize();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint(error.toString());

    debugPrint(stack.toString());

    return true;
  };

  runApp(const ProviderScope(child: MimirAIApp()));
}