package com.example.geo_fencing

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.google.android.gms.location.GeofencingEvent
import com.google.android.gms.location.Geofence

class GeofenceBroadcastReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        Log.d("GeofenceReceiver", "onReceive fired")
        scheduleImmediateConfigCheck(context)

        val geofencingEvent = GeofencingEvent.fromIntent(intent) ?: return
        if (geofencingEvent.hasError()) return

        val transitionType = geofencingEvent.geofenceTransition
        val triggeringGeofences = geofencingEvent.triggeringGeofences ?: return

        for (geofence in triggeringGeofences) {
            val zoneId = geofence.requestId
            val title: String
            val message: String

            when (transitionType) {
                Geofence.GEOFENCE_TRANSITION_ENTER -> {
                    title = "📍 Entered zone"
                    message = "You entered: $zoneId"
                }
                Geofence.GEOFENCE_TRANSITION_EXIT -> {
                    title = "🚶 Exited zone"
                    message = "You exited: $zoneId"
                }
                else -> return
            }
            showNotification(context, title, message)
        }
    }

    private fun scheduleImmediateConfigCheck(context: Context) {
        val request = OneTimeWorkRequestBuilder<GeofenceConfigWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            "geofence_config_immediate",
            ExistingWorkPolicy.REPLACE,
            request
        )
        Log.d("GeofenceReceiver", "Scheduled immediate config check")
    }

    private fun showNotification(context: Context, title: String, message: String) {
        val channelId = "geofence_alerts"
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(channelId, "Geofence Alerts",
                    NotificationManager.IMPORTANCE_HIGH)
            )
        }
        nm.notify(
            1001,
            NotificationCompat.Builder(context, channelId)
                .setSmallIcon(android.R.drawable.ic_dialog_map)
                .setContentTitle(title)
                .setContentText(message)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build()
        )
    }
}