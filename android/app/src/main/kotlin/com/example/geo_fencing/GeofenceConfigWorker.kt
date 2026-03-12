package com.example.geo_fencing

import android.content.Context
import android.location.Location
import android.util.Log
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.google.android.gms.location.LocationServices
import com.google.firebase.Firebase
import com.google.firebase.remoteconfig.remoteConfig
import com.google.firebase.remoteconfig.remoteConfigSettings
import kotlinx.coroutines.tasks.await
import org.json.JSONArray
import java.util.concurrent.TimeUnit

class GeofenceConfigWorker(
    private val ctx: Context,
    params: WorkerParameters
) : CoroutineWorker(ctx, params) {

    private val TAG = "GeofenceConfigWorker"

    override suspend fun doWork(): Result {
        Log.d(TAG, "Worker running")

        val prefs = ctx.getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
        val isActive = prefs.getBoolean("is_active", false)
        if (!isActive) {
            Log.d(TAG, "Not active - skipping")
            return Result.success()
        }

        try {
            val remoteConfig = Firebase.remoteConfig
            remoteConfig.setConfigSettingsAsync(remoteConfigSettings {
                minimumFetchIntervalInSeconds = 0
            }).await()
            remoteConfig.setDefaultsAsync(
                mapOf(
                    "zone_id" to "kochi_zone",
                    "zone_coordinates" to """[
                        {"lat":9.9340,"lng":76.2650},
                        {"lat":9.9340,"lng":76.2700},
                        {"lat":9.9280,"lng":76.2700},
                        {"lat":9.9280,"lng":76.2650}
                    ]""",
                )
            ).await()

            remoteConfig.fetchAndActivate().await()

            val newId = remoteConfig.getString("zone_id")
            val coordsJson = remoteConfig.getString("zone_coordinates")
            Log.d(TAG, "Fetched - zone: $newId")

            val arr = JSONArray(coordsJson)
            if (arr.length() < 3) return Result.success()

            var latSum = 0.0
            var lngSum = 0.0
            for (i in 0 until arr.length()) {
                latSum += arr.getJSONObject(i).getDouble("lat")
                lngSum += arr.getJSONObject(i).getDouble("lng")
            }
            val centerLat = latSum / arr.length()
            val centerLng = lngSum / arr.length()

            var maxRadius = 0.0
            for (i in 0 until arr.length()) {
                val lat = arr.getJSONObject(i).getDouble("lat")
                val lng = arr.getJSONObject(i).getDouble("lng")
                val dist = FloatArray(1)
                Location.distanceBetween(centerLat, centerLng, lat, lng, dist)
                if (dist[0] > maxRadius) maxRadius = dist[0].toDouble()
            }
            val newRadius = if (maxRadius > 0) maxRadius else 200.0


            val savedId      = prefs.getString("zone_id", "") ?: ""
            val savedCoordsJson = prefs.getString("zone_coordinates", "") ?: ""

            val changed = newId != savedId || savedCoordsJson != coordsJson

            if (changed) {
                Log.d(TAG, "Zone changed! saving new zone: $newId")

                prefs.edit()
                    .putString("zone_id", newId)
                    .putString("zone_coordinates", coordsJson)  // save raw JSON
                    .putFloat("zone_lat", centerLat.toFloat())
                    .putFloat("zone_lng", centerLng.toFloat())
                    .putFloat("zone_radius", newRadius.toFloat())
                    .apply()

                GeofenceManager.addGeofence(
                    ctx, newId, centerLat, centerLng, newRadius.toFloat()
                )

                notifyZoneChanged(newId, centerLat, centerLng, newRadius)
                schedulePeriodicCheck()

            } else {
                Log.d(TAG, "Zone unchanged: $newId")
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error: ${e.message}")
            return Result.retry()
        }

        return Result.success()
    }

    private suspend fun notifyZoneChanged(
        zoneId: String,
        zoneLat: Double,
        zoneLng: Double,
        zoneRadius: Double
    ) {
        try {
            val fusedClient = LocationServices.getFusedLocationProviderClient(ctx)
            val location = fusedClient.lastLocation.await() ?: return

            val dist = FloatArray(1)
            Location.distanceBetween(
                location.latitude, location.longitude,
                zoneLat, zoneLng, dist
            )
            val isInside = dist[0] <= zoneRadius

            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE)
                    as android.app.NotificationManager

            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                nm.createNotificationChannel(
                    android.app.NotificationChannel(
                        "geofence_alerts", "Geofence Alerts",
                        android.app.NotificationManager.IMPORTANCE_HIGH
                    )
                )
            }

            val title = if (isInside) "Entered zone" else "Exited zone"
            val message = "Zone updated to: $zoneId"

//            nm.notify(
//                1002,
//                androidx.core.app.NotificationCompat.Builder(ctx, "geofence_alerts")
//                    .setSmallIcon(android.R.drawable.ic_dialog_map)
//                    .setContentTitle(title)
//                    .setContentText(message)
//                    .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
//                    .setAutoCancel(true)
//                    .build()
//            )
            Log.d(TAG, "Zone change notification sent - inside: $isInside")
        } catch (e: Exception) {
            Log.e(TAG, "notifyZoneChanged error: ${e.message}")
        }
    }

    private fun schedulePeriodicCheck() {
        val request = PeriodicWorkRequestBuilder<GeofenceConfigWorker>(
            15, TimeUnit.MINUTES
        )
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .build()

        WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(
            "geofence_config_periodic",
            ExistingPeriodicWorkPolicy.KEEP,
            request
        )
        Log.d(TAG, "Periodic check scheduled every 15 minutes")
    }
}