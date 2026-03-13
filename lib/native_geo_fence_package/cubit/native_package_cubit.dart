import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:native_geofence/native_geofence.dart';

import 'package:permission_handler/permission_handler.dart';

import '../../core/util/native_geo_fence_callback.dart';
import '../../core/util/remote_config.dart';
import 'native_package_state.dart';

@pragma('vm:entry-point')
Future<void> _geofenceCallback(GeofenceCallbackParams params) async {
  WidgetsFlutterBinding.ensureInitialized();

  final n = FlutterLocalNotificationsPlugin();
  await n.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );
  await n.resolvePlatformSpecificImplementation;
  AndroidFlutterLocalNotificationsPlugin().createNotificationChannel(
    const AndroidNotificationChannel(
      'geofence',
      'Geofence Alerts',
      importance: Importance.max,
    ),
  );

  // params.geofences is List<ActiveGeofence>, params.event is GeofenceEvent
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

// ── Cubit ────────────────────────────────────────────────────────────────────
class GeofencePkgCubit extends Cubit<GeofencePkgState> {
  Timer? _remoteConfigTimer;
  late String _zoneId;
  late List<ZoneCoordinate> _zoneCoordinates;

  GeofencePkgCubit() : super(const GeofencePkgState());

  Future<void> init() async {
    await _loadZoneFromRemoteConfig();
    // initialize() uses its own internal callbackDispatcher — no parameter needed
    await NativeGeofenceManager.instance.initialize();
  }

  Future<void> _loadZoneFromRemoteConfig() async {
    await RemoteConfigService.refresh();
    _zoneId = RemoteConfigService.zoneId;
    _zoneCoordinates = RemoteConfigService.zoneCoordinates;
    emit(state.copyWith(zoneId: _zoneId, zoneCoordinates: _zoneCoordinates));
  }

  Future<void> startService() async {
    await Permission.location.request();
    await Permission.locationAlways.request();
    await _loadZoneFromRemoteConfig();
    await _registerZone(_zoneId, _zoneCoordinates);
    final notifStatus = await Permission.notification.request();
    debugPrint('[PKG] Notification permission: $notifStatus');
    emit(state.copyWith(serviceRunning: true));

    _remoteConfigTimer?.cancel();
    _remoteConfigTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) async => await _checkForZoneUpdate(),
    );
  }

  Future<void> _registerZone(String id, List<ZoneCoordinate> coords) async {
    // ...
    final handle = PluginUtilities.getCallbackHandle(geofencePkgCallback);
    debugPrint('[PKG] handle=${handle?.toRawHandle()}');
    if (handle == null) {
      debugPrint(
        '[PKG]Callback handle is NULL — geofencePkgCallback not registered',
      );
      return;
    }
    // If this prints null → callback is not registered properly
    final centerLat =
        coords.map((c) => c.lat).reduce((a, b) => a + b) / coords.length;
    final centerLng =
        coords.map((c) => c.lng).reduce((a, b) => a + b) / coords.length;

    double maxRadius = 0;
    for (final c in coords) {
      final d = _calcDistance(centerLat, centerLng, c.lat, c.lng);
      if (d > maxRadius) maxRadius = d;
    }
    final radius = maxRadius > 0 ? maxRadius : 200.0;

    try {
      await NativeGeofenceManager.instance.removeGeofenceById(id);
    } catch (_) {}

    // createGeofence takes 2 positional args: Geofence + GeofenceCallback
    await NativeGeofenceManager.instance.createGeofence(
      Geofence(
        id: id,
        location: Location(latitude: centerLat, longitude: centerLng),
        radiusMeters: radius,
        triggers: {GeofenceEvent.enter, GeofenceEvent.exit},
        iosSettings: const IosGeofenceSettings(initialTrigger: true),
        androidSettings: const AndroidGeofenceSettings(
          initialTriggers: {GeofenceEvent.enter, GeofenceEvent.exit},
          notificationResponsiveness: Duration(seconds: 0),
        ),
      ),
      geofencePkgCallback,
    );
    debugPrint('[PKG] Registered: $id radius=${radius.toStringAsFixed(0)}m');
  }

  Future<void> _checkForZoneUpdate() async {
    await RemoteConfigService.refresh();
    final newId = RemoteConfigService.zoneId;
    final newCoords = RemoteConfigService.zoneCoordinates;

    final changed =
        newId != _zoneId ||
        newCoords.length != _zoneCoordinates.length ||
        !_coordsEqual(newCoords, _zoneCoordinates);

    if (changed) {
      debugPrint('[PKG] Zone changed! $_zoneId → $newId');
      _zoneId = newId;
      _zoneCoordinates = newCoords;
      emit(
        state.copyWith(
          zoneId: _zoneId,
          zoneCoordinates: _zoneCoordinates,
          status: GeofenceStatus.initial,
        ),
      );
      await _registerZone(_zoneId, _zoneCoordinates);
    }
  }

  Future<void> stopService() async {
    _remoteConfigTimer?.cancel();
    try {
      await NativeGeofenceManager.instance.removeGeofenceById(_zoneId);
    } catch (_) {}
    emit(state.copyWith(serviceRunning: false, status: GeofenceStatus.initial));
  }

  double _calcDistance(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  bool _coordsEqual(List<ZoneCoordinate> a, List<ZoneCoordinate> b) {
    for (int i = 0; i < a.length; i++) {
      if (a[i].lat != b[i].lat || a[i].lng != b[i].lng) return false;
    }
    return true;
  }

  @override
  Future<void> close() {
    _remoteConfigTimer?.cancel();
    return super.close();
  }
}
