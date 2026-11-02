import Foundation

/// Progress records the user's confirmations, never a detected installation.
public struct BrowserExtensionSetupJourney: Equatable {
    public enum Browser: String, CaseIterable, Identifiable {
        case chrome = "Chrome", safari = "Safari"
        public var id: Self { self }
        public var bundleIdentifier: String {
            switch self { case .chrome: "com.google.Chrome"; case .safari: "com.apple.Safari" }
        }
    }
    public enum Step: Int, CaseIterable {
        case files, browser, installation, access, transfer
        public var title: String {
            switch self {
            case .files: "Dateien vorbereiten"
            case .browser: "Browser vorbereiten"
            case .installation: "Erweiterung hinzufügen"
            case .access: "Etsy-Zugriff erlauben"
            case .transfer: "Bestellung übernehmen"
            }
        }
    }
    public private(set) var browser: Browser = .chrome
    public private(set) var step: Step = .files
    public private(set) var filesPrepared = false
    public var browserConfigured = false
    public var installationConfirmed = false
    public var accessConfirmed = false
    public var transferConfirmed = false
    public init() {}
    public var canAdvance: Bool {
        switch step {
        case .files: filesPrepared
        case .browser: browserConfigured
        case .installation: installationConfirmed
        case .access: accessConfirmed
        case .transfer: transferConfirmed
        }
    }
    public mutating func didPrepareFiles() { filesPrepared = true }
    public mutating func select(_ browser: Browser) {
        guard self.browser != browser else { return }
        self.browser = browser
        restart()
    }
    public mutating func restart() {
        step = .files
        browserConfigured = false; installationConfirmed = false
        accessConfirmed = false; transferConfirmed = false
    }
    public mutating func advance() {
        guard canAdvance, let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }
    public mutating func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }
}
