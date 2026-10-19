import Foundation
import Flutter
import UIKit
import CoreLocation
import UserNotifications
import FirebaseCore
import FirebaseAuth

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let regionIdentifier = "home_geofence"
    private var methodChannel: FlutterMethodChannel?
    private var commandTask: Task<Void, Never>?
    private var commandGeneration = 0
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private let policyKey = "geofence_exit_policy_v1"
    private let resultKey = "geofence_last_result_v1"

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        if let controller = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(name: "geofence_channel", binaryMessenger: controller.binaryMessenger)
            methodChannel = channel
            channel.setMethodCallHandler { [weak self] call, result in
                guard let self = self else { return }
                switch call.method {
                case "configureExitActions":
                    self.configureActions(call.arguments as? [String: Any] ?? [:])
                    result(true)
                case "startMonitoring":
                    guard let args = call.arguments as? [String: Any],
                          let lat = args["latitude"] as? Double,
                          let lng = args["longitude"] as? Double,
                          let radius = args["radius"] as? Double,
                          CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lng)),
                          radius > 0 else {
                        result(FlutterError(code: "INVALID_ARGS", message: "Invalid home region", details: nil)); return
                    }
                    result(self.startMonitoring(latitude: lat, longitude: lng, radius: radius))
                case "stopMonitoring":
                    self.stopMonitoring(); result(true)
                case "getDistance":
                    if let args = call.arguments as? [String: Any],
                       let lat = args["latitude"] as? Double, let lng = args["longitude"] as? Double,
                       let location = self.locationManager.location {
                        result(location.distance(from: CLLocation(latitude: lat, longitude: lng)))
                    } else { result(0.0) }
                case "isMonitoring":
                    result(self.locationManager.monitoredRegions.contains { $0.identifier == self.regionIdentifier })
                case "getLastAutomationResult":
                    result(UserDefaults.standard.string(forKey: self.resultKey))
                default: result(FlutterMethodNotImplemented)
                }
            }
        }
        restoreGeofenceIfNeeded()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // A cached location must NOT be treated as a new boundary crossing.
    // CLLocationManager's region callbacks are the authoritative trigger.
    override func application(_ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        completionHandler(.noData)
    }

    private func configureActions(_ args: [String: Any]) {
        let owner = args["ownerUid"] as? String ?? ""
        let lights = Array(Set((args["lightIds"] as? [String] ?? []).filter {
            $0.range(of: "^lamp[1-8]$", options: .regularExpression) != nil
        })).sorted()
        let ips = args["lightIPs"] as? [String: String] ?? [:]
        let policy: [String: Any] = [
            "enabled": (args["enabled"] as? Bool ?? false) && !owner.isEmpty,
            "ownerUid": owner,
            "heating": args["heating"] as? Bool ?? true,
            "lightIds": lights,
            "lightIPs": ips.filter { lights.contains($0.key) }
        ]
        let defaults = UserDefaults.standard
        let previous = defaults.dictionary(forKey: policyKey) ?? [:]
        if !NSDictionary(dictionary: previous).isEqual(to: policy) {
            cancelNativeTask()
            if (previous["ownerUid"] as? String) != owner {
                defaults.removeObject(forKey: "isInsideGeofence")
            }
            defaults.set(policy, forKey: policyKey)
        }
    }

    @discardableResult
    private func startMonitoring(latitude: Double, longitude: Double, radius: Double) -> Bool {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self),
              let policy = UserDefaults.standard.dictionary(forKey: policyKey),
              policy["enabled"] as? Bool == true else { return false }
        let defaults = UserDefaults.standard
        let maximum = locationManager.maximumRegionMonitoringDistance
        guard maximum > 0 else { return false }
        let clamped = min(radius, maximum)
        // Theme/checkbox changes must not reset the region or manufacture a crossing.
        if defaults.bool(forKey: "geofence_enabled"),
           defaults.double(forKey: "geofence_lat") == latitude,
           defaults.double(forKey: "geofence_lng") == longitude,
           defaults.double(forKey: "geofence_radius") == clamped,
           locationManager.monitoredRegions.contains(where: { $0.identifier == regionIdentifier }) {
            return true
        }
        for region in locationManager.monitoredRegions where region.identifier == regionIdentifier {
            locationManager.stopMonitoring(for: region)
        }
        defaults.removeObject(forKey: "isInsideGeofence")
        defaults.set(latitude, forKey: "geofence_lat")
        defaults.set(longitude, forKey: "geofence_lng")
        defaults.set(clamped, forKey: "geofence_radius")
        defaults.set(true, forKey: "geofence_enabled")
        let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                      radius: clamped, identifier: regionIdentifier)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        locationManager.requestAlwaysAuthorization()
        locationManager.startMonitoring(for: region)
        locationManager.requestState(for: region)
        return true
    }

    private func stopMonitoring() {
        for region in locationManager.monitoredRegions where region.identifier == regionIdentifier {
            locationManager.stopMonitoring(for: region)
        }
        UserDefaults.standard.set(false, forKey: "geofence_enabled")
        cancelNativeTask()
    }

    private func restoreGeofenceIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "geofence_enabled"),
              !locationManager.monitoredRegions.contains(where: { $0.identifier == regionIdentifier }) else { return }
        let lat = defaults.double(forKey: "geofence_lat")
        let lng = defaults.double(forKey: "geofence_lng")
        let radius = defaults.double(forKey: "geofence_radius")
        guard CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lng)), radius > 0 else { return }
        startMonitoring(latitude: lat, longitude: lng, radius: radius)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == regionIdentifier else { return }
        transition(isEntering: true, initialState: false)
        methodChannel?.invokeMethod("onEnterRegion", arguments: nil)
    }
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == regionIdentifier else { return }
        transition(isEntering: false, initialState: false)
        methodChannel?.invokeMethod("onExitRegion", arguments: nil)
    }
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard region.identifier == regionIdentifier else { return }
        if state != .unknown { transition(isEntering: state == .inside, initialState: true) }
        let text = state == .inside ? "inside" : (state == .outside ? "outside" : "unknown")
        methodChannel?.invokeMethod("onStateChanged", arguments: ["state": text])
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[Geofence] Location unavailable")
    }
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("[Geofence] Region monitoring unavailable")
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}

    private func transition(isEntering: Bool, initialState: Bool) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "geofence_enabled"),
              let policy = defaults.dictionary(forKey: policyKey), policy["enabled"] as? Bool == true else { return }
        let previous = defaults.object(forKey: "isInsideGeofence") as? Bool
        defaults.set(isEntering, forKey: "isInsideGeofence")
        // First installation/reconfiguration records a baseline, not an action.
        if initialState && previous == nil { return }
        guard previous != isEntering else { return }
        runActions(isEntering: isEntering, policy: policy)
    }

    private func cancelNativeTask() {
        commandGeneration += 1
        commandTask?.cancel()
        commandTask = nil
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    private func finishNativeTask(_ generation: Int) {
        guard generation == commandGeneration else { return }
        commandTask = nil
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }

    private func runActions(isEntering: Bool, policy: [String: Any]) {
        guard let owner = policy["ownerUid"] as? String, !owner.isEmpty else { return }
        let heating = isEntering || (policy["heating"] as? Bool ?? true)
        let lights = isEntering ? [] : (policy["lightIds"] as? [String] ?? [])
        guard heating || !lights.isEmpty else {
            publishResult("Evden çıkışta kapatılacak cihaz seçili değil; komut gönderilmedi.")
            return
        }
        cancelNativeTask()
        let generation = commandGeneration
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "GeofenceActions") { [weak self] in
            guard let self = self, self.commandGeneration == generation else { return }
            self.commandTask?.cancel()
            self.publishResult("Konum komutlarının tamamlanması doğrulanamadı; iOS arka plan süresi bitti.")
            self.finishNativeTask(generation)
        }
        commandTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer { self.finishNativeTask(generation) }
            var results: [String] = []
            do {
                try await self.ensureOwner(owner)
                if heating {
                    do {
                        // Preserve existing arrival behaviour (25 C); departure only turns OFF.
                        let command: ThermostatHeatingCommand = isEntering ? .setTemperature(25.0) : .turnOff
                        try await ThermostatCommandService.send(command, authProvider: GeofenceOwnerAuthProvider(owner: owner))
                        try Task.checkCancellation()
                        try await self.ensureOwner(owner)
                        WidgetSnapshotStore.recordAccepted(command)
                        results.append(isEntering ? "25 derece ısıtma komutu gönderildi" : "kombi kapatma komutu gönderildi")
                    } catch {
                        try Task.checkCancellation()
                        results.append("kombi komutu doğrulanamadı")
                    }
                }
                if !lights.isEmpty {
                    do {
                        let count = try await self.sendLightOffCommands(owner: owner, ids: lights,
                            expectedIPs: policy["lightIPs"] as? [String: String] ?? [:])
                        results.append(count > 0 ? "\(count) ışığa kapatma komutu gönderildi" : "seçili ışıklar listede bulunamadı")
                    } catch {
                        try Task.checkCancellation()
                        results.append("ışık komutları doğrulanamadı")
                    }
                }
                try Task.checkCancellation()
                guard generation == self.commandGeneration else { return }
                self.publishResult((isEntering ? "Eve dönüş: " : "Evden çıkış: ") + results.joined(separator: "; ") + ".")
            } catch {
                guard !Task.isCancelled, generation == self.commandGeneration else { return }
                self.publishResult("Konum komutu gönderilemedi; uygulamadaki oturumu ve internet bağlantısını kontrol et.")
            }
        }
    }

    private func ensureOwner(_ expected: String) async throws {
        try Task.checkCancellation()
        guard !WidgetSnapshotStore.explicitlySignedOut else { throw ThermostatCommandError.signInRequired }
        try await FirebaseAuthSessionProvider().ensureUserAuthenticated(timeout: 5)
        try Task.checkCancellation()
        let app = try ThermostatFirebaseConfig.configuredFirebaseApp()
        guard Auth.auth(app: app).currentUser?.uid == expected else { throw ThermostatCommandError.signInRequired }
    }

    private func sendLightOffCommands(owner: String, ids: [String], expectedIPs: [String: String]) async throws -> Int {
        // Fetch current config so a deleted selection doesn't invalidate the whole batch.
        let data = try await firebaseRequest(owner: owner, path: "wizHomes/\(owner)/config/lights", method: "GET")
        let raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let configured = raw as? [String: Any] ?? [:]
        let valid = ids.filter { id in
            guard id.range(of: "^lamp[1-8]$", options: .regularExpression) != nil,
                  let expected = expectedIPs[id],
                  let config = configured[id] as? [String: Any],
                  config["ip"] as? String == expected else { return false }
            return true
        }
        guard !valid.isEmpty else { return 0 }
        var updates: [String: Any] = [:]
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for id in valid {
            updates["wizHomes/\(owner)/commands/\(id)"] = [
                "id": UUID().uuidString,
                "issuedAt": [".sv": "timestamp"],
                "requestedAt": now,
                "ttlMs": 60000,
                "params": ["state": false]
            ]
        }
        _ = try await firebaseRequest(owner: owner, path: "", method: "PATCH", body: updates)
        return valid.count
    }

    private func firebaseRequest(owner: String, path: String, method: String, body: [String: Any]? = nil) async throws -> Data {
        let auth = FirebaseAuthSessionProvider()
        let databaseURL = try ThermostatFirebaseConfig.databaseURL()
        let bytes = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        for attempt in 0..<2 {
            try await ensureOwner(owner)
            let token = try await auth.getValidIDToken(forcingRefresh: attempt == 1)
            try await ensureOwner(owner)
            guard var components = URLComponents(string: databaseURL), components.scheme == "https",
                  let host = components.host, components.user == nil, components.password == nil,
                  host.hasSuffix(".firebasedatabase.app") || host.hasSuffix(".firebaseio.com") else {
                throw ThermostatCommandError.invalidDatabaseURL
            }
            components.path = "/" + path + ".json"
            components.queryItems = [URLQueryItem(name: "auth", value: token)]
            components.fragment = nil
            guard let url = components.url else { throw ThermostatCommandError.invalidDatabaseURL }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.httpBody = bytes
            request.timeoutInterval = 7
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw ThermostatCommandError.invalidResponse }
            if http.statusCode == 401 && attempt == 0 { continue }
            guard (200..<300).contains(http.statusCode) else {
                throw ThermostatCommandError.requestFailed(http.statusCode)
            }
            return data
        }
        throw ThermostatCommandError.authorizationDenied
    }

    private func publishResult(_ message: String) {
        UserDefaults.standard.set(message, forKey: resultKey)
        methodChannel?.invokeMethod("onAutomationResult", arguments: ["message": message])
        let content = UNMutableNotificationContent()
        content.title = "Termostat · Konum otomasyonu"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: "geofence_result", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// Bind every token to the selected app owner, including after session restoration.
// This prevents a login switch during an awaited SDK call using another account.
private final class GeofenceOwnerAuthProvider: ThermostatAuthSessionProviding {
    private let owner: String
    private let base = FirebaseAuthSessionProvider()
    init(owner: String) { self.owner = owner }
    private func checkOwner() throws {
        try Task.checkCancellation()
        guard !WidgetSnapshotStore.explicitlySignedOut else { throw ThermostatCommandError.signInRequired }
        let app = try ThermostatFirebaseConfig.configuredFirebaseApp()
        guard Auth.auth(app: app).currentUser?.uid == owner else { throw ThermostatCommandError.signInRequired }
    }
    func ensureUserAuthenticated(timeout: TimeInterval) async throws {
        try await base.ensureUserAuthenticated(timeout: timeout)
        try checkOwner()
    }
    func getValidIDToken(forcingRefresh: Bool) async throws -> String {
        try checkOwner()
        let token = try await base.getValidIDToken(forcingRefresh: forcingRefresh)
        try checkOwner()
        return token
    }
}
