package com.example.geo_fencing

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices

object GeofenceManager {

    private const val TAG = "GeofenceManager"
    private const val PREFS_NAME = "geofence_prefs"
    private const val KEY_ZONE_ID = "zone_id"
    private const val KEY_ZONE_LAT = "zone_lat"
    private const val KEY_ZONE_LNG = "zone_lng"
    private const val KEY_ZONE_RADIUS = "zone_radius"
    private const val KEY_IS_ACTIVE = "is_active"

    private fun getPrefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun getPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, GeofenceBroadcastReceiver::class.java)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT
        val pi = PendingIntent.getBroadcast(context, 0, intent, flags)
        Log.d(TAG, "PendingIntent created: $pi")
        return pi
    }

    fun addGeofence(
        context: Context,
        id: String,
        latitude: Double,
        longitude: Double,
        radius: Float,
    ) {
        Log.d(TAG, "addGeofence called — id=$id lat=$latitude lng=$longitude radius=$radius")

        getPrefs(context).edit()
            .putString(KEY_ZONE_ID, id)
            .putFloat(KEY_ZONE_LAT, latitude.toFloat())
            .putFloat(KEY_ZONE_LNG, longitude.toFloat())
            .putFloat(KEY_ZONE_RADIUS, radius)
            .putBoolean(KEY_IS_ACTIVE, true)
            .putString("zone_coordinates", "")  // will be filled by worker on first run
            .apply()

        Log.d(TAG, "Saved to SharedPreferences")
        registerWithClient(context, id, latitude, longitude, radius)
    }

    fun restoreIfActive(context: Context) {
        val prefs = getPrefs(context)
        val isActive = prefs.getBoolean(KEY_IS_ACTIVE, false)
        Log.d(TAG, "restoreIfActive — isActive=$isActive")
        if (!isActive) return

        val id     = prefs.getString(KEY_ZONE_ID, "") ?: return
        val lat    = prefs.getFloat(KEY_ZONE_LAT, 0f).toDouble()
        val lng    = prefs.getFloat(KEY_ZONE_LNG, 0f).toDouble()
        val radius = prefs.getFloat(KEY_ZONE_RADIUS, 200f)

        if (id.isEmpty()) return

        Log.d(TAG, "Restoring geofence: $id at $lat,$lng radius=$radius")
        registerWithClient(context, id, lat, lng, radius)
    }

    private fun registerWithClient(
        context: Context,
        id: String,
        latitude: Double,
        longitude: Double,
        radius: Float,
    ) {
        val client: GeofencingClient = LocationServices.getGeofencingClient(context)

        val geofence = Geofence.Builder()
            .setRequestId(id)
            .setCircularRegion(latitude, longitude, radius)
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .setTransitionTypes(
                Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT
            )
            .build()

        val request = GeofencingRequest.Builder()
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofence(geofence)
            .build()

        Log.d(TAG, "Calling client.addGeofences...")
        client.addGeofences(request, getPendingIntent(context))
            .addOnSuccessListener {
                Log.d(TAG, "✅ Geofence registered successfully: $id")
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "❌ Geofence registration FAILED: ${e.message} — code: ${(e as? com.google.android.gms.common.api.ApiException)?.statusCode}")
            }
    }

    fun removeGeofence(context: Context, id: String) {
        Log.d(TAG, "removeGeofence: $id")
        getPrefs(context).edit().putBoolean(KEY_IS_ACTIVE, false).apply()
        LocationServices.getGeofencingClient(context).removeGeofences(listOf(id))
    }

    fun removeAll(context: Context) {
        Log.d(TAG, "removeAll geofences")
        getPrefs(context).edit().putBoolean(KEY_IS_ACTIVE, false).apply()
        LocationServices.getGeofencingClient(context)
            .removeGeofences(getPendingIntent(context))
    }
}