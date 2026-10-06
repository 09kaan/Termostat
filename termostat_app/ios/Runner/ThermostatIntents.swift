import Foundation
import AppIntents

@available(iOS 16.0, *)
struct HeatingOnIntent: AppIntent {
    static var title: LocalizedStringResource = "Isıtmayı aç"
    static var description = IntentDescription(
        "Termostatın ısıtma modunu açar ve hedef sıcaklığı 25°C yapar."
    )
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            try await ThermostatCommandService.send(.turnOn)
            return .result(
                dialog: "Isıtmayı 25 dereceye ayarlama komutu gönderildi."
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
