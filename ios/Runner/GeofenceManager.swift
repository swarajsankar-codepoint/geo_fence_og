import Foundation
import CoreLocation
import UserNotifications

// Mirrors GeofenceManager.kt
// Uses CLLocationManager instead of GeofencingClient
class GeofenceManager: NSObject, CLLocationManagerDelegate {

    private let locationManager = CLLocationManager()
    private let TAG = "GeofenceManager"

    // Mirrors SharedPreferences "geofence_prefs"
    private let prefs = UserDefaults.standard
    private let KEY_ZONE_ID      = "zone_id"
    private let KEY_ZONE_LAT     = "zone_lat"
    private let KEY_ZONE_LNG     = "zone_lng"
    private let KEY_ZONE_RADIUS  = "zone_radius"
    private let KEY_IS_ACTIVE    = "is_active"

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        // Request always authorization — required for terminated app monitoring
        locationManager.requestAlwaysAuthorization()
        // Allow background location updates
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    // Mirrors GeofenceManager.addGeofence()
    func addGeofence(id: String, lat: Double, lng: Double, radius: Double) {
        print("[\(TAG)] addGeofence — id=\(id) lat=\(lat) lng=\(lng) radius=\(radius)")

        // Save to UserDefaults (mirrors SharedPreferences)
        prefs.set(id,     forKey: KEY_ZONE_ID)
        prefs.set(lat,    forKey: KEY_ZONE_LAT)
        prefs.set(lng,    forKey: KEY_ZONE_LNG)
        prefs.set(radius, forKey: KEY_ZONE_RADIUS)
        prefs.set(true,   forKey: KEY_IS_ACTIVE)
        print("[\(TAG)] Saved to UserDefaults")

        // Remove old region first
        removeAllRegions()

        // Register new CLCircularRegion (iOS equivalent of GeofencingClient)
        let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let region = CLCircularRegion(
            center: center,
            radius: CLLocationDistance(radius),
            identifier: id
        )
        region.notifyOnEntry = true
        region.notifyOnExit  = true

        // Check authorization before monitoring
        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways else {
            print("[\(TAG)] ❌ Need 'Always' location permission, current: \(status.rawValue)")
            locationManager.requestAlwaysAuthorization()
            return
        }

        // iOS limit: max 20 monitored regions
        if locationManager.monitoredRegions.count >= 20 {
            print("[\(TAG)] ⚠️ Max 20 regions reached, removing oldest")
            if let oldest = locationManager.monitoredRegions.first {
                locationManager.stopMonitoring(for: oldest)
            }
        }

        locationManager.startMonitoring(for: region)
        print("[\(TAG)] ✅ Region monitoring started: \(id)")
    }

    // Mirrors GeofenceManager.removeGeofence()
    func removeGeofence(id: String) {
        print("[\(TAG)] removeGeofence — id=\(id)")
        prefs.set(false, forKey: KEY_IS_ACTIVE)
        removeAllRegions()
    }

    // Mirrors GeofenceManager.restoreIfActive()
    func restoreIfActive() {
        let isActive = prefs.bool(forKey: KEY_IS_ACTIVE)
        print("[\(TAG)] restoreIfActive — isActive=\(isActive)")
        guard isActive else { return }

        let id     = prefs.string(forKey: KEY_ZONE_ID) ?? ""
        let lat    = prefs.double(forKey: KEY_ZONE_LAT)
        let lng    = prefs.double(forKey: KEY_ZONE_LNG)
        let radius = prefs.double(forKey: KEY_ZONE_RADIUS)

        print("[\(TAG)] Restoring geofence: \(id) at \(lat),\(lng) radius=\(radius)")
        addGeofence(id: id, lat: lat, lng: lng, radius: radius)
    }

    private func removeAllRegions() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
    }

    // MARK: - CLLocationManagerDelegate

    // Mirrors GeofenceBroadcastReceiver — ENTER transition
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("[\(TAG)] ENTERED: \(region.identifier)")
        showNotification(title: "📍 Entered zone", body: "You entered: \(region.identifier)")
        // Trigger config check on boundary crossing — mirrors scheduleImmediateConfigCheck()
        GeofenceConfigWorker.runNow()
    }

    // Mirrors GeofenceBroadcastReceiver — EXIT transition
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("[\(TAG)] EXITED: \(region.identifier)")
        showNotification(title: "🚶 Exited zone", body: "You exited: \(region.identifier)")
        GeofenceConfigWorker.runNow()
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("[\(TAG)] Monitoring failed: \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[\(TAG)] Location error: \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("[\(TAG)] Authorization changed: \(status.rawValue)")
        if status == .authorizedAlways {
            restoreIfActive()
        }
    }

    // MARK: - Notifications

    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "geofence_1001", // fixed ID — replaces previous
            content: content,
            trigger: nil // show immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[\(self.TAG)] Notification error: \(error.localizedDescription)")
            }
        }
    }
}