import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/native_package_cubit.dart';
import '../cubit/native_package_state.dart';

class GeofencePkgView extends StatelessWidget {
  const GeofencePkgView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Package Implementation'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: BlocBuilder<GeofencePkgCubit, GeofencePkgState>(
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
                          ? 'BGGeolocation running'
                          : 'Stopped',
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
                    state.serviceRunning ? 'Stop' : 'Start',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () {
                    final cubit = context.read<GeofencePkgCubit>();
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
