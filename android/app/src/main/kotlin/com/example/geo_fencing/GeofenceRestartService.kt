package com.example.geo_fencing

import android.app.Service
import android.content.Intent
import android.os.IBinder

class GeofenceRestartService : Service() {

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Restart the geofence foreground service
        val serviceIntent = Intent(
            this,
            com.f2fk.geofence_foreground_service.GeofenceForegroundService::class.java
        )
        startForegroundService(serviceIntent)
        stopSelf()
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
}