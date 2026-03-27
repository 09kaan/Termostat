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
        
        // Setup method channel
        let controller = window?.rootViewController as! FlutterViewController
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
        
        // Check if launched by geofence event
        if let _ = launchOptions?[.location] {
            print("[Geofence] App launched by location event!")
            // Location manager delegate will be called automatically
        }
        
        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            print("[Geofence] Notification permission: \(granted)")
        }
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // MARK: - Geofence Management
    
    private func startMonitoring(latitude: Double, longitude: Double, radius: Double) {
        // Stop existing monitoring first
        stopMonitoring()
        
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            print("[Geofence] Region monitoring not available")
            return
        }
        
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let clampedRadius = min(radius, locationManager.maximumRegionMonitoringDistance)
        let region = CLCircularRegion(center: center, radius: clampedRadius, identifier: regionIdentifier)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        
        locationManager.requestAlwaysAuthorization()
        locationManager.startMonitoring(for: region)
        
        // Also request initial state
        locationManager.requestState(for: region)
        
        print("[Geofence] Started monitoring: lat=\(latitude), lng=\(longitude), radius=\(clampedRadius)m")
    }
    
    private func stopMonitoring() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        print("[Geofence] Stopped all monitoring")
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
        let url = URL(string: "\(firebaseBaseURL)/devices/\(deviceId).json")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "mode": mode,
            "targetTemperature": targetTemp
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
