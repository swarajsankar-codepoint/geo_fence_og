package com.example.geo_fencing

import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {

    private val channel = "com.example.geo_fencing/geofence"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            Log.d("MainActivity", "onCreate")
            GeofenceManager.restoreIfActive(this)
            BootReceiver.startPollingService(this)
            scheduleConfigWorker()
            runImmediateConfigCheck()
        }
    }

    private fun scheduleConfigWorker() {
        val request = PeriodicWorkRequestBuilder<GeofenceConfigWorker>(
            15, TimeUnit.MINUTES
        )
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .build()

        WorkManager.getInstance(this).enqueueUniquePeriodicWork(
            "geofence_config_periodic",
            ExistingPeriodicWorkPolicy.KEEP,
            request
        )
        Log.d("MainActivity", "Periodic config worker scheduled")
    }

    private fun runImmediateConfigCheck() {
        val request = OneTimeWorkRequestBuilder<GeofenceConfigWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .build()

        WorkManager.getInstance(this).enqueueUniqueWork(
            "geofence_config_immediate",
            ExistingWorkPolicy.KEEP,  // changed REPLACE → KEEP to avoid cancellations
            request
        )
        Log.d("MainActivity", "Immediate config check triggered")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                Log.d("MainActivity", "MethodChannel: ${call.method}")
                when (call.method) {
                    "addGeofence" -> {
                        val id     = call.argument<String>("id") ?: ""
                        val lat    = call.argument<Double>("latitude") ?: 0.0
                        val lng    = call.argument<Double>("longitude") ?: 0.0
                        val radius = call.argument<Double>("radius") ?: 200.0
                        GeofenceManager.addGeofence(this, id, lat, lng, radius.toFloat())
                        BootReceiver.startPollingService(this)
                        scheduleConfigWorker()
                        runImmediateConfigCheck()
                        result.success(true)
                    }
                    "removeGeofence" -> {
                        val id = call.argument<String>("id") ?: ""
                        GeofenceManager.removeGeofence(this, id)
                        stopService(Intent(this, GeofencePollingService::class.java))
                        WorkManager.getInstance(this).cancelUniqueWork("geofence_config_periodic")
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}