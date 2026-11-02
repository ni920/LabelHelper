import AppKit
import Sparkle
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        updaterController.updater.checkForUpdatesInBackground()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first(where: { $0.identifier?.rawValue == "main" })?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}

@main
struct LabelHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appStore = AppStore()

    var body: some Scene {
        Window("Label Helper", id: "main") {
            ContentView()
                .environmentObject(appStore)
                .frame(minWidth: 920, minHeight: 620)
                .onOpenURL { url in
                    appStore.handleIncomingURL(url)
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first(where: { $0.identifier?.rawValue == "main" })?.makeKeyAndOrderFront(nil)
                }
        }
        .defaultSize(width: 1_080, height: 720)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen …") {
                    appDelegate.updaterController.checkForUpdates(nil)
                }
                .disabled(!appDelegate.updaterController.updater.canCheckForUpdates)
            }

            BrowserExtensionSetupCommands()
            ShippingCommands(appStore: appStore)
            CommandGroup(after: .newItem) {
                Button("Etikett importieren …") {
                    appStore.requestLabelImport()
                }
                .keyboardShortcut("o")

                Button("Briefmarken-Bündel importieren …") { appStore.showPostageImporter = true }

                Button("Drucker verbinden …") {
                    appStore.showPrinterConnection = true
                }
                .keyboardShortcut("r")

                Button("Etsy-Adresse aus CSV übernehmen …") {
                    appStore.showEtsyImporter = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        Window("Browser-Erweiterung einrichten", id: "browser-extension-setup") {
            BrowserExtensionSetupView()
        }
        .defaultSize(width: 640, height: 650)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(appStore)
        }
    }
}
