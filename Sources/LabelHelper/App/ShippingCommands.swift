import SwiftUI

struct ShippingNavigationActions {
    var back: () -> Void
    var advance: () -> Void
    var canGoBack: Bool
    var canAdvance: Bool
}

private struct ShippingNavigationKey: FocusedValueKey {
    typealias Value = ShippingNavigationActions
}
extension FocusedValues {
    var shippingNavigation: ShippingNavigationActions? {
        get { self[ShippingNavigationKey.self] }
        set { self[ShippingNavigationKey.self] = newValue }
    }
}

struct ShippingCommands: Commands {
    @ObservedObject var appStore: AppStore
    @FocusedValue(\.shippingNavigation) private var navigation

    var body: some Commands {
        CommandMenu("Versand") {
            Toggle("Geführter Modus", isOn: $appStore.guidedMode)
            Button("Aufgabe auswählen") {
                appStore.showShippingHome()
            }.keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Button("Zurück") { navigation?.back() }
                .disabled(navigation?.canGoBack != true)
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("Weiter") { navigation?.advance() }
                .disabled(navigation?.canAdvance != true)
                .keyboardShortcut(.return, modifiers: .command)
        }
    }
}
