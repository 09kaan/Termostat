import Foundation
import CoreFoundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Only thermostat display data is stored here. Never store auth tokens in UserDefaults.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    var temperature: Double?
    var humidity: Double?
    var targetTemperature: Double?
    var mode: String?
    var isHeating: Bool?
    var observedAtMilliseconds: Double?
    var commandAtMilliseconds: Double?

    var observedDate: Date? {
        observedAtMilliseconds.map { Date(timeIntervalSince1970: $0 / 1000) }
    }
    var hasPendingCommand: Bool {
        guard let commandAtMilliseconds = commandAtMilliseconds else { return false }
        return commandAtMilliseconds > (observedAtMilliseconds ?? 0)
    }
    var isStale: Bool {
        guard let date = observedDate else { return true }
        return Date().timeIntervalSince(date) > 15 * 60
    }

    static func fromDeviceJSON(_ data: Data, now: Date = Date()) throws -> WidgetSnapshot {
        guard data.count <= 2 * 1024 * 1024,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ThermostatCommandError.invalidResponse
        }
        func number(_ key: String, range: ClosedRange<Double>) -> Double? {
            guard let value = json[key] as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            let result = value.doubleValue
            return result.isFinite && range.contains(result) ? result : nil
        }
        let control = json["control"] as? [String: Any] ?? [:]
        let rawMode = control["mode"] as? String ?? json["mode"] as? String
        let mode = ["on", "off", "manual"].contains(rawMode ?? "") ? rawMode : nil
        // Never treat the commanded legacy isHeating value as an ESP8266 ACK.
        let heating = verifiedOutput(json, now: now)
        let canonicalTarget = (control["targetTemperature"] as? NSNumber)?.doubleValue
        let target = canonicalTarget.flatMap { $0.isFinite && (10...30).contains($0) ? $0 : nil }
        return WidgetSnapshot(
            temperature: number("currentTemperature", range: -40...85),
            humidity: number("currentHumidity", range: 0...100) ?? number("humidity", range: 0...100),
            targetTemperature: target ?? number("targetTemperature", range: 10...30),
            mode: mode,
            isHeating: heating,
            observedAtMilliseconds: now.timeIntervalSince1970 * 1000,
            commandAtMilliseconds: nil
        )
    }
    private static func verifiedOutput(_ json: [String: Any], now: Date) -> Bool? {
        let ms = now.timeIntervalSince1970 * 1000
        func fresh(_ raw: Any?, _ age: Double) -> Bool {
            guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return false }
            let v = n.doubleValue
            return v.isFinite && v >= 1704067200000 && ms - v >= -5000 && ms - v <= age
        }
        func boolean(_ raw: Any?) -> Bool? {
            guard let n = raw as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
            return n.boolValue
        }
        let all = json["feedback"] as? [String: Any] ?? [:]
        let c = all["controller"] as? [String: Any] ?? [:]
        let r = all["relay"] as? [String: Any] ?? [:]
        let q = all["relayRequest"] as? [String: Any] ?? [:]
        let control = json["control"] as? [String: Any] ?? [:]
        guard c["protocol"] as? Int == 1, r["protocol"] as? Int == 1,
              fresh(c["lastSeen"],75000), fresh(r["lastSeen"],75000), fresh(c["measurementAt"],90000),
              boolean(c["sensorValid"]) == true, boolean(c["controlReady"]) == true,
              let session=c["sessionId"] as? String, !session.isEmpty,
              let relaySession=r["sessionId"] as? String, !relaySession.isEmpty,
              let id=c["controlId"] as? String, !id.isEmpty,
              let decision=c["decisionId"] as? String, !decision.isEmpty,
              let mode=c["mode"] as? String, ["on","off","manual"].contains(mode),
              let requested=boolean(c["requestedOn"]), let output=boolean(r["outputOn"]),
              r["reason"] as? String == "applied", fresh(r["appliedAt"],366*24*3600000),
              q["id"] as? String == decision, q["controlId"] as? String == id,
              q["controllerSession"] as? String == session, q["mode"] as? String == mode,
              boolean(q["on"]) == requested,
              r["controllerSession"] as? String == session, r["controlId"] as? String == id,
              r["decisionId"] as? String == decision, output == requested,
              mode == "on" || !output else { return nil }
        if let latest=control["id"] as? String, !latest.isEmpty, latest != id { return nil }
        return output
    }

}

enum WidgetSnapshotStore {
    static let appGroupID = "group.com.example.termostatApp"
    static let widgetKind = "ThermostatWidget"
    static let snapshotKey = "widget.snapshot.v1"
    static let sessionKey = "widget.session.active.v1"
    private static let lock = NSLock()

    static func read() -> WidgetSnapshot? {
        guard let string = UserDefaults(suiteName: appGroupID)?.string(forKey: snapshotKey),
              let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
    static func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot),
              let string = String(data: data, encoding: .utf8) else { return }
        UserDefaults(suiteName: appGroupID)?.set(string, forKey: snapshotKey)
    }
    static func clear(reloadTimeline: Bool = true) {
        UserDefaults(suiteName: appGroupID)?.removeObject(forKey: snapshotKey)
        if reloadTimeline { reload() }
    }
    static var explicitlySignedOut: Bool {
        (UserDefaults(suiteName: appGroupID)?.object(forKey: sessionKey) as? Bool) == false
    }
    static func recordAccepted(_ command: ThermostatHeatingCommand) {
        lock.lock()
        var snapshot = read() ?? WidgetSnapshot()
        switch command {
        case .turnOn:
            snapshot.mode = "on"
            snapshot.isHeating = nil // No claim that the physical relay already changed.
        case .turnOff:
            snapshot.mode = "off"
            snapshot.isHeating = nil
        case .setTemperature(let temperature):
            snapshot.mode = "on"
            snapshot.targetTemperature = temperature
            snapshot.isHeating = nil
        }
        // Do not refresh the sensor timestamp when only a command is acknowledged.
        snapshot.commandAtMilliseconds = Date().timeIntervalSince1970 * 1000
        write(snapshot)
        lock.unlock()
        reload()
    }
    static func reload() {
        #if canImport(WidgetKit)
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        }
        #endif
    }
}

/// Reads real Firebase values; a network failure never creates invented readings.
enum WidgetDataLoader {
    static func refresh() async throws -> WidgetSnapshot {
        try Task.checkCancellation()
        if WidgetSnapshotStore.explicitlySignedOut {
            throw ThermostatCommandError.signInRequired
        }
        #if canImport(FirebaseCore) && canImport(FirebaseAuth)
        let databaseURL = try ThermostatFirebaseConfig.databaseURL()
        let auth = FirebaseAuthSessionProvider()
        try await auth.ensureUserAuthenticated(timeout: 5)
        var token = try await auth.getValidIDToken(forcingRefresh: false)
        for attempt in 0..<2 {
            try Task.checkCancellation()
            var request = try ThermostatCommandService.buildRequest(
                databaseURL: databaseURL,
                deviceID: ThermostatCommandService.defaultDeviceID,
                token: token,
                command: .turnOn
            )
            request.httpMethod = "GET"
            request.httpBody = nil
            request.timeoutInterval = 12
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.performData(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw ThermostatCommandError.invalidResponse
            }
            if response.statusCode == 401 && attempt == 0 {
                token = try await auth.getValidIDToken(forcingRefresh: true)
                continue
            }
            guard (200..<300).contains(response.statusCode) else {
                if [401, 403].contains(response.statusCode) {
                    throw ThermostatCommandError.authorizationDenied
                }
                throw ThermostatCommandError.requestFailed(response.statusCode)
            }
            let snapshot = try WidgetSnapshot.fromDeviceJSON(data)
            try Task.checkCancellation()
            if WidgetSnapshotStore.explicitlySignedOut {
                throw ThermostatCommandError.signInRequired
            }
            WidgetSnapshotStore.write(snapshot)
            return snapshot
        }
        throw ThermostatCommandError.authorizationDenied
        #else
        throw ThermostatCommandError.missingConfiguration
        #endif
    }
}
