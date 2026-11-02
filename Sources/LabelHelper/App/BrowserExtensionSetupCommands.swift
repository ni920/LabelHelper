import SwiftUI

struct BrowserExtensionSetupCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Browser-Erweiterung einrichten …") { openWindow(id: "browser-extension-setup") }
        }
    }
}
