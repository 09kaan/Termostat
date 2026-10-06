import Flutter
import UIKit
import CoreLocation
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
    
    private let locationManager = CLLocationManager()
    private let regionIdentifier = "home_geofence"
    private var methodChannel: FlutterMethodChannel?
    
    // Firebase REST API (works even when Flutter engine is dead)
    private let firebaseBaseURL = "https://termometer-4b9d6-default-rtdb.europe-west1.firebasedatabase.app"
    private let firebaseSecret = "zHPpeMbreSIUSFwGaR5y9bxv7Tc5FHdW4IDj2ql1"  // Same secret as ESP32/ESP8266
    private let deviceId = "device1"
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        // Setup location manager
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        
        // Setup method channel (safely)
        if let controller = window?.rootViewController as? FlutterViewController {
            methodChannel = FlutterMethodChannel(name: "geofence_channel", binaryMessenger: controller.binaryMessenger)
            
            methodChannel?.setMethodCallHandler { [weak self] (call, result) in
                guard let self = self else { return }
                
                switch call.method {
                case "startMonitoring":
                    if let args = call.arguments as? [String: Any],
                       let lat = args["latitude"] as? Double,
                       let lng = args["longitude"] as? Double,
                       let radius = args["radius"] as? Double {
                        self.startMonitoring(latitude: lat, longitude: lng, radius: radius)
                        result(true)
                    } else {
                        result(FlutterError(code: "INVALID_ARGS", message: "Missing lat/lng/radius", details: nil))
                    }
                    
                case "stopMonitoring":
                    self.stopMonitoring()
                    result(true)
                    
                case "getDistance":
                    if let args = call.arguments as? [String: Any],
                       let lat = args["latitude"] as? Double,
                       let lng = args["longitude"] as? Double {
                        self.getDistanceToHome(latitude: lat, longitude: lng, result: result)
                    } else {
                        result(0.0)
                    }
                    
                case "isMonitoring":
                    let isMonitoring = !locationManager.monitoredRegions.isEmpty
                    result(isMonitoring)
                    
                default:
                    result(FlutterMethodNotImplemented)
                }
            }
        }
        
        // Check if launched by geofence event (iOS woke us up!)
        if let _ = launchOptions?[.location] {
            print("[Geofence] ⚡ App launched by location event!")
        }
        
        // Auto-restore geofence monitoring from saved coordinates
        // This ensures geofence survives app being killed by iOS
        restoreGeofenceIfNeeded()
        
        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            print("[Geofence] Notification permission: \(granted)")
        }
        
        // Enable Background App Refresh (safety net)
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
        print("[Geofence] Background fetch enabled")
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // MARK: - Background App Refresh
    
    override func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("[BGFetch] ⏰ Background fetch triggered")
        
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "geofence_enabled") else {
            print("[BGFetch] Geofence not enabled, skipping")
            completionHandler(.noData)
            return
        }
        
        let homeLat = defaults.double(forKey: "geofence_lat")
        let homeLng = defaults.double(forKey: "geofence_lng")
        let homeRadius = defaults.double(forKey: "geofence_radius")
        
        guard homeLat != 0 && homeLng != 0 else {
            print("[BGFetch] No saved coordinates")
            completionHandler(.noData)
            return
        }
        
        // Get current location
        locationManager.requestLocation()
        
        // Use last known location
        guard let currentLocation = locationManager.location else {
            print("[BGFetch] No location available")
            completionHandler(.failed)
            return
        }
        
        let homeLocation = CLLocation(latitude: homeLat, longitude: homeLng)
        let distance = currentLocation.distance(from: homeLocation)
        let isInside = distance <= homeRadius
        let wasInside = defaults.bool(forKey: "isInsideGeofence")
        
        print("[BGFetch] Distance: \(Int(distance))m, inside: \(isInside), wasInside: \(wasInside)")
        
        // State changed — take action!
        if isInside != wasInside {
            print("[BGFetch] 🔄 State changed! Triggering geofence action")
            defaults.set(isInside, forKey: "isInsideGeofence")
            handleGeofenceEvent(isEntering: isInside)
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
    
    // MARK: - Geofence Management
    
    private func startMonitoring(latitude: Double, longitude: Double, radius: Double) {
        // Stop existing monitoring first
        stopMonitoring()
        
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            print("[Geofence] Region monitoring not available")
            return
        }
        
        // Save coordinates to UserDefaults (persist across app kills)
        let defaults = UserDefaults.standard
        defaults.set(latitude, forKey: "geofence_lat")
        defaults.set(longitude, forKey: "geofence_lng")
        defaults.set(radius, forKey: "geofence_radius")
        defaults.set(true, forKey: "geofence_enabled")
        
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let clampedRadius = min(radius, locationManager.maximumRegionMonitoringDistance)
        let region = CLCircularRegion(center: center, radius: clampedRadius, identifier: regionIdentifier)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        
        locationManager.requestAlwaysAuthorization()
        locationManager.startMonitoring(for: region)
        
        // Also request initial state
        locationManager.requestState(for: region)
        
        print("[Geofence] ✅ Started monitoring: lat=\(latitude), lng=\(longitude), radius=\(clampedRadius)m")
    }
    
    private func stopMonitoring() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        UserDefaults.standard.set(false, forKey: "geofence_enabled")
        print("[Geofence] Stopped all monitoring")
    }
    
    /// Restore geofence monitoring from saved coordinates (after app restart/kill)
    private func restoreGeofenceIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "geofence_enabled") else {
            print("[Geofence] Restore: geofence not enabled, skipping")
            return
        }
        
        // If already monitoring, don't re-register
        if !locationManager.monitoredRegions.isEmpty {
            print("[Geofence] Restore: already monitoring \(locationManager.monitoredRegions.count) region(s)")
            return
        }
        
        let lat = defaults.double(forKey: "geofence_lat")
        let lng = defaults.double(forKey: "geofence_lng")
        let radius = defaults.double(forKey: "geofence_radius")
        
        guard lat != 0 && lng != 0 && radius > 0 else {
            print("[Geofence] Restore: no saved coordinates")
            return
        }
        
        print("[Geofence] 🔄 Restoring geofence from saved coordinates...")
        startMonitoring(latitude: lat, longitude: lng, radius: radius)
    }
    
    private func getDistanceToHome(latitude: Double, longitude: Double, result: @escaping FlutterResult) {
        locationManager.requestLocation()
        
        // Use last known location for quick response
        if let location = locationManager.location {
            let homeLocation = CLLocation(latitude: latitude, longitude: longitude)
            let distance = location.distance(from: homeLocation)
            result(distance)
        } else {
            result(0.0)
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == regionIdentifier else { return }
        print("[Geofence] 🏠 ENTERED home region!")
        
        handleGeofenceEvent(isEntering: true)
        
        // Notify Flutter (if running)
        methodChannel?.invokeMethod("onEnterRegion", arguments: nil)
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == regionIdentifier else { return }
        print("[Geofence] 🚶 EXITED home region!")
        
        handleGeofenceEvent(isEntering: false)
        
        // Notify Flutter (if running)
        methodChannel?.invokeMethod("onExitRegion", arguments: nil)
    }
    
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard region.identifier == regionIdentifier else { return }
        let stateStr = state == .inside ? "inside" : (state == .outside ? "outside" : "unknown")
        print("[Geofence] Region state determined: \(stateStr)")
        
        methodChannel?.invokeMethod("onStateChanged", arguments: ["state": stateStr])
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[Geofence] Location error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("[Geofence] Monitoring failed: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if #available(iOS 14.0, *) {
            print("[Geofence] Authorization changed: \(manager.authorizationStatus.rawValue)")
        } else {
            print("[Geofence] Authorization changed: \(CLLocationManager.authorizationStatus().rawValue)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Used by requestLocation() for distance calculation
    }
    
    // MARK: - Geofence Event Handling
    
    private func handleGeofenceEvent(isEntering: Bool) {
        // Save state
        UserDefaults.standard.set(isEntering, forKey: "isInsideGeofence")
        
        // Show local notification
        let content = UNMutableNotificationContent()
        content.title = "Termostat"
        content.body = isEntering
            ? "Eve hoş geldiniz! Isıtma açılıyor."
            : "Evden ayrıldınız. Eko moda geçiliyor."
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "geofence_\(isEntering ? "enter" : "exit")",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        
        // Update Firebase directly via REST API (works even when Flutter is dead!)
        if isEntering {
            updateFirebase(mode: "on", targetTemp: 25.0)
        } else {
            updateFirebase(mode: "off", targetTemp: 18.0)
        }
    }
    
    private func updateFirebase(mode: String, targetTemp: Double) {
        let url = URL(string: "\(firebaseBaseURL)/devices/\(deviceId).json?auth=\(firebaseSecret)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "mode": mode,
            "targetTemperature": targetTemp,
            "isHeating": mode == "on" ? true : false
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("[Geofence] JSON error: \(error)")
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("[Geofence] Firebase update error: \(error.localizedDescription)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                print("[Geofence] Firebase updated: mode=\(mode), temp=\(targetTemp), status=\(httpResponse.statusCode)")
            }
        }
        task.resume()
    }
}
