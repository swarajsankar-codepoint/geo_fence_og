import Foundation
import BackgroundTasks
import CoreLocation
import UserNotifications
import FirebaseRemoteConfig

// Mirrors GeofenceConfigWorker.kt
// Uses BGTaskScheduler instead of WorkManager
class GeofenceConfigWorker {

    private static let TAG             = "GeofenceConfigWorker"
    static let TASK_ID_PERIODIC        = "com.example.geo_fencing.config_check"
    static let TASK_ID_REFRESH         = "com.example.geo_fencing.config_refresh"

    private static let prefs           = UserDefaults.standard
    private static let KEY_ZONE_ID     = "zone_id"
    private static let KEY_ZONE_LAT    = "zone_lat"
    private static let KEY_ZONE_LNG    = "zone_lng"
    private static let KEY_ZONE_RADIUS = "zone_radius"
    private static let KEY_ZONE_COORDS = "zone_coordinates"
    private static let KEY_IS_ACTIVE   = "is_active"

    // MARK: - Registration (call in AppDelegate before app finishes launching)

    // Call this in AppDelegate.application(_:didFinishLaunchingWithOptions:)
    // BEFORE super.application(...) returns
    static func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: TASK_ID_PERIODIC,
            using: nil
        ) { task in
            handlePeriodicTask(task: task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: TASK_ID_REFRESH,
            using: nil
        ) { task in
            handleRefreshTask(task: task as! BGProcessingTask)
        }
        print("[\(TAG)] Background tasks registered")
    }

    // MARK: - Scheduling

    // Mirrors MainActivity.scheduleConfigWorker() — periodic every 15 min
    static func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: TASK_ID_PERIODIC)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[\(TAG)] Periodic task scheduled")
        } catch {
            print("[\(TAG)] Failed to schedule periodic task: \(error)")
        }
    }

    // Mirrors OneTimeWorkRequest — immediate processing task
    static func scheduleProcessingTask() {
        let request = BGProcessingTaskRequest(identifier: TASK_ID_REFRESH)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = nil // run as soon as possible

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[\(TAG)] Processing task scheduled immediately")
        } catch {
            print("[\(TAG)] Failed to schedule processing task: \(error)")
        }
    }

    static func cancelBackgroundTask() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: TASK_ID_PERIODIC)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: TASK_ID_REFRESH)
        print("[\(TAG)] Background tasks cancelled")
    }

    // MARK: - Task Handlers

    private static func handlePeriodicTask(task: BGAppRefreshTask) {
        print("[\(TAG)] Periodic task running")
        scheduleBackgroundTask() // reschedule next run

        task.expirationHandler = {
            print("[\(TAG)] Periodic task expired")
            task.setTaskCompleted(success: false)
        }

        fetchRemoteConfig { success in
            task.setTaskCompleted(success: success)
        }
    }

    private static func handleRefreshTask(task: BGProcessingTask) {
        print("[\(TAG)] Processing task running")

        task.expirationHandler = {
            print("[\(TAG)] Processing task expired")
            task.setTaskCompleted(success: false)
        }

        fetchRemoteConfig { success in
            task.setTaskCompleted(success: success)
        }
    }

    // MARK: - Run immediately (for testing / app launch check)

    // Mirrors runImmediateConfigCheck() in MainActivity
    static func runNow(completion: (() -> Void)? = nil) {
        print("[\(TAG)] Running config check now")
        fetchRemoteConfig { _ in
            completion?()
        }
    }

    // MARK: - Core Logic (mirrors GeofenceConfigWorker.doWork())

    static func fetchRemoteConfig(completion: @escaping (Bool) -> Void) {
        let isActive = prefs.bool(forKey: KEY_IS_ACTIVE)
        guard isActive else {
            print("[\(TAG)] Not active — skipping")
            completion(true)
            return
        }

        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 0 // always fetch fresh
        remoteConfig.configSettings = settings

        // Set defaults
        remoteConfig.setDefaults([
            "zone_id": "kochi_zone" as NSObject,
            "zone_coordinates": """
            [{"lat":9.9340,"lng":76.2650},{"lat":9.9340,"lng":76.2700},
             {"lat":9.9280,"lng":76.2700},{"lat":9.9280,"lng":76.2650}]
            """ as NSObject
        ])

        remoteConfig.fetchAndActivate { status, error in
            if let error = error {
                print("[\(TAG)] Fetch failed: \(error.localizedDescription)")
                completion(false)
                return
            }

            let newId      = remoteConfig["zone_id"].stringValue ?? "kochi_zone"
            let coordsJson = remoteConfig["zone_coordinates"].stringValue ?? "[]"
            print("[\(TAG)] Fetched — zone: \(newId)")

            guard
                let data = coordsJson.data(using: .utf8),
                let arr  = try? JSONSerialization.jsonObject(with: data) as? [[String: Double]],
                arr.count >= 3
            else {
                print("[\(TAG)] Invalid coordinates JSON")
                completion(false)
                return
            }

            // Calculate center
            let centerLat = arr.map { $0["lat"] ?? 0 }.reduce(0, +) / Double(arr.count)
            let centerLng = arr.map { $0["lng"] ?? 0 }.reduce(0, +) / Double(arr.count)

            // Calculate max radius from center
            var maxRadius = 0.0
            let center = CLLocation(latitude: centerLat, longitude: centerLng)
            for coord in arr {
                let lat = coord["lat"] ?? 0
                let lng = coord["lng"] ?? 0
                let point = CLLocation(latitude: lat, longitude: lng)
                let dist = center.distance(from: point)
                if dist > maxRadius { maxRadius = dist }
            }
            let newRadius = maxRadius > 0 ? maxRadius : 200.0

            // Compare with saved
            let savedId     = prefs.string(forKey: KEY_ZONE_ID) ?? ""
            let savedCoords = prefs.string(forKey: KEY_ZONE_COORDS) ?? ""
            let changed     = newId != savedId || savedCoords != coordsJson

            if changed {
                print("[\(TAG)] Zone changed! \(savedId) → \(newId)")

                // Update UserDefaults (mirrors SharedPreferences update)
                prefs.set(newId,      forKey: KEY_ZONE_ID)
                prefs.set(centerLat,  forKey: KEY_ZONE_LAT)
                prefs.set(centerLng,  forKey: KEY_ZONE_LNG)
                prefs.set(newRadius,  forKey: KEY_ZONE_RADIUS)
                prefs.set(coordsJson, forKey: KEY_ZONE_COORDS)

                // Re-register CLCircularRegion with new zone
                let manager = GeofenceManager()
                manager.addGeofence(id: newId, lat: centerLat, lng: centerLng, radius: newRadius)

                // Notify user of zone change
                notifyZoneChanged(zoneId: newId, lat: centerLat, lng: centerLng, radius: newRadius)

                // Schedule next periodic check
                scheduleBackgroundTask()

            } else {
                print("[\(TAG)] Zone unchanged: \(newId)")
            }

            completion(true)
        }
    }

    // Mirrors GeofenceConfigWorker.notifyZoneChanged()
    private static func notifyZoneChanged(zoneId: String, lat: Double, lng: Double, radius: Double) {
        // Check current location vs new zone
        let locationManager = CLLocationManager()
        if let currentLocation = locationManager.location {
            let zoneCenter = CLLocation(latitude: lat, longitude: lng)
            let distance   = currentLocation.distance(from: zoneCenter)
            let isInside   = distance <= radius

            let title   = isInside ? "📍 Inside new zone" : "🚶 Outside new zone"
            let message = "Zone updated to: \(zoneId)"

            let content = UNMutableNotificationContent()
            content.title = title
            content.body  = message
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "geofence_zone_change",
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("[\(TAG)] Zone change notification error: \(error)")
                } else {
                    print("[\(TAG)] Zone change notification sent — inside: \(isInside)")
                }
            }
        }
    }
}