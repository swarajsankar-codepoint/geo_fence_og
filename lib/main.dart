import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geofence_foreground_service/constants/geofence_event_type.dart';
import 'package:geofence_foreground_service/geofence_foreground_service.dart';

import 'core/util/notification_service.dart';
import 'core/util/remote_config.dart';
import 'features/geo_fence_screen/cubit/geo_fence_cubit.dart';
import 'features/geo_fence_screen/view/geo_fence_screen.dart';
import 'firebase_options.dart';

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
  debugPrint('STEP 1: binding');
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('STEP 2: firebase init');
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('STEP 2: firebase ok');
  } catch (e) {
    debugPrint('STEP 2 ERROR: $e');
  }

  debugPrint('STEP 3: remote config');
  try {
    await RemoteConfigService.init();
    debugPrint('STEP 3: remote config ok');
  } catch (e) {
    debugPrint('STEP 3 ERROR: $e');
  }

  debugPrint('STEP 4: notifications');
  try {
    await initNotifications();
    debugPrint('STEP 4: notifications ok');
  } catch (e) {
    debugPrint('STEP 4 ERROR: $e');
  }

  debugPrint('STEP 5: runApp');
  runApp(
    BlocProvider(
      create: (_) => GeofenceCubit()..init(callbackDispatcher),
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: GeofenceView(),
      ),
    ),
  );
  debugPrint('STEP 5: runApp ok');
}
