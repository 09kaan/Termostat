import Foundation
import AppIntents

@available(iOS 16.0, *)
struct ThermostatShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: HeatingOnIntent(),
            phrases: [
                "\(.applicationName) ile ısıtmayı aç"
            ],
            shortTitle: "Isıtmayı aç",
            systemImageName: "flame"
        )
        AppShortcut(
            intent: HeatingOffIntent(),
            phrases: [
                "\(.applicationName) ile ısıtmayı kapat"
            ],
            shortTitle: "Isıtmayı kapat",
            systemImageName: "power"
        )
    }
}
