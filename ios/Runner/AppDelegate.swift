import UIKit
import Flutter
import FirebaseCore
import BackgroundTasks
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

    private var geofenceManager: GeofenceManager?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Register background tasks FIRST — before super returns
        GeofenceConfigWorker.registerBackgroundTasks()

        FirebaseApp.configure()
        GeneratedPluginRegistrant.register(with: self)

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, _ in
            print("[AppDelegate] Notification permission: \(granted)")
        }

        // Setup MethodChannel — mirrors MainActivity.kt MethodChannel
        let controller = window?.rootViewController as! FlutterViewController
        let channel = FlutterMethodChannel(
            name: "com.example.geo_fencing/geofence",
            binaryMessenger: controller.binaryMessenger
        )

        geofenceManager = GeofenceManager()

        channel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "addGeofence":
                guard
                    let args   = call.arguments as? [String: Any],
                    let id     = args["id"] as? String,
                    let lat    = args["latitude"] as? Double,
                    let lng    = args["longitude"] as? Double,
                    let radius = args["radius"] as? Double
                else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil))
                    return
                }
                self?.geofenceManager?.addGeofence(id: id, lat: lat, lng: lng, radius: radius)
                GeofenceConfigWorker.scheduleBackgroundTask()
                GeofenceConfigWorker.runNow()
                result(true)

            case "removeGeofence":
                guard
                    let args = call.arguments as? [String: Any],
                    let id   = args["id"] as? String
                else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing id", details: nil))
                    return
                }
                self?.geofenceManager?.removeGeofence(id: id)
                GeofenceConfigWorker.cancelBackgroundTask()
                result(true)

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // Restore geofence on app launch — mirrors GeofenceManager.restoreIfActive()
        geofenceManager?.restoreIfActive()

        // Run immediate config check on every app open — mirrors runImmediateConfigCheck()
        GeofenceConfigWorker.runNow()

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // Background fetch handler
    override func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        GeofenceConfigWorker.runNow {
            completionHandler(.newData)
        }
    }

    // Show notification even when app is in foreground
    override func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}