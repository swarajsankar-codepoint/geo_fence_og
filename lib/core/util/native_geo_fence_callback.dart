import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:native_geofence/native_geofence.dart';

@pragma('vm:entry-point')
Future<void> geofencePkgCallback(GeofenceCallbackParams params) async {
  WidgetsFlutterBinding.ensureInitialized();

  final n = FlutterLocalNotificationsPlugin();
  await n.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );
  await n.resolvePlatformSpecificImplementation;
  AndroidFlutterLocalNotificationsPlugin()?.createNotificationChannel(
    const AndroidNotificationChannel(
      'geofence',
      'Geofence Alerts',
      importance: Importance.max,
    ),
  );

  final entered = params.event == GeofenceEvent.enter;
  final ids = params.geofences.map((g) => g.id).join(', ');

  debugPrint('[PKG] Geofence event: ${params.event} zones: $ids');

  await n.show(
    1001,
    entered ? '📍 Entered zone' : '🚶 Exited zone',
    entered ? 'You entered: $ids' : 'You exited: $ids',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'geofence',
        'Geofence Alerts',
        importance: Importance.max,
        priority: Priority.max,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    ),
  );
}
