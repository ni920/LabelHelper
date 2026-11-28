import SwiftUI

struct RecipientEditorView: View {
    @ObservedObject var appStore: AppStore

    var body: some View {
        Form {
            TextField("Name", text: $appStore.recipientName, prompt: Text("Vor- und Nachname oder Firma"))
            TextField("Straße", text: $appStore.recipientStreet1, prompt: Text("Straße und Hausnummer"))
            TextField("Zusatz", text: $appStore.recipientStreet2, prompt: Text("Optional"))
            TextField("PLZ", text: $appStore.recipientPostalCode)
            TextField("Ort", text: $appStore.recipientCity)
            TextField("Land", text: $appStore.recipientCountry)
        }
        .textFieldStyle(.roundedBorder)
    }
}

struct PrinterConnectionView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject var bluetooth: BluetoothPrinterService
    var showsDiagnosticsLink = true
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            Label(bluetooth.connectionState.isReady ? "Drucker verbunden" : "Drucker verbinden …", systemImage: bluetooth.connectionState.isReady ? "printer.fill" : "printer")
        }
        .help("Drucker auswählen und Verbindungsstatus prüfen")
        .popover(isPresented: $isPresented) {
            PrinterConnectionControls(appStore: appStore, bluetooth: bluetooth, showsDiagnosticsLink: showsDiagnosticsLink)
        }
    }
}

struct PrinterConnectionControls: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject var bluetooth: BluetoothPrinterService
    var showsDiagnosticsLink = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(bluetooth.connectionState.title).font(.headline)
            if let firmware = bluetooth.firmwareVersion { Text("Firmware \(firmware)").font(.callout) }
            if let detail = bluetooth.connectionState.detail { Text(detail).fixedSize(horizontal: false, vertical: true) }
            if bluetooth.connectionState.isReady {
                Button("Testetikett drucken", action: appStore.printTestLabel).disabled(appStore.shippingBusy)
                Button("Verbindung trennen", action: bluetooth.disconnect).disabled(appStore.shippingBusy)
            } else {
                Button("Drucker suchen", action: bluetooth.startScanning)
                if bluetooth.connectionState == .scanning { ProgressView().controlSize(.small) }
                ForEach(bluetooth.discoveredDevices.prefix(8)) { device in
                    HStack {
                        Label(device.name, systemImage: "printer")
                        Spacer()
                        Button("Verbinden") { bluetooth.connect(to: device.id) }
                    }
                }
            }
            if showsDiagnosticsLink {
                SettingsLink { Text("Druckereinstellungen …") }
            }
        }
        .padding(20).frame(width: 340)
    }
}
