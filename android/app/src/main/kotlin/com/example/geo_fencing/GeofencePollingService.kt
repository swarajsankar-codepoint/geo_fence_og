package com.example.geo_fencing

import android.app.*
import android.content.Context
import android.content.Intent
import android.location.Location
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import com.google.firebase.Firebase
import com.google.firebase.remoteconfig.remoteConfig
import com.google.firebase.remoteconfig.remoteConfigSettings
import org.json.JSONArray

class GeofencePollingService : Service() {

    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var locationCallback: LocationCallback
    private val TAG = "GeofencePollingService"

    private var zoneId     = ""
    private var zoneLat    = 0.0
    private var zoneLng    = 0.0
    private var zoneRadius = 200.0
    private var wasInside: Boolean? = null

    private val handler = Handler(Looper.getMainLooper())
    private val remoteConfigRunnable = object : Runnable {
        override fun run() {
            fetchRemoteConfig()
            handler.postDelayed(this, 30_000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "=== SERVICE CREATED === PID: ${android.os.Process.myPid()}")
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        startForeground(999, buildForegroundNotification())
        loadZoneFromPrefs()
        startLocationUpdates()
        handler.post(remoteConfigRunnable)
    }

    private fun loadZoneFromPrefs() {
        val prefs = getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
        val isActive = prefs.getBoolean("is_active", false)
        if (!isActive) {
            stopSelf()
            return
        }
        zoneId     = prefs.getString("zone_id", "") ?: ""
        zoneLat    = prefs.getFloat("zone_lat", 0f).toDouble()
        zoneLng    = prefs.getFloat("zone_lng", 0f).toDouble()
        zoneRadius = prefs.getFloat("zone_radius", 200f).toDouble()
        Log.d(TAG, "Loaded from prefs — zone: $zoneId at $zoneLat,$zoneLng radius=$zoneRadius")
    }

    private fun fetchRemoteConfig() {
        Log.d(TAG, "Fetching Remote Config...")
        val remoteConfig = Firebase.remoteConfig
        remoteConfig.setConfigSettingsAsync(remoteConfigSettings {
            minimumFetchIntervalInSeconds = 0
        })
        remoteConfig.setDefaultsAsync(mapOf(
            "zone_id" to "kochi_zone",
            "zone_coordinates" to """[
                {"lat":9.9340,"lng":76.2650},
                {"lat":9.9340,"lng":76.2700},
                {"lat":9.9280,"lng":76.2700},
                {"lat":9.9280,"lng":76.2650}
            ]""",
        ))
        remoteConfig.fetchAndActivate().addOnCompleteListener { task ->
            if (!task.isSuccessful) {
                Log.e(TAG, "Remote Config fetch failed: ${task.exception?.message}")
                return@addOnCompleteListener
            }

            val newId        = remoteConfig.getString("zone_id")
            val coordsJson   = remoteConfig.getString("zone_coordinates")
            Log.d(TAG, "Remote Config fetched — zone: $newId")

            try {
                val arr = JSONArray(coordsJson)
                if (arr.length() < 3) return@addOnCompleteListener

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

                val changed = newId != zoneId ||
                        Math.abs(centerLat - zoneLat) > 0.00001 ||
                        Math.abs(centerLng - zoneLng) > 0.00001 ||
                        Math.abs(newRadius - zoneRadius) > 1.0

                if (changed) {
                    Log.d(TAG, "Zone changed! old=$zoneId new=$newId")
                    zoneId     = newId
                    zoneLat    = centerLat
                    zoneLng    = centerLng
                    zoneRadius = newRadius
                    wasInside  = null // reset for new zone

                    // Save to SharedPreferences
                    getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
                        .edit()
                        .putString("zone_id", zoneId)
                        .putFloat("zone_lat", zoneLat.toFloat())
                        .putFloat("zone_lng", zoneLng.toFloat())
                        .putFloat("zone_radius", zoneRadius.toFloat())
                        .apply()

                    // Re-register native GeofencingClient
                    GeofenceManager.addGeofence(
                        this, zoneId, zoneLat, zoneLng, zoneRadius.toFloat()
                    )

                    Log.d(TAG, "Zone updated and re-registered: $zoneId")
                } else {
                    Log.d(TAG, "Zone unchanged: $zoneId")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error parsing coords: ${e.message}")
            }
        }
    }

    private fun startLocationUpdates() {
        val request = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY, 5000L
        ).setMinUpdateIntervalMillis(3000L).build()

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val loc = result.lastLocation ?: return
                val distance = FloatArray(1)
                Location.distanceBetween(
                    loc.latitude, loc.longitude,
                    zoneLat, zoneLng, distance
                )
                val isInside = distance[0] <= zoneRadius
                Log.d(TAG, "Location: ${loc.latitude},${loc.longitude} dist=${distance[0]}m inside=$isInside zone=$zoneId")

                if (wasInside == null) {
                    wasInside = isInside
                    return
                }

                if (isInside && wasInside == false) {
                    Log.d(TAG, "ENTERED: $zoneId")
                    showZoneNotification("📍 Entered zone", "You entered: $zoneId")
                    wasInside = true
                } else if (!isInside && wasInside == true) {
                    Log.d(TAG, "EXITED: $zoneId")
                    showZoneNotification("🚶 Exited zone", "You exited: $zoneId")
                    wasInside = false
                }
            }
        }

        try {
            fusedLocationClient.requestLocationUpdates(
                request, locationCallback, mainLooper
            )
            Log.d(TAG, "Location updates started")
        } catch (e: SecurityException) {
            Log.e(TAG, "Location permission denied: ${e.message}")
            stopSelf()
        }
    }

    private fun buildForegroundNotification(): Notification {
        val channelId = "geofence_polling"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(
                    NotificationChannel(channelId, "Geofence Monitoring",
                        NotificationManager.IMPORTANCE_LOW)
                )
        }
        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("Geofence active")
            .setContentText("Monitoring your location")
            .setSmallIcon(android.R.drawable.ic_dialog_map)
            .setOngoing(true)
            .build()
    }

    private fun showZoneNotification(title: String, message: String) {
        val channelId = "geofence_alerts"
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(channelId, "Geofence Alerts",
                    NotificationManager.IMPORTANCE_HIGH)
            )
        }
        nm.notify(
            1001, // fixed ID — replaces previous instead of stacking
            NotificationCompat.Builder(this, channelId)
                .setSmallIcon(android.R.drawable.ic_dialog_map)
                .setContentTitle(title)
                .setContentText(message)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build()
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand — fetching Remote Config")
        fetchRemoteConfig()
        return START_STICKY
    }
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d(TAG, "onTaskRemoved — restarting service")
        // Restart self when app is swiped away
        val restartIntent = Intent(applicationContext, GeofencePollingService::class.java)
        val pendingIntent = android.app.PendingIntent.getService(
            applicationContext, 1, restartIntent,
            android.app.PendingIntent.FLAG_ONE_SHOT or
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                        android.app.PendingIntent.FLAG_MUTABLE
                    else 0
        )
        val alarmManager = getSystemService(ALARM_SERVICE) as android.app.AlarmManager
        alarmManager.set(
            android.app.AlarmManager.ELAPSED_REALTIME_WAKEUP,
            android.os.SystemClock.elapsedRealtime() + 1000,
            pendingIntent
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "=== SERVICE DESTROYED ===")
        handler.removeCallbacks(remoteConfigRunnable)
        if (::locationCallback.isInitialized) {
            fusedLocationClient.removeLocationUpdates(locationCallback)
        }
        Log.d(TAG, "Service destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}