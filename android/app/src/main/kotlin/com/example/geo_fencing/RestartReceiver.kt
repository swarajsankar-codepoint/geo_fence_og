package com.example.geo_fencing

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class RestartReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val serviceIntent = Intent(
            context,
            com.f2fk.geofence_foreground_service.GeofenceForegroundService::class.java
        )
        context.startForegroundService(serviceIntent)
    }
}