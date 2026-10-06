import Foundation
import AppIntents

@available(iOS 16.0, *)
struct HeatingOnIntent: AppIntent {
    static var title: LocalizedStringResource = "Isıtmayı aç"
    static var description = IntentDescription(
        "Mevcut hedef sıcaklığı değiştirmeden termostatın ısıtma modunu açar."
    )
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try await ThermostatCommandService.send(.turnOn)
            return .result(
                dialog: "Isıtmayı açma komutu gönderildi."
            )
        } catch let error as LocalizedError {
            throw error
        } catch {
            throw ThermostatCommandError.internalError(error.localizedDescription)
        }
    }
}

@available(iOS 16.0, *)
struct HeatingOffIntent: AppIntent {
    static var title: LocalizedStringResource = "Isıtmayı kapat"
    static var description = IntentDescription(
        "Termostatın ısıtma modunu kapatır."
    )
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try await ThermostatCommandService.send(.turnOff)
            return .result(
                dialog: "Isıtmayı kapatma komutu gönderildi."
            )
        } catch let error as LocalizedError {
            throw error
        } catch {
            throw ThermostatCommandError.internalError(error.localizedDescription)
        }
    }
}


@available(iOS 16.0, *)
struct SetTemperatureIntent: AppIntent {
    static var title: LocalizedStringResource = "Sıcaklığı ayarla"
    static var description = IntentDescription(
        "Hedef sıcaklığı 10–30°C arasında ayarlar ve ısıtma modunu açar."
    )
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Sıcaklık", requestValueDialog: "Kaç dereceye ayarlayayım?")
    var temperature: Double

    init() {}
    init(temperature: Double) { self.temperature = temperature }

    static var parameterSummary: some ParameterSummary {
        Summary("Sıcaklığı \(\.$temperature) dereceye ayarla")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await ThermostatCommandService.send(.setTemperature(temperature))
        let value = temperature.formatted(
            .number.locale(Locale(identifier: "tr_TR"))
                .precision(.fractionLength(0...2))
        )
        return .result(dialog: "Sıcaklığı \(value) dereceye ayarlama komutu gönderildi.")
    }
}
