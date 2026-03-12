package com.example.geo_fencing

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("BootReceiver", "onReceive: ${intent.action}")
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_LOCKED_BOOT_COMPLETED) {
            GeofenceManager.restoreIfActive(context)
            startPollingService(context)
        }
    }

    companion object {
        fun startPollingService(context: Context) {
            val prefs = context.getSharedPreferences("geofence_prefs", Context.MODE_PRIVATE)
            val isActive = prefs.getBoolean("is_active", false)
            if (!isActive) {
                Log.d("BootReceiver", "Geofence not active — not starting service")
                return
            }
            Log.d("BootReceiver", "Starting GeofencePollingService")
            val serviceIntent = Intent(context, GeofencePollingService::class.java)
            context.startForegroundService(serviceIntent)
        }
    }
}