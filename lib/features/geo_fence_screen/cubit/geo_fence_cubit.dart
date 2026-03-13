import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geofence_foreground_service/constants/geofence_event_type.dart';
import 'package:geofence_foreground_service/exports.dart';
import 'package:geofence_foreground_service/geofence_foreground_service.dart';
import 'package:geofence_foreground_service/models/notification_icon_data.dart';
import 'package:geofence_foreground_service/models/zone.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/util/notification_service.dart';
import '../../../core/util/remote_config.dart';
import 'geo_fence_state.dart';

const _nativeChannel = MethodChannel('com.example.geo_fencing/geofence');

class GeofenceCubit extends Cubit<GeofenceState> {
  StreamSubscription<Position>? _positionStream;
  Timer? _remoteConfigTimer;
  bool _serviceTriggered = false;
  DateTime? _lastNotifTime;

  late String _zoneId;
  late List<ZoneCoordinate> _zoneCoordinates;
  late void Function() _callbackDispatcher;

  GeofenceCubit() : super(const GeofenceState());

  Future<void> init(void Function() callbackDispatcher) async {
    _callbackDispatcher = callbackDispatcher;
    await Permission.location.request();
    await Permission.locationAlways.request();

    if (!await Permission.ignoreBatteryOptimizations.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    await _loadZoneFromRemoteConfig();

    await _registerNativeGeofence();

    _serviceTriggered = await _startForegroundService();
    debugPrint(
      'Using: ${_serviceTriggered ? "foreground service" : "geolocator stream"}',
    );

    _startLocationStream();

    _remoteConfigTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _checkForZoneUpdate();
    });
  }

  Future<void> _registerNativeGeofence() async {
    try {
      final centerLat =
          _zoneCoordinates.map((c) => c.lat).reduce((a, b) => a + b) /
          _zoneCoordinates.length;
      final centerLng =
          _zoneCoordinates.map((c) => c.lng).reduce((a, b) => a + b) /
          _zoneCoordinates.length;

      double maxRadius = 0;
      for (final coord in _zoneCoordinates) {
        final d = _calcDistance(centerLat, centerLng, coord.lat, coord.lng);
        if (d > maxRadius) maxRadius = d;
      }

      await _nativeChannel.invokeMethod('addGeofence', {
        'id': _zoneId,
        'latitude': centerLat,
        'longitude': centerLng,
        'radius': maxRadius > 0 ? maxRadius : 200.0,
      });
      debugPrint('Native geofence registered: $_zoneId');
    } catch (e) {
      debugPrint('Native geofence error: $e');
    }
  }

  Future<void> _removeNativeGeofence(String zoneId) async {
    try {
      await _nativeChannel.invokeMethod('removeGeofence', {'id': zoneId});
    } catch (e) {
      debugPrint('Remove native geofence error: $e');
    }
  }

  Future<void> _loadZoneFromRemoteConfig() async {
    await RemoteConfigService.refresh();
    _zoneId = RemoteConfigService.zoneId;
    _zoneCoordinates = RemoteConfigService.zoneCoordinates;
    emit(state.copyWith(zoneId: _zoneId, zoneCoordinates: _zoneCoordinates));
  }

  Future<bool> _startForegroundService() async {
    try {
      await Permission.locationAlways.request();
      final isRunning = await GeofenceForegroundService()
          .isForegroundServiceRunning();

      if (!isRunning) {
        final started = await GeofenceForegroundService()
            .startGeofencingService(
              contentTitle: 'Geofence active',
              contentText: 'Monitoring your zone.',
              notificationChannelId: 'geofence_service',
              serviceId: 1000,
              notificationIconData: const NotificationIconData(
                resType: ResourceType.mipmap,
                resPrefix: ResourcePrefix.ic,
                name: 'launcher',
              ),
              callbackDispatcher: _callbackDispatcher,
            );
        if (!started) return false;
      }

      final centerLat =
          _zoneCoordinates.map((c) => c.lat).reduce((a, b) => a + b) /
          _zoneCoordinates.length;
      final centerLng =
          _zoneCoordinates.map((c) => c.lng).reduce((a, b) => a + b) /
          _zoneCoordinates.length;
      double maxRadius = 0;
      for (final coord in _zoneCoordinates) {
        final d = _calcDistance(centerLat, centerLng, coord.lat, coord.lng);
        if (d > maxRadius) maxRadius = d;
      }
      final radius = maxRadius > 0 ? maxRadius : 100.0;

      await GeofenceForegroundService().addGeofenceZone(
        zone: Zone(
          id: _zoneId,
          radius: radius,
          coordinates: [
            LatLng(Angle.degree(centerLat), Angle.degree(centerLng)),
          ],
          triggers: [GeofenceEventType.enter, GeofenceEventType.exit],
        ),
      );

      emit(state.copyWith(serviceRunning: true));
      return true;
    } catch (e) {
      debugPrint('Foreground service error: $e');
    }
    return false;
  }

  Future<void> _checkForZoneUpdate() async {
    await RemoteConfigService.refresh();

    final newId = RemoteConfigService.zoneId;
    final newCoordinates = RemoteConfigService.zoneCoordinates;

    final changed =
        newId != _zoneId ||
        newCoordinates.length != _zoneCoordinates.length ||
        !_coordinatesEqual(newCoordinates, _zoneCoordinates);

    if (changed) {
      final oldId = _zoneId;
      _zoneId = newId;
      _zoneCoordinates = newCoordinates;

      emit(
        state.copyWith(
          currentLat: _zoneCoordinates.isNotEmpty
              ? _zoneCoordinates.first.lat
              : 0,
          currentLng: _zoneCoordinates.isNotEmpty
              ? _zoneCoordinates.first.lng
              : 0,
          zoneId: _zoneId,
          zoneCoordinates: _zoneCoordinates,
          status: GeofenceStatus.initial,
        ),
      );

      await _removeNativeGeofence(oldId);
      await _registerNativeGeofence();

      if (_serviceTriggered) {
        await _reRegisterZone(oldId);
      }
    }
  }

  bool _coordinatesEqual(List<ZoneCoordinate> a, List<ZoneCoordinate> b) {
    for (int i = 0; i < a.length; i++) {
      if (a[i].lat != b[i].lat || a[i].lng != b[i].lng) return false;
    }
    return true;
  }

  Future<void> _reRegisterZone(String oldZoneId) async {
    try {
      await GeofenceForegroundService().removeGeofenceZone(zoneId: oldZoneId);
    } catch (_) {}
    try {
      await GeofenceForegroundService().addGeofenceZone(
        zone: Zone(
          id: _zoneId,
          radius: 0,
          coordinates: _zoneCoordinates
              .map((c) => LatLng(Angle.degree(c.lat), Angle.degree(c.lng)))
              .toList(),
          triggers: [GeofenceEventType.enter, GeofenceEventType.exit],
        ),
      );
    } catch (_) {}
  }

  void _startLocationStream() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    debugPrint('Location service enabled: $serviceEnabled');

    final permission = await Geolocator.checkPermission();
    debugPrint('Location permission: $permission');

    if (!serviceEnabled) {
      emit(state.copyWith(locationDisabled: true));
      Future.delayed(const Duration(seconds: 5), _startLocationStream);
      return;
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      await Geolocator.requestPermission();
      Future.delayed(const Duration(seconds: 2), _startLocationStream);
      return;
    }

    emit(state.copyWith(locationDisabled: false));

    Geolocator.getLastKnownPosition()
        .then((pos) {
          if (pos != null) _processPosition(pos);
        })
        .catchError((e) {
          debugPrint('getLastKnownPosition error: $e');
        });

    _positionStream?.cancel();
    _positionStream =
        Geolocator.getPositionStream(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.bestForNavigation,
                distanceFilter: 0,
              ),
            )
            .handleError((e) {
              debugPrint('Position stream error: $e');
              emit(state.copyWith(locationDisabled: true));
              Future.delayed(const Duration(seconds: 5), _startLocationStream);
            })
            .listen((pos) {
              emit(state.copyWith(locationDisabled: false));
              _processPosition(pos);
            });
  }

  // Future<void> _checkLocationAndRestart() async {
  //   final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  //   if (serviceEnabled) {
  //     debugPrint('Location service re-enabled — restarting stream');
  //     _positionStream?.cancel();
  //     _startLocationStream();
  //   } else {
  //     debugPrint('Location service still disabled — retrying in 5s');
  //     Future.delayed(const Duration(seconds: 5), () {
  //       _checkLocationAndRestart();
  //     });
  //   }
  // }

  void _processPosition(Position pos) {
    final isInside = _isInsidePolygon(
      pos.latitude,
      pos.longitude,
      _zoneCoordinates,
    );
    final wasInside = state.status == GeofenceStatus.inside;
    final dist = _nearestBoundaryDistance(
      pos.latitude,
      pos.longitude,
      _zoneCoordinates,
    );

    if (isInside && !wasInside) {
      emit(
        state.copyWith(
          status: GeofenceStatus.inside,
          currentLat: pos.latitude,
          currentLng: pos.longitude,
          distanceToZone: 0,
        ),
      );
      _sendNotifWithCooldown('Entered zone', 'You entered: $_zoneId');
    } else if (!isInside && wasInside) {
      emit(
        state.copyWith(
          status: GeofenceStatus.outside,
          currentLat: pos.latitude,
          currentLng: pos.longitude,
          distanceToZone: dist,
        ),
      );
      _sendNotifWithCooldown('Exited zone', 'You exited: $_zoneId');
    } else {
      emit(
        state.copyWith(
          currentLat: pos.latitude,
          currentLng: pos.longitude,
          distanceToZone: isInside ? 0 : dist,
        ),
      );
    }
  }

  bool _isInsidePolygon(double lat, double lng, List<ZoneCoordinate> polygon) {
    if (polygon.length < 3) return false;
    int intersections = 0;
    final n = polygon.length;
    for (int i = 0; i < n; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % n];
      if ((a.lng > lng) != (b.lng > lng)) {
        final intersectLat =
            (b.lat - a.lat) * (lng - a.lng) / (b.lng - a.lng) + a.lat;
        if (lat < intersectLat) intersections++;
      }
    }
    return intersections.isOdd;
  }

  double _nearestBoundaryDistance(
    double lat,
    double lng,
    List<ZoneCoordinate> polygon,
  ) {
    double minDist = double.infinity;
    for (final coord in polygon) {
      final d = _calcDistance(lat, lng, coord.lat, coord.lng);
      if (d < minDist) minDist = d;
    }
    return minDist;
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

  void _sendNotifWithCooldown(String title, String body) {
    final now = DateTime.now();
    if (_lastNotifTime == null ||
        now.difference(_lastNotifTime!) > const Duration(seconds: 5)) {
      _lastNotifTime = now;
      showNotif(title, body);
    }
  }

  Future<void> startService() async {
    await _loadZoneFromRemoteConfig();
    await Permission.location.request();
    await Permission.locationAlways.request();
    await _registerNativeGeofence();
    _serviceTriggered = await _startForegroundService();
    _startLocationStream();
    _remoteConfigTimer?.cancel();
    _remoteConfigTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      await _checkForZoneUpdate();
    });
    emit(state.copyWith(serviceRunning: true));
  }

  Future<void> stopService() async {
    _remoteConfigTimer?.cancel();
    _positionStream?.cancel();
    _positionStream = null;
    await _removeNativeGeofence(_zoneId);
    await GeofenceForegroundService().stopGeofencingService();
    emit(
      state.copyWith(
        serviceRunning: false,
        status: GeofenceStatus.initial,
        distanceToZone: null,
      ),
    );
  }

  @override
  Future<void> close() {
    _remoteConfigTimer?.cancel();
    _positionStream?.cancel();
    return super.close();
  }
}
