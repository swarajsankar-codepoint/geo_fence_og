import 'dart:developer';
import 'package:flutter/cupertino.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geofence_foreground_service/constants/geofence_event_type.dart';
import 'package:geofence_foreground_service/exports.dart';
import 'package:geofence_foreground_service/geofence_foreground_service.dart';
import 'package:geofence_foreground_service/models/notification_icon_data.dart';
import 'package:geofence_foreground_service/models/zone.dart';
import 'package:permission_handler/permission_handler.dart';

const _initSettings = InitializationSettings(
  android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  iOS: DarwinInitializationSettings(),
);

const _notifDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'geofence_alerts',
    'Geofence Alerts',
    channelDescription: 'Zone entry and exit alerts',
    importance: Importance.max,
    priority: Priority.max,
    playSound: true,
  ),
  iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
);

@pragma('vm:entry-point')
void callbackDispatcher() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(_initSettings);

  GeofenceForegroundService().handleTrigger(
    backgroundTriggerHandler: (zoneId, triggerType) async {
      log('Geofence trigger: $zoneId — $triggerType');

      final entered =
          triggerType == GeofenceEventType.enter ||
          triggerType == GeofenceEventType.dwell;

      await notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
        entered ? '-- Entered zone' : '--Exited zone',
        entered ? 'You entered: $zoneId' : 'You exited: $zoneId',
        _notifDetails,
      );

      return true;
    },
  );
}

Future<void> initGeofenceService() async {
  // Request permissions
  await Permission.location.request();
  await Permission.locationAlways.request();
  await Permission.notification.request();

  // Init notifications in main isolate too
  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(_initSettings);

  // Create notification channel explicitly (Android 8+)
  await notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          'geofence_alerts',
          'Geofence Alerts',
          description: 'Zone entry and exit alerts',
          importance: Importance.max,
        ),
      );

  final started = await GeofenceForegroundService().startGeofencingService(
    contentTitle: 'Geofence active',
    contentText: 'Monitoring your zone.',
    notificationChannelId: 'geofence_service',
    serviceId: 1000,
    isInDebugMode: true,
    notificationIconData: const NotificationIconData(
      resType: ResourceType.mipmap,
      resPrefix: ResourcePrefix.ic,
      name: 'launcher',
    ),
    callbackDispatcher: callbackDispatcher,
  );

  log('Service started: $started');

  if (started) {
    await GeofenceForegroundService().addGeofenceZone(
      zone: Zone(
        id: 'kochi_zone',
        radius: 200,
        coordinates: [LatLng(Angle.degree(9.9312), Angle.degree(76.2673))],
        triggers: [
          GeofenceEventType.enter,
          GeofenceEventType.exit,
          GeofenceEventType.dwell,
        ],
      ),
    );
  }
}
