import AppKit
import LabelCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appStore: AppStore

    var body: some View {
        TabView {
            GeneralSettingsView(appStore: appStore)
                .tabItem {
                    Label("Allgemein", systemImage: "slider.horizontal.3")
                }

            LabelDesignerView(appStore: appStore)
                .tabItem {
                    Label("Etikett", systemImage: "rectangle.and.pencil.and.ellipsis")
                }

            QueueView(appStore: appStore, jobStore: appStore.jobs)
                .tabItem {
                    Label("Druckaufträge", systemImage: "list.bullet.rectangle")
                }

            BluetoothDiagnosticsView(bluetooth: appStore.bluetooth)
                .tabItem {
                    Label("Bluetooth", systemImage: "wave.3.right.circle")
                }
        }
        .frame(width: 620, height: 600)
        .scenePadding()
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var appStore: AppStore
    @Environment(\.openWindow) private var openWindow
    @State private var restoreURL: URL?
    @State private var dataStatus: String?
    @State private var dataError: String?

    var body: some View {
        Form {
            Section("Bedienung") {
                Toggle("Geführten Modus verwenden", isOn: $appStore.guidedMode)
                Text("Der geführte Modus zeigt die Vorbereitung Schritt für Schritt. Im Direktmodus stehen alle Versandfelder zusammen.")
                    .font(.callout)
            }

            Section("Etsy-Browser-Erweiterung") {
                Text("Eine geöffnete Etsy-Bestellung aus Chrome oder Safari übernehmen.")
                    .font(.callout)
                Button("Browser-Erweiterung einrichten …") { openWindow(id: "browser-extension-setup") }
            }

            Section("Absender für Briefetiketten") {
                TextField("Name oder Firma", text: $appStore.senderName)
                TextField("Straße und Hausnummer", text: $appStore.senderStreet)
                HStack {
                    TextField("PLZ", text: $appStore.senderPostalCode)
                        .frame(width: 90)
                    TextField("Ort", text: $appStore.senderCity)
                }
                TextField("Land", text: $appStore.senderCountry)
            }
            Section("Etikettenmaterial") {
                LabelFormatControls(appStore: appStore, showHeading: false)
                Text("Paketlabel verwenden 100 × 150 mm.").font(.callout)
                if appStore.labelStockMode == .continuous100 {
                    Stepper("Papierzugabe nach der Schnittlinie: \(Int(appStore.continuousExtraFeedMM)) mm",
                            value: $appStore.continuousExtraFeedMM,
                            in: ContinuousLabelCutGuide.additionalFeedRangeMM, step: 2)
                    Text("Falls der Drucker das Papier beim Start zu weit einzieht: Mit 8 bis 12 mm bleibt die Schnittkante weiter vorn. Das kostet pro Etikett entsprechend mehr Papier.")
                        .font(.callout)
                }
            }
            Section {
                DisclosureGroup("Erweiterte Druckeinstellungen") {
                    Stepper("Geschwindigkeit: \(appStore.speed)", value: $appStore.speed, in: 1...8)
                    Stepper("Druckdichte: \(appStore.density)", value: $appStore.density, in: 1...15)
                }
            }

            Section("Daten") {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Speicherort")
                        .font(.headline)
                    Text(appStore.applicationDataLocation.rootURL.path)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Datenordner anzeigen", action: revealDataDirectory)
                        Button("Datensicherung erstellen …", action: createBackup)
                    }
                    Button("Datensicherung wiederherstellen …", action: chooseBackupToRestore)
                }
                .disabled(!appStore.canManageApplicationData)
                Text("Die Sicherung enthält Druckaufträge, Adressetiketten, Briefmarkenbestand, Label-Verlauf und die vorbereitete Browser-Erweiterung.")
                    .font(.callout)
                if !appStore.canManageApplicationData {
                    Label("Datensicherungen sind während eines Druckablaufs gesperrt.", systemImage: "printer")
                        .font(.callout)
                }
                if let dataStatus {
                    Label(dataStatus, systemImage: "checkmark.circle")
                        .font(.callout)
                        .textSelection(.enabled)
                }
                if let dataError {
                    Label(dataError, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Datensicherung wiederherstellen?", isPresented: Binding(
            get: { restoreURL != nil },
            set: { if !$0 { restoreURL = nil } }
        )) {
            Button("Abbrechen", role: .cancel) { restoreURL = nil }
            Button("Wiederherstellen und beenden", role: .destructive) {
                guard let url = restoreURL else { return }
                restoreURL = nil
                restoreBackup(from: url)
            }
        } message: {
            Text("Der aktuelle Datenstand wird vorher automatisch gesichert. Danach beendet sich Label Helper, damit beim nächsten Start ausschließlich die wiederhergestellten Daten geladen werden.")
        }
    }

    private func revealDataDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([appStore.applicationDataLocation.rootURL])
    }

    private func createBackup() {
        guard appStore.canManageApplicationData, let destination = chooseDirectory(
            title: "Speicherort für die Datensicherung wählen",
            prompt: "Hier sichern"
        ) else { return }
        dataStatus = nil
        dataError = nil
        let scoped = destination.startAccessingSecurityScopedResource()
        defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
        do {
            let backup = try ApplicationDataManager.createBackup(
                of: appStore.applicationDataLocation.rootURL,
                in: destination
            )
            dataStatus = "Datensicherung erstellt: \(backup.path)"
            NSWorkspace.shared.activateFileViewerSelecting([backup])
        } catch {
            dataError = error.localizedDescription
        }
    }

    private func chooseBackupToRestore() {
        guard appStore.canManageApplicationData else { return }
        restoreURL = chooseDirectory(
            title: "Label-Helper-Datensicherung auswählen",
            prompt: "Auswählen"
        )
    }

    private func restoreBackup(from backup: URL) {
        dataStatus = nil
        dataError = nil
        let scoped = backup.startAccessingSecurityScopedResource()
        defer { if scoped { backup.stopAccessingSecurityScopedResource() } }
        do {
            _ = try ApplicationDataManager.restoreBackup(
                from: backup,
                to: appStore.applicationDataLocation.rootURL
            )
            NSApp.terminate(nil)
        } catch {
            dataError = error.localizedDescription
        }
    }

    private func chooseDirectory(title: String, prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
