import 'dart:convert';
import 'package:cipher_ai/app/router.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

// NEW: Import the router to access the global navigator key


class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    const channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'Important notifications',
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();

    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      showNotification(message);
    });

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      // update Firestore user token here
    });
  }

  // NEW: Handle the notification tap using GoRouter and the payload
  static void _onNotificationTap(NotificationResponse response) {
    final payloadString = response.payload;
    if (payloadString == null || payloadString.isEmpty) return;

    try {
      final data = jsonDecode(payloadString) as Map<String, dynamic>;
      final type = data['type'];
      final chatId = data['chatId'];

      final context = rootNavigatorKey.currentContext;
      if (context != null) {
        if (type == 'research_complete' && chatId != null) {
          // Deep link to the specific chat
          GoRouter.of(context).push('/chat/$chatId');
        } else {
          // Default fallback to dashboard
          GoRouter.of(context).go('/dashboard');
        }
      }
    } catch (e) {
      // If JSON parsing fails, just go home
      final context = rootNavigatorKey.currentContext;
      if (context != null) {
        GoRouter.of(context).go('/dashboard');
      }
    }
  }

  static Future<void> showNotification(RemoteMessage message) async {
    final notification = message.notification;
    
    // Convert the data payload to a JSON string so we can pass it to the local notification
    final String payloadString = jsonEncode(message.data);

    await _localNotifications.show(
      message.hashCode,
      notification?.title ?? "cipher AI",
      notification?.body ?? "",
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription: 'Important notifications',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: payloadString, // Pass the payload here!
    );
  }

  static Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription: 'Important notifications',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  static Future<String?> getDeviceToken() async {
    return await _messaging.getToken();
  }
}