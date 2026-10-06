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
        let rawMode = json["mode"] as? String
        let mode = ["on", "off"].contains(rawMode ?? "") ? rawMode : nil
        var heating: Bool?
        if let value = json["isHeating"] as? NSNumber,
           CFGetTypeID(value) == CFBooleanGetTypeID() {
            heating = value.boolValue
        }
        return WidgetSnapshot(
            temperature: number("currentTemperature", range: -40...85),
            humidity: number("currentHumidity", range: 0...100) ?? number("humidity", range: 0...100),
            targetTemperature: number("targetTemperature", range: 10...30),
            mode: mode,
            isHeating: heating,
            observedAtMilliseconds: now.timeIntervalSince1970 * 1000,
            commandAtMilliseconds: nil
        )
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
