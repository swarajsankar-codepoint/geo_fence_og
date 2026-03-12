import '../../../core/util/remote_config.dart';

enum GeofenceStatus { initial, inside, outside }

class GeofenceState {
  final GeofenceStatus status;
  final double? currentLat;
  final double? currentLng;
  final double? distanceToZone;
  final bool serviceRunning;
  final bool locationDisabled; // new
  final String zoneId;
  final List<ZoneCoordinate> zoneCoordinates;

  const GeofenceState({
    this.status = GeofenceStatus.initial,
    this.currentLat,
    this.currentLng,
    this.distanceToZone,
    this.serviceRunning = false,
    this.locationDisabled = false, // new
    this.zoneId = 'kochi_zone',
    this.zoneCoordinates = const [],
  });

  GeofenceState copyWith({
    GeofenceStatus? status,
    double? currentLat,
    double? currentLng,
    double? distanceToZone,
    bool? serviceRunning,
    bool? locationDisabled, // new
    String? zoneId,
    List<ZoneCoordinate>? zoneCoordinates,
  }) => GeofenceState(
    status: status ?? this.status,
    currentLat: currentLat ?? this.currentLat,
    currentLng: currentLng ?? this.currentLng,
    distanceToZone: distanceToZone ?? this.distanceToZone,
    serviceRunning: serviceRunning ?? this.serviceRunning,
    locationDisabled: locationDisabled ?? this.locationDisabled, // new
    zoneId: zoneId ?? this.zoneId,
    zoneCoordinates: zoneCoordinates ?? this.zoneCoordinates,
  );
}
