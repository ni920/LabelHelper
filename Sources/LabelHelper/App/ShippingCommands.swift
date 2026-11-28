import SwiftUI

struct ShippingCommands: Commands {
    @ObservedObject var appStore: AppStore

    var body: some Commands {
        CommandMenu("Versand") {
            Button("Versandübersicht", action: appStore.showShippingHome)
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(appStore.shippingBusy)
            Button("DHL-Paketlabel öffnen …", action: appStore.chooseDHLLabelImport)
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Label-Verlauf exportieren …", action: appStore.exportHistory)
                .disabled(appStore.shippingBusy)
        }
    }
}
