import LabelCore
import SwiftUI

struct PrinterSettingsView: View {
    @ObservedObject var appStore: AppStore
    @AppStorage("postageLabelFormatID") private var postageFormatID = LabelFormat.shipping100x150.id
    @AppStorage("postageCutGuides") private var postageCutGuides = true
    @AppStorage("letterFlowAutoCopyTracking") private var autoCopyTracking = false

    var body: some View {
        Form {
            Section("Etikettenmaterial") {
                LabelFormatControls(appStore: appStore, showHeading: false)
                Text("Paketlabel verwenden 100 × 150 mm.").font(.callout)
                if appStore.labelStockMode == .continuous100 {
                    Stepper("Papierzugabe nach der Schnittlinie: \(Int(appStore.continuousExtraFeedMM)) mm",
                            value: $appStore.continuousExtraFeedMM,
                            in: ContinuousLabelCutGuide.additionalFeedRangeMM, step: 2)
                    Text("Verlängert den Rand bei zu starkem Einzug der Endlosrolle.").font(.callout)
                }
            }
            Section("Briefmarken") {
                Toggle("Sendungsnummer nach dem Briefdruck kopieren", isOn: $autoCopyTracking)
                DisclosureGroup("Layout für Briefmarken-Bündel") {
                    PostageFormatControls(appStore: appStore, formatID: $postageFormatID)
                    Toggle("Schnittlinien drucken", isOn: $postageCutGuides)
                }
            }
            Section {
                DisclosureGroup("Erweiterte Druckeinstellungen") {
                    Stepper("Geschwindigkeit: \(appStore.speed)", value: $appStore.speed, in: 1...8)
                    Stepper("Druckdichte: \(appStore.density)", value: $appStore.density, in: 1...15)
                }
            }

            Section("Verbindung") {
                PrinterConnectionView(appStore: appStore, bluetooth: appStore.bluetooth, showsDiagnosticsLink: false)
                DisclosureGroup("Bluetooth-Diagnose") {
                    BluetoothDiagnosticsView(bluetooth: appStore.bluetooth)
                        .frame(minHeight: 365)
                }
            }
        }
        .formStyle(.grouped)
    }
}
