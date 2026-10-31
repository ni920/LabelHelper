import AppKit
import LabelCore
import SwiftUI

struct BrowserExtensionSetupView: View {
    private enum Browser: String, CaseIterable, Identifiable {
        case chrome = "Chrome"
        case safari = "Safari"

        var id: Self { self }
        var bundleIdentifier: String {
            switch self {
            case .chrome: "com.google.Chrome"
            case .safari: "com.apple.Safari"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var browser: Browser = .chrome
    @State private var preparedDirectory: URL?
    @State private var isPreparing = false
    @State private var errorMessage: String?
    @State private var copiedPath = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Browser-Erweiterung einrichten").font(.title2.weight(.semibold))
            Text("Label Helper bereitet die Dateien vor, kopiert den Ordnerpfad und öffnet den Browser. Das Hinzufügen und den Etsy-Zugriff bestätigst du dort selbst.")
                .font(.callout)

            Picker("Browser", selection: $browser) {
                ForEach(Browser.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(isPreparing)

            ScrollView {
                setupDetails
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Schließen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isPreparing)
                Link("Ausführliche Anleitung",
                     destination: URL(string: "https://github.com/ni920/LabelHelper/blob/main/BrowserExtension/README.md")!)
                Spacer()
                Button(preparedDirectory == nil ? "Einrichtung starten" : "\(browser.rawValue) öffnen") {
                    Task { await prepareAndOpenBrowser() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isPreparing)
            }
        }
        .padding(24)
        .frame(width: 560, height: 600)
        .interactiveDismissDisabled(isPreparing)
        .onChange(of: browser) { _, _ in errorMessage = nil }
    }

    private var setupDetails: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                if browser == .chrome {
                    instruction(1, "In Chrome chrome://extensions öffnen und den Entwicklermodus einschalten.")
                    instruction(2, "„Entpackte Erweiterung laden“ wählen. Im Dateidialog mit ⇧⌘G den vorbereiteten Ordnerpfad einfügen.")
                    instruction(3, "Die Erweiterung aktivieren und die Etsy-Bestellseite neu laden.")
                } else {
                    instruction(1, "Safari → Einstellungen → Erweitert: „Funktionen für Webentwickler anzeigen“ einschalten.")
                    instruction(2, "Unter „Entwickler“ die temporäre Erweiterung hinzufügen. Im Dateidialog mit ⇧⌘G den vorbereiteten Ordnerpfad einfügen.")
                    instruction(3, "Unter „Erweiterungen“ aktivieren, Etsy-Zugriff erlauben und die Bestellseite neu laden.")
                }
            }
            if browser == .safari {
                Label("Safari entfernt temporäre Erweiterungen beim Beenden oder nach 24 Stunden. Eine dauerhafte Installation benötigt eine Safari-Container-App.",
                      systemImage: "info.circle")
                    .font(.callout)
            }
            if let preparedDirectory {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Dateien vorbereitet – noch im Browser hinzufügen", systemImage: "folder.badge.gearshape")
                        .font(.headline)
                    Text(preparedDirectory.path).font(.callout).textSelection(.enabled)
                    HStack {
                        Button("Ordner anzeigen") {
                            NSWorkspace.shared.activateFileViewerSelecting([preparedDirectory])
                        }
                        Button(copiedPath ? "Pfad kopiert" : "Pfad kopieren") {
                            copyPath(preparedDirectory)
                        }
                    }
                    Text("Den Ordner nicht löschen oder verschieben. Bereits hinzugefügt? Nach einem App-Update die Einrichtung erneut starten und die Erweiterung im Browser neu laden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if isPreparing {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Einrichtung wird vorbereitet …")
                }
            }
        }
    }

    @discardableResult
    private func copyPath(_ directory: URL) -> Bool {
        NSPasteboard.general.clearContents()
        copiedPath = NSPasteboard.general.setString(directory.path, forType: .string)
        if !copiedPath { errorMessage = "Der Ordnerpfad konnte nicht kopiert werden. Bitte den Pfad oben manuell kopieren." }
        return copiedPath
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private func prepareAndOpenBrowser() async {
        guard !isPreparing else { return }
        isPreparing = true
        errorMessage = nil
        defer { isPreparing = false }
        do {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) else {
                errorMessage = "\(browser.rawValue) wurde nicht gefunden. Bitte den Browser zuerst installieren oder den anderen Browser wählen."
                return
            }
            if preparedDirectory == nil {
                guard let source = Bundle.main.url(forResource: "BrowserExtension", withExtension: nil) else {
                    throw BrowserExtensionSetupError.missingBundle
                }
                let destination = try BrowserExtensionFiles.defaultDirectory()
                let prepared = try BrowserExtensionFiles.prepare(from: source, at: destination)
                preparedDirectory = prepared
                guard copyPath(prepared) else { return }
            }
            let configuration = NSWorkspace.OpenConfiguration()
            if browser == .chrome {
                _ = try await NSWorkspace.shared.open(
                    [URL(string: "chrome://extensions")!], withApplicationAt: appURL, configuration: configuration)
            } else {
                _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            }
        } catch {
            errorMessage = "Einrichtung nicht abgeschlossen: \(error.localizedDescription)"
        }
    }
}
