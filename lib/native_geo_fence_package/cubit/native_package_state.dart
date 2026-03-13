import '../../core/util/remote_config.dart';

enum GeofenceStatus { initial, inside, outside }

class GeofencePkgState {
  final GeofenceStatus status;
  final double? currentLat;
  final double? currentLng;
  final double? distanceToZone;
  final bool serviceRunning;
  final String zoneId;
  final List<ZoneCoordinate> zoneCoordinates;

  const GeofencePkgState({
    this.status = GeofenceStatus.initial,
    this.currentLat,
    this.currentLng,
    this.distanceToZone,
    this.serviceRunning = false,
    this.zoneId = '',
    this.zoneCoordinates = const [],
  });

  GeofencePkgState copyWith({
    GeofenceStatus? status,
    double? currentLat,
    double? currentLng,
    double? distanceToZone,
    bool? serviceRunning,
    String? zoneId,
    List<ZoneCoordinate>? zoneCoordinates,
  }) => GeofencePkgState(
    status: status ?? this.status,
    currentLat: currentLat ?? this.currentLat,
    currentLng: currentLng ?? this.currentLng,
    distanceToZone: distanceToZone ?? this.distanceToZone,
    serviceRunning: serviceRunning ?? this.serviceRunning,
    zoneId: zoneId ?? this.zoneId,
    zoneCoordinates: zoneCoordinates ?? this.zoneCoordinates,
  );
}
