import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final notifications = FlutterLocalNotificationsPlugin();

const notifDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'geofence',
    'Geofence Alerts',
    importance: Importance.max,
    priority: Priority.max,
  ),
  iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
);

const _initSettings = InitializationSettings(
  android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  iOS: DarwinInitializationSettings(),
);

Future<void> initNotifications() async {
  await notifications.initialize(_initSettings);
  await notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          'geofence',
          'Geofence Alerts',
          importance: Importance.max,
        ),
      );
  await notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();
}

Future<void> showNotif(String title, String body) async {
  await notifications.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
    title,
    body,
    notifDetails,
  );
}
