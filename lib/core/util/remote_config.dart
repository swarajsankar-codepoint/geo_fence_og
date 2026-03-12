import 'dart:convert';
import 'package:firebase_remote_config/firebase_remote_config.dart';

class ZoneCoordinate {
  final double lat;
  final double lng;
  const ZoneCoordinate({required this.lat, required this.lng});

  factory ZoneCoordinate.fromJson(Map<String, dynamic> json) =>
      ZoneCoordinate(lat: json['lat'], lng: json['lng']);
}

class RemoteConfigService {
  static final _instance = FirebaseRemoteConfig.instance;

  static Future<void> init() async {
    await _instance.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: Duration.zero,
      ),
    );

    await _instance.setDefaults({
      'zone_id': 'N/A',
      'zone_coordinates': jsonEncode([
        {'lat': 0, 'lng': 0},
        {'lat': 0, 'lng': 0},
        {'lat': 0, 'lng': 0},
        {'lat': 0, 'lng': 0},
      ]),
    });

    await _instance.fetchAndActivate();
  }

  static Future<void> refresh() async {
    await _instance.fetchAndActivate();
  }

  static String get zoneId => _instance.getString('zone_id');

  static List<ZoneCoordinate> get zoneCoordinates {
    final raw = _instance.getString('zone_coordinates');
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => ZoneCoordinate.fromJson(e)).toList();
  }
}
