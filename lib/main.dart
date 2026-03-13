import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geofence_foreground_service/constants/geofence_event_type.dart';
import 'package:geofence_foreground_service/geofence_foreground_service.dart';

import 'core/util/notification_service.dart';
import 'core/util/remote_config.dart';
import 'firebase_options.dart';
import 'native_geo_fence_package/selection_scren.dart';

@pragma('vm:entry-point')
void callbackDispatcher() async {
  WidgetsFlutterBinding.ensureInitialized();
  final n = FlutterLocalNotificationsPlugin();
  await n.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );
  await n
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
  GeofenceForegroundService().handleTrigger(
    backgroundTriggerHandler: (zoneId, triggerType) async {
      final entered =
          triggerType == GeofenceEventType.enter ||
          triggerType == GeofenceEventType.dwell;
      await n.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
        entered ? '📍 Entered zone' : '🚶 Exited zone',
        entered ? 'You entered: $zoneId' : 'You exited: $zoneId',
        notifDetails,
      );
      return true;
    },
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await RemoteConfigService.init();
  await initNotifications();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SelectionScreen(),
    ),
  );
}
