import AppKit
import SwiftUI

struct ShipmentCompletionView: View {
    @ObservedObject var appStore: AppStore
    let status: String
    var trackingNumbers: [String] = []
    var symbol = "checkmark.circle.fill"
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(status, systemImage: symbol)
                .font(.headline)
            if !trackingNumbers.isEmpty {
                Text(trackingNumbers.joined(separator: "\n")).font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Button(copied ? "Kopiert" : trackingNumbers.count == 1 ? "Sendungsnummer kopieren" : "Sendungsnummern kopieren") {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(trackingNumbers.joined(separator: "\n"), forType: .string)
                }
            }
            Button("Neuer Versand", action: appStore.returnToStart).buttonStyle(.borderedProminent)
            Button("Im Label-Verlauf anzeigen", action: appStore.showCompletedShipmentInHistory)
        }
    }
}
