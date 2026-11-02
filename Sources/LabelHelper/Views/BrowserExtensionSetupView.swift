import AppKit
import LabelCore
import SwiftUI

struct BrowserExtensionSetupView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var journey = BrowserExtensionSetupJourney()
    @State private var preparedDirectory: URL?
    @State private var isPreparing = false
    @State private var errorMessage: String?
    @State private var copyStatus: String?
    // A narrow dependency for isolated UI verification; normal setup uses the data folder.
    var preparationDirectory: URL? = nil

    private var browser: BrowserExtensionSetupJourney.Browser { journey.browser }
    private var isSafari: Bool { browser == .safari }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Etsy mit Label Helper verbinden").font(.title2.weight(.semibold))
            Picker("Browser", selection: Binding(get: { browser }, set: {
                journey.select($0); errorMessage = nil; copyStatus = nil
            })) {
                ForEach(BrowserExtensionSetupJourney.Browser.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).disabled(isPreparing)
            HStack {
                Text("Schritt \(journey.step.rawValue + 1) von 5").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text(isSafari ? "Temporäre Safari-Erweiterung" : "Chrome-Erweiterung").font(.callout)
            }
            ProgressView(value: Double(journey.step.rawValue + 1), total: 5)
                .accessibilityLabel("Einrichtungsfortschritt")
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(journey.step.title).font(.title3.weight(.semibold))
                    instructions
                    if let copyStatus { Label(copyStatus, systemImage: "doc.on.clipboard").font(.callout) }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red).font(.callout).textSelection(.enabled)
                    }
                    if isPreparing { ProgressView("Dateien werden vorbereitet …").controlSize(.small) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if journey.step != .files && !journey.canAdvance {
                Text("Erledigt? Setze das Häkchen, dann kannst du weitergehen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("Schließen", role: .cancel) { close() }.keyboardShortcut(.cancelAction)
                Link("Anleitung", destination: URL(string: "https://github.com/ni920/LabelHelper/blob/main/BrowserExtension/README.md")!)
                Spacer()
                if journey.step != .files { Button("Zurück") { journey.back(); copyStatus = nil; errorMessage = nil } }
                Button(primaryTitle, action: next)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(isPreparing || (journey.step != .files && !journey.canAdvance))
            }.disabled(isPreparing)
        }
        .padding(24)
        .frame(minWidth: 600, idealWidth: 640, maxWidth: 760, minHeight: 620, idealHeight: 650)
        .onAppear { journey.restart() }
    }

    @ViewBuilder private var instructions: some View {
        switch journey.step {
        case .files:
            Text("Die Erweiterung ist bereits in Label Helper enthalten. Du brauchst kein zusätzliches ZIP und kein Terminal.")
            if isSafari {
                Label("Safari entfernt diese Installation beim Beenden oder nach 24 Stunden. Eine dauerhaft verteilbare Safari-Erweiterung benötigt eine signierte Container-App; diese ist in diesem Download nicht enthalten.", systemImage: "info.circle")
                    .font(.callout)
            } else {
                Text("Chrome lädt die Erweiterung aus einem festen Ordner. Label Helper legt ihn für dich an.")
            }
            if preparedDirectory != nil { folderActions }
            Text("Mit „\(primaryTitle)“ werden nur die lokalen Erweiterungsdateien vorbereitet. Im Browser bestätigst du die Installation selbst.")
                .font(.callout).foregroundStyle(.secondary)
        case .browser:
            if isSafari {
                instruction(1, "Safari öffnen und mit ⌘, die Einstellungen aufrufen.")
                instruction(2, "„Erweitert“ auswählen und „Funktionen für Webentwickler anzeigen“ einschalten.")
                Text("Danach erscheint der Reiter „Entwickler“. Ältere Safari-Versionen haben den nächsten Menüpunkt möglicherweise nicht; siehe Anleitung für den Xcode-Weg.").font(.callout)
                Button("Safari öffnen") { Task { await openBrowser() } }
            } else {
                instruction(1, "Die Erweiterungsseite in Chrome öffnen.")
                instruction(2, "Oben rechts „Entwicklermodus“ einschalten.")
                HStack {
                    Button("Chrome-Erweiterungen öffnen") { Task { await openBrowser() } }
                    Button("Browseradresse kopieren") { copy("chrome://extensions/", message: "Browseradresse kopiert. In die Chrome-Adressleiste einfügen und Return drücken.") }
                }
                Text("Falls Chrome die Seite nicht direkt öffnet: chrome://extensions/ in die Adressleiste einfügen und Return drücken.")
                    .font(.callout).textSelection(.enabled)
            }
            Toggle(isSafari ? "Funktionen für Webentwickler sind eingeschaltet" : "Entwicklermodus ist eingeschaltet", isOn: $journey.browserConfigured)
        case .installation:
            instruction(1, isSafari ? "Safari → Einstellungen → Entwickler öffnen und „Temporäre Erweiterung hinzufügen …“ wählen." : "In Chrome „Entpackte Erweiterung laden“ anklicken.")
            instruction(2, "Im Dateidialog ⇧⌘G drücken, den Ordnerpfad einfügen und Return drücken. Danach „Auswählen“ bestätigen.")
            folderActions
            Text("Wähle den Ordner BrowserExtension mit der Datei manifest.json – nicht die Datei selbst, nicht „icons“ und kein ZIP.").font(.callout)
            if isSafari {
                Text("Safari kann eine Bestätigung für unsignierte Erweiterungen verlangen. Fehlt „Temporäre Erweiterung hinzufügen“, nutze den Xcode-Weg in der Anleitung oder Chrome.").font(.callout)
            }
            Toggle("„Label Helper für Etsy“ erscheint in den Erweiterungen", isOn: $journey.installationConfirmed)
        case .access:
            instruction(1, isSafari ? "Safari → Einstellungen → Erweiterungen öffnen und „Label Helper für Etsy“ einschalten." : "Bei chrome://extensions/ prüfen, dass „Label Helper für Etsy“ eingeschaltet ist. „Details“ öffnen.")
            instruction(2, isSafari ? "Den Website-Zugriff für etsy.com erlauben. Bei Safari-Profilen auch das verwendete Profil prüfen." : "Unter „Websitezugriff“ den Zugriff auf etsy.com für die unterstützten Bestellseiten erlauben.")
            Text("Die Erweiterung braucht Zugriff auf die Etsy-Bestellseite, damit der Senden-Button und die Adressübernahme funktionieren.").font(.callout)
            Toggle("Erweiterung ist aktiviert und Etsy-Zugriff ist erlaubt", isOn: $journey.accessConfirmed)
        case .transfer:
            Button("Etsy-Bestellungen öffnen") { Task { await openBrowser(url: URL(string: "https://www.etsy.com/your/orders/sold")) } }
            instruction(1, "Den Etsy-Tab neu laden (⌘R) und die Details einer einzelnen Bestellung öffnen. Die vollständige Adresse unter „Versand an“ muss sichtbar sein.")
            instruction(2, "Unten rechts auf der Etsy-Seite „An Label Helper senden“ anklicken und das Öffnen der App bestätigen.")
            instruction(3, "In Label Helper Brief oder Paket wählen und die übernommene Adresse kontrollieren. Zum Einrichten musst du nichts drucken.")
            Toggle("Die richtige Empfängeradresse ist in Label Helper angekommen", isOn: $journey.transferConfirmed)
            DisclosureGroup("Es klappt noch nicht?") {
                Text("Kein Button: Etsy neu laden, Erweiterung, Website-Zugriff und Browser-Profil prüfen.\nAdresse fehlt: Einzelne Bestellung mit vollständiger Versandadresse öffnen.\nApp öffnet nicht: Label Helper einmal aus Programme öffnen und den App-Link im Browser bestätigen.\nSafari nach Neustart leer: Temporäre Erweiterung erneut hinzufügen.")
                    .font(.callout).padding(.top, 8).fixedSize(horizontal: false, vertical: true)
            }
            Text("Die Häkchen sind deine Bestätigung. Label Helper liest dafür keine Browserprofile aus.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var folderActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let preparedDirectory {
                Text(preparedDirectory.path).font(.callout).textSelection(.enabled)
                HStack {
                    Button("Ordnerpfad kopieren") { copy(preparedDirectory.path, message: "Ordnerpfad kopiert. Im Browser-Dateidialog ⇧⌘G drücken und einfügen.") }
                    Button("Ordner anzeigen") { NSWorkspace.shared.activateFileViewerSelecting([preparedDirectory]) }
                }
                Text("Diesen Ordner behalten. Der Browser verwendet ihn weiterhin.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var primaryTitle: String {
        if journey.step == .files { return preparedDirectory == nil ? "Dateien vorbereiten" : "Dateien aktualisieren" }
        return journey.step == .transfer ? "Fertig" : "Weiter"
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine)
    }

    private func close() { dismissWindow(id: "browser-extension-setup") }
    private func next() {
        errorMessage = nil; copyStatus = nil
        if journey.step == .files { Task { await prepareFiles() } }
        else if journey.step == .transfer { if journey.canAdvance { close() } }
        else { journey.advance() }
    }

    @MainActor private func prepareFiles() async {
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            guard let source = Bundle.main.url(forResource: "BrowserExtension", withExtension: nil) else {
                throw BrowserExtensionSetupError.missingBundle
            }
            let destination = try preparationDirectory ?? BrowserExtensionFiles.defaultDirectory()
            preparedDirectory = try BrowserExtensionFiles.prepare(from: source, at: destination)
            journey.didPrepareFiles()
            journey.advance()
        } catch { errorMessage = "Dateien nicht vorbereitet: \(error.localizedDescription)" }
    }

    @MainActor private func copy(_ value: String, message: String) {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(value, forType: .string) { copyStatus = message }
        else { errorMessage = "Kopieren nicht möglich. Bitte den angezeigten Text manuell kopieren." }
    }

    @MainActor private func openBrowser(url: URL? = nil) async {
        errorMessage = nil
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) else {
            errorMessage = "\(browser.rawValue) wurde nicht gefunden. Bitte zuerst installieren oder den anderen Browser wählen."
            return
        }
        do {
            let destination = url ?? (isSafari ? nil : URL(string: "chrome://extensions/"))
            if let destination {
                _ = try await NSWorkspace.shared.open([destination], withApplicationAt: appURL, configuration: .init())
            } else {
                _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
            }
        } catch { errorMessage = "Browser konnte nicht geöffnet werden: \(error.localizedDescription)" }
    }
}
