import 'dart:async';
import 'package:mimir_ai/features/agents/DSA_agent/dsa_agent.dart';
import 'package:mimir_ai/features/agents/models/execution_context.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';


final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// This function MUST be a top-level or static function.
// ... (imports remain the same) ...

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("Background Task Started: $task");

    // 1. Initialize necessary services for the background isolate
    await Firebase.initializeApp();
    await Supabase.initialize(
      url: 'YOUR_SUPABASE_URL',
      anonKey: 'YOUR_SUPABASE_ANON_KEY',
    );
    
    // Initialize notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    try {
      // 2. Route the task based on the name
      if (task == 'dsaDailyFetch') {
        await _fetchDsaPotdAndNotify(inputData?['userId'] as String);
      } 
      // You can add more background agent tasks here later
      
    } catch (e) {
      print("Background Task Error: $e");
      return Future.value(false); // Task failed, OS will retry later
    }

    return Future.value(true); // Task succeeded
  });
}

Future<void> _fetchDsaPotdAndNotify(String userId) async {
  // 1. Access the ToolManager Singleton
  
  // 2. CRITICAL: Register your tools in this background isolate!
  // Because this is a separate isolate, the tools registered in main.dart 
  // don't exist here. You must register them again.
  // (Adjust these based on how you actually register tools in your ToolManager)
  //
  // Example:
  // toolManager.registerTool(GroqTool());
  // toolManager.registerTool(FirebaseTool());
  // toolManager.registerTool(HttpTool());
  
  // 3. Initialize the agent
  final dsaAgent = DsaAgent();
  
  // 4. Create a mock execution context for the background task
  final context = ExecutionContext(
    userId: userId,
    chatId: 'background_task',
    message: "What is today's problem of the day?",
    recentMessages: const [],
    rollingSummary: '',
    alwaysContext: '',
    agentMemory: const {},
  );

  // 5. Execute the agent
  final result = await dsaAgent.execute(context);

  // 6. Show a notification with the result
  await flutterLocalNotificationsPlugin.show(
    8888, // Notification ID
    'DSA Problem of the Day is Ready! 🔥',
    result.responseText.split('\n').first, // Just show the first line (usually the title)
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'dsa_daily_channel',
        'DSA Daily Updates',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    ),
  );
}

// ... (rest of BackgroundTaskService class remains the same) ...
class BackgroundTaskService {
  static final BackgroundTaskService instance = BackgroundTaskService._();
  BackgroundTaskService._();

  Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  /// Call this when user logs in or opens the app to schedule the 8 AM task
  Future<void> scheduleDailyDsaFetch(String userId) async {
    await Workmanager().registerPeriodicTask(
      'dsa-daily-fetch-task', // Unique name
      'dsaDailyFetch', // Task name matched in callbackDispatcher
      frequency: const Duration(hours: 24),
      tag: 'dsa_fetch',
      inputData: {'userId': userId},
      constraints: Constraints(
        networkType: NetworkType.connected, // Requires internet
      ),
      // Note: Workmanager doesn't guarantee exact 8 AM execution, 
      // it optimizes for battery. It will run roughly once a day.
    );
    print("Scheduled DSA Daily Fetch for user: $userId");
  }

  /// Call this when user logs out to cancel the background task
  Future<void> cancelAllTasks() async {
    await Workmanager().cancelAll();
  }
}