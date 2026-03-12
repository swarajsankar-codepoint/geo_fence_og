import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../cubit/geo_fence_cubit.dart';
import '../cubit/geo_fence_state.dart';

class GeofenceView extends StatefulWidget {
  const GeofenceView({super.key});

  @override
  State<GeofenceView> createState() => _GeofenceViewState();
}

class _GeofenceViewState extends State<GeofenceView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (!status.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<GeofenceCubit, GeofenceState>(
        builder: (context, state) {
          final color = switch (state.status) {
            GeofenceStatus.inside => Colors.green,
            GeofenceStatus.outside => Colors.orange,
            GeofenceStatus.initial => Colors.grey,
          };

          final label = switch (state.status) {
            GeofenceStatus.inside => 'Inside Zone',
            GeofenceStatus.outside => 'Outside Zone',
            GeofenceStatus.initial => 'Waiting for location...',
          };

          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.locationDisabled)
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_off,
                          color: Colors.red.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Location is disabled. Please enable GPS.',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Geolocator.openLocationSettings(),
                          child: const Text('Enable'),
                        ),
                      ],
                    ),
                  ),
                Icon(Icons.location_on, size: 72, color: color),
                const SizedBox(height: 16),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 8),
                Text(state.zoneId, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 4),
                if (state.distanceToZone != null)
                  Text(
                    'Distance: ${state.distanceToZone!.toStringAsFixed(1)} m',
                    style: const TextStyle(color: Colors.grey),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: state.serviceRunning
                            ? Colors.green
                            : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      state.serviceRunning
                          ? 'Foreground service running'
                          : 'Stream only',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: state.serviceRunning
                        ? Colors.red
                        : Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: Icon(
                    state.serviceRunning ? Icons.stop : Icons.play_arrow,
                  ),
                  label: Text(
                    state.serviceRunning ? 'Stop Geofence' : 'Start Geofence',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () {
                    final cubit = context.read<GeofenceCubit>();
                    if (state.serviceRunning) {
                      cubit.stopService();
                    } else {
                      cubit.startService();
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
