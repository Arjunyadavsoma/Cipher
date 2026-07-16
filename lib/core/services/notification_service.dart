import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';


class NotificationService {

  static final FirebaseMessaging _messaging =
      FirebaseMessaging.instance;


  static final FlutterLocalNotificationsPlugin
      _localNotifications =
      FlutterLocalNotificationsPlugin();



  static Future<void> initialize() async {


    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );



    const channel = AndroidNotificationChannel(

      'high_importance_channel',

      'High Importance Notifications',

      description:
          'Important notifications',

      importance:
          Importance.high,

    );



    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);



    const androidSettings =
        AndroidInitializationSettings(
          '@mipmap/ic_launcher',
        );



    await _localNotifications.initialize(

      const InitializationSettings(

        android: androidSettings,

      ),

    );



    // Foreground notification

    FirebaseMessaging.onMessage.listen(
      (RemoteMessage message) {

        showNotification(message);

      },
    );



    // Token refresh

    FirebaseMessaging.instance
        .onTokenRefresh
        .listen(
      (newToken) {

        // update Firestore user token here

      },
    );

  }




  static Future<void> showNotification(
      RemoteMessage message) async {


    final notification =
        message.notification;



    await _localNotifications.show(

      message.hashCode,

      notification?.title ??
          "Cipher",

      notification?.body ??
          "",



      const NotificationDetails(

        android:
            AndroidNotificationDetails(

              'high_importance_channel',

              'High Importance Notifications',

              channelDescription:
                  'Important notifications',

              importance:
                  Importance.high,

              priority:
                  Priority.high,

              icon:
                  '@mipmap/ic_launcher',

            ),

      ),

    );

  }





  static Future<String?> getDeviceToken() async {

  return await _messaging.getToken();

}


}