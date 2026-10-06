import AppIntents

@available(iOS 17.0, *)
struct AdjustWidgetTemperatureIntent: AppIntent {
    static var title: LocalizedStringResource = "Widget sıcaklığını değiştir"
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var isDiscoverable: Bool = false

    @Parameter(title: "Değişim") var delta: Double

    init() {}
    init(delta: Double) { self.delta = delta }

    func perform() async throws -> some IntentResult {
        guard delta == -0.5 || delta == 0.5 else {
            throw ThermostatCommandError.invalidTemperature
        }
        // Read the current server target instead of relying on a stale widget value.
        let snapshot = try await WidgetDataLoader.refresh()
        guard let current = snapshot.targetTemperature else {
            throw ThermostatCommandError.invalidResponse
        }
        let target = min(30, max(10, current + delta))
        try await ThermostatCommandService.send(.setTemperature(target))
        return .result()
    }
}
