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
    private let legacyRegion = "home_geofence"
    private let prefix = "home_v10_"
    private let kinds = ["heatEntry", "heatExit", "lightEntry", "lightExit"]
    private var methodChannel: FlutterMethodChannel?
    private var tasks: [String: Task<Void, Never>] = [:]
    private var backgrounds: [String: UIBackgroundTaskIdentifier] = [:]
    private var tickets: [String: UUID] = [:]
    private var generation = 0
    private let policyKey = "geofence_exit_policy_v1"
    private let resultKey = "geofence_last_result_v1"

    override func application(_ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
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
                    self.configureActions(call.arguments as? [String: Any] ?? [:]); result(true)
                case "startMonitoring":
                    guard let args = call.arguments as? [String: Any],
                          let lat = args["latitude"] as? Double, let lng = args["longitude"] as? Double,
                          let radius = args["radius"] as? Double, radius.isFinite, radius > 0,
                          CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lng)) else {
                        result(FlutterError(code: "INVALID_ARGS", message: "Geçersiz ev konumu", details: nil)); return
                    }
                    result(self.startMonitoring(latitude: lat, longitude: lng, fallback: radius))
                case "stopMonitoring": self.stopMonitoring(); result(true)
                case "getDistance":
                    if let args = call.arguments as? [String: Any], let lat = args["latitude"] as? Double,
                       let lng = args["longitude"] as? Double, let location = self.locationManager.location {
                        result(location.distance(from: CLLocation(latitude: lat, longitude: lng)))
                    } else { result(0.0) }
                case "isMonitoring": result(self.locationManager.monitoredRegions.contains { $0.identifier.hasPrefix(self.prefix) })
                case "getLastAutomationResult": result(UserDefaults.standard.string(forKey: self.resultKey))
                default: result(FlutterMethodNotImplemented)
                }
            }
        }
        restoreGeofenceIfNeeded()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    override func application(_ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        completionHandler(.noData) // Cached GPS samples never manufacture crossings.
    }
    private func validIds(_ value: Any?) -> [String] {
        Array(Set((value as? [String] ?? []).filter { $0.range(of: "^lamp[1-8]$", options: .regularExpression) != nil })).sorted()
    }
    private func configureActions(_ args: [String: Any]) {
        let defaults = UserDefaults.standard
        let owner = args["ownerUid"] as? String ?? ""
        let departure = validIds(args["lightIds"]), arrival = validIds(args["entryLightIds"])
        let departureIPs = args["lightIPs"] as? [String:String] ?? [:]
        let arrivalIPs = args["entryLightIPs"] as? [String:String] ?? [:]
        var policy: [String: Any] = ["version": 2,
            "enabled": (args["enabled"] as? Bool ?? false) && !owner.isEmpty,
            "ownerUid": owner, "heating": args["heating"] as? Bool ?? true,
            "entryHeating": args["entryHeating"] as? Bool ?? true,
            "lightIds": departure, "lightIPs": departureIPs.filter { departure.contains($0.key) },
            "entryLightIds": arrival, "entryLightIPs": arrivalIPs.filter { arrival.contains($0.key) }]
        for kind in kinds {
            let radius = args[kind] as? Double ?? 200
            policy[kind] = radius.isFinite ? max(50, min(2000, radius)) : 200
        }
        // Keep exit outside entry, including malformed/legacy saved policies.
        policy["heatExit"] = max(policy["heatEntry"] as! Double, policy["heatExit"] as! Double)
        policy["lightExit"] = max(policy["lightEntry"] as! Double, policy["lightExit"] as! Double)
        let previous = defaults.dictionary(forKey: policyKey) ?? [:]
        if !NSDictionary(dictionary: previous).isEqual(to: policy) {
            cancelAllTasks()
            if previous["ownerUid"] as? String != owner {
                for kind in kinds { defaults.removeObject(forKey: prefix + kind + "_inside") }
                defaults.removeObject(forKey: "isInsideGeofence")
            }
            defaults.set(policy, forKey: policyKey)
            if policy["enabled"] as? Bool != true { stopMonitoring() }
            else if defaults.bool(forKey: "geofence_enabled") {
                _ = startMonitoring(latitude: defaults.double(forKey: "geofence_lat"),
                    longitude: defaults.double(forKey: "geofence_lng"), fallback: defaults.double(forKey: "geofence_radius"))
            }
        }
    }
    @discardableResult
    private func startMonitoring(latitude: Double, longitude: Double, fallback: Double) -> Bool {
        let defaults = UserDefaults.standard
        guard CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)),
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self),
              let policy = defaults.dictionary(forKey: policyKey), policy["enabled"] as? Bool == true,
              locationManager.maximumRegionMonitoringDistance > 0 else { return false }
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        for old in locationManager.monitoredRegions where old.identifier == legacyRegion {
            locationManager.stopMonitoring(for: old)
        }
        for kind in kinds {
            let id = prefix + kind
            let requested = policy[kind] as? Double ?? max(50, fallback)
            let radius = min(max(50, requested), locationManager.maximumRegionMonitoringDistance)
            if let existing = locationManager.monitoredRegions.first(where: { $0.identifier == id }) as? CLCircularRegion,
                existing.center.latitude == latitude, existing.center.longitude == longitude, existing.radius == radius {
                continue
            }
            if let old = locationManager.monitoredRegions.first(where: { $0.identifier == id }) {
                locationManager.stopMonitoring(for: old)
            }
            defaults.removeObject(forKey: id + "_inside")
            let region = CLCircularRegion(center: center, radius: radius, identifier: id)
            region.notifyOnEntry = true; region.notifyOnExit = true // Opposite edge re-arms this region.
            locationManager.requestAlwaysAuthorization()
            locationManager.startMonitoring(for: region)
            locationManager.requestState(for: region)
        }
        defaults.set(latitude, forKey: "geofence_lat"); defaults.set(longitude, forKey: "geofence_lng")
        defaults.set(fallback, forKey: "geofence_radius"); defaults.set(true, forKey: "geofence_enabled")
        return true
    }
    private func stopMonitoring() {
        for region in locationManager.monitoredRegions where region.identifier == legacyRegion || region.identifier.hasPrefix(prefix) {
            locationManager.stopMonitoring(for: region)
        }
        UserDefaults.standard.set(false, forKey: "geofence_enabled"); cancelAllTasks()
    }
    private func restoreGeofenceIfNeeded() {
        let d = UserDefaults.standard
        guard d.bool(forKey: "geofence_enabled") else { return }
        _ = startMonitoring(latitude:d.double(forKey:"geofence_lat"), longitude:d.double(forKey:"geofence_lng"),
                            fallback:max(50,d.double(forKey:"geofence_radius")))
    }
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard region.identifier.hasPrefix(prefix), state != .unknown else { return }
        // First baseline / app reopen / radius change never sends a command.
        UserDefaults.standard.set(state == .inside, forKey: region.identifier + "_inside")
        if region.identifier == prefix + "heatEntry" {
            UserDefaults.standard.set(state == .inside, forKey:"isInsideGeofence")
            methodChannel?.invokeMethod("onStateChanged", arguments:["state":state == .inside ? "inside":"outside"])
        }
    }
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) { crossing(region, entering:true) }
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) { crossing(region, entering:false) }
    private func crossing(_ region: CLRegion, entering: Bool) {
        let d = UserDefaults.standard
        guard region.identifier.hasPrefix(prefix), d.bool(forKey:"geofence_enabled"),
              let policy=d.dictionary(forKey:policyKey), policy["enabled"] as? Bool == true else { return }
        let kind=String(region.identifier.dropFirst(prefix.count))
        guard kinds.contains(kind) else { return }
        let previous=d.object(forKey:region.identifier+"_inside") as? Bool
        d.set(entering,forKey:region.identifier+"_inside")
        guard let previous=previous, previous != entering else { return }
        if kind == "heatEntry" {
            d.set(entering,forKey:"isInsideGeofence")
            methodChannel?.invokeMethod(entering ? "onEnterRegion":"onExitRegion",arguments:nil)
        }
        guard (kind.hasSuffix("Entry") && entering) || (kind.hasSuffix("Exit") && !entering) else { return }
        runActions(kind:kind, entering:entering, policy:policy)
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { publishResult("Konum hizmeti kullanılamıyor; yeni otomasyon doğrulanamadı.") }
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        publishResult("Konum bölgesi izlenemedi. Konum iznini ve iOS ayarlarını kontrol et.")
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
    private func finish(_ key: String) {
        tasks[key]=nil; tickets[key]=nil
        if let id=backgrounds.removeValue(forKey:key), id != .invalid { UIApplication.shared.endBackgroundTask(id) }
    }
    private func cancelAllTasks() {
        generation += 1; tickets.removeAll()
        for task in tasks.values { task.cancel() }; tasks.removeAll()
        for id in backgrounds.values where id != .invalid { UIApplication.shared.endBackgroundTask(id) }
        backgrounds.removeAll()
    }
    private func runActions(kind: String, entering: Bool, policy: [String:Any]) {
        guard let owner=policy["ownerUid"] as? String, !owner.isEmpty, tasks[kind] == nil else { return }
        let heating=kind.hasPrefix("heat") && (policy[entering ? "entryHeating":"heating"] as? Bool ?? true)
        let lights=kind.hasPrefix("light") ? validIds(policy[entering ? "entryLightIds":"lightIds"]) : []
        guard heating || !lights.isEmpty else { return }
        let revision=generation, ticket=UUID()
        tickets[kind]=ticket
        backgrounds[kind]=UIApplication.shared.beginBackgroundTask(withName:"Geofence_"+kind) { [weak self] in
            guard let self=self, self.generation == revision, self.tickets[kind] == ticket else { return }
            self.tasks[kind]?.cancel(); self.finish(kind)
            self.publishResult("iOS arka plan süresi bitti; konum talebinin tamamlanması doğrulanamadı.")
        }
        tasks[kind]=Task { @MainActor [weak self] in
            guard let self=self else { return }
            defer { if self.generation == revision, self.tickets[kind] == ticket { self.finish(kind) } }
            do {
                try await self.ensureOwner(owner)
                if heating {
                    // Controller alone arbitrates automations vs Manual. Never overwrite mode here.
                    let now=Int64(Date().timeIntervalSince1970 * 1000)
                    var request:[String:Any]=["id":UUID().uuidString,"mode":entering ? "on":"off",
                        "issuedAt":[".sv":"timestamp"],"requestedAt":now,"ttlMs":60000,
                        "source":entering ? "geofence_entry":"geofence_exit","handled":false]
                    if entering { request["targetTemperature"]=25.0 } // Preserve V9.1 arrival target.
                    _ = try await self.firebaseRequest(owner:owner,path:"devices/device1/control/automation",method:"PUT",body:request)
                    try Task.checkCancellation()
                    if self.generation == revision { self.publishResult(entering
                        ? "Eve dönüş: 25 °C ısıtma talebi gönderildi. Manuel modda ESP32 talebi uygulamaz."
                        : "Evden çıkış: kapatma talebi gönderildi; cihaz onayını ana ekrandan izle.") }
                } else {
                    let count=try await self.sendLightCommands(owner:owner,ids:lights,
                        expectedIPs:policy[entering ? "entryLightIPs":"lightIPs"] as? [String:String] ?? [:],on:entering)
                    try Task.checkCancellation()
                    if self.generation == revision { self.publishResult(count > 0
                        ? "\(count) ışığa \(entering ? "açma":"kapatma") komutu gönderildi; ampul onayını Evim'den izle."
                        : "Seçili ışıklar/IP eşleşmeleri bulunamadı; komut gönderilmedi.") }
                }
            } catch {
                guard !Task.isCancelled, self.generation == revision else { return }
                self.publishResult("Konum talebi doğrulanamadı. Oturumu ve internet bağlantısını kontrol et.")
            }
        }
    }
    private func ensureOwner(_ expected: String) async throws {
        try Task.checkCancellation()
        guard !WidgetSnapshotStore.explicitlySignedOut else { throw ThermostatCommandError.signInRequired }
        try await FirebaseAuthSessionProvider().ensureUserAuthenticated(timeout:5)
        try Task.checkCancellation()
        let app=try ThermostatFirebaseConfig.configuredFirebaseApp()
        guard Auth.auth(app:app).currentUser?.uid == expected else { throw ThermostatCommandError.signInRequired }
    }
    private func sendLightCommands(owner:String,ids:[String],expectedIPs:[String:String],on:Bool) async throws -> Int {
        let data=try await firebaseRequest(owner:owner,path:"wizHomes/\(owner)/config/lights",method:"GET")
        let raw=try JSONSerialization.jsonObject(with:data,options:[.fragmentsAllowed])
        let configured=raw as? [String:Any] ?? [:]
        let valid=ids.filter { id in
            guard let expected=expectedIPs[id], let config=configured[id] as? [String:Any],
                  config["ip"] as? String == expected else { return false }; return true
        }
        guard !valid.isEmpty else { return 0 }
        var updates:[String:Any]=[:]
        let now=Int64(Date().timeIntervalSince1970 * 1000)
        for id in valid { updates["wizHomes/\(owner)/commands/\(id)"]=["id":UUID().uuidString,
            "issuedAt":[".sv":"timestamp"],"requestedAt":now,"ttlMs":60000,"params":["state":on]] }
        _ = try await firebaseRequest(owner:owner,path:"",method:"PATCH",body:updates)
        return valid.count
    }
    private func firebaseRequest(owner:String,path:String,method:String,body:[String:Any]?=nil) async throws -> Data {
        let auth=FirebaseAuthSessionProvider(), databaseURL=try ThermostatFirebaseConfig.databaseURL()
        let bytes=try body.map { try JSONSerialization.data(withJSONObject:$0) }
        for attempt in 0..<2 {
            try await ensureOwner(owner)
            let token=try await auth.getValidIDToken(forcingRefresh:attempt == 1)
            try await ensureOwner(owner)
            guard var c=URLComponents(string:databaseURL), c.scheme == "https", let host=c.host,
                  c.user == nil,c.password == nil,
                  host.hasSuffix(".firebasedatabase.app") || host.hasSuffix(".firebaseio.com") else { throw ThermostatCommandError.invalidDatabaseURL }
            c.path="/"+path+".json";c.queryItems=[URLQueryItem(name:"auth",value:token)];c.fragment=nil
            guard let url=c.url else { throw ThermostatCommandError.invalidDatabaseURL }
            var request=URLRequest(url:url);request.httpMethod=method;request.httpBody=bytes;request.timeoutInterval=7
            request.setValue("application/json",forHTTPHeaderField:"Content-Type")
            let (data,response)=try await URLSession.shared.data(for:request)
            try Task.checkCancellation()
            guard let http=response as? HTTPURLResponse else { throw ThermostatCommandError.invalidResponse }
            if http.statusCode == 401 && attempt == 0 { continue }
            guard (200..<300).contains(http.statusCode) else { throw ThermostatCommandError.requestFailed(http.statusCode) }
            return data
        }
        throw ThermostatCommandError.authorizationDenied
    }
    private func publishResult(_ message:String) {
        UserDefaults.standard.set(message,forKey:resultKey)
        methodChannel?.invokeMethod("onAutomationResult",arguments:["message":message])
        let content=UNMutableNotificationContent();content.title="Termostat · Konum otomasyonu";content.body=message;content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:"geofence_result",content:content,trigger:nil))
    }
}
