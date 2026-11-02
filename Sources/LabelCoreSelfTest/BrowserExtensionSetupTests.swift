import Foundation
import LabelCore

func runBrowserExtensionSetupTests() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("extension-setup-\(UUID())")
    try manager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: root) }
    let source = root.appendingPathComponent("bundle/BrowserExtension")
    let destination = root.appendingPathComponent("support/BrowserExtension")
    try manager.createDirectory(at: source.appendingPathComponent("icons"), withIntermediateDirectories: true)
    for path in BrowserExtensionFiles.resourcePaths {
        let data = path == "manifest.json"
            ? Data(#"{"manifest_version":3,"version":"1.0.0"}"#.utf8) : Data("fixture: \(path)".utf8)
        try data.write(to: source.appendingPathComponent(path))
    }
    let prepared = try BrowserExtensionFiles.prepare(from: source, at: destination)
    try require(prepared == destination,
                "Prepared extension must keep its stable installation path")
    for path in BrowserExtensionFiles.resourcePaths {
        let original = try Data(contentsOf: source.appendingPathComponent(path))
        let copy = try Data(contentsOf: destination.appendingPathComponent(path))
        try require(original == copy, "Prepared extension file differs: \(path)")
    }
    let script = destination.appendingPathComponent("content.js")
    try Data("updated script".utf8).write(to: source.appendingPathComponent("content.js"))
    try BrowserExtensionFiles.prepare(from: source, at: destination)
    var scriptText = try String(contentsOf: script, encoding: .utf8)
    try require(scriptText == "updated script",
                "Repeated setup must update the existing folder rather than create a new path")

    try manager.removeItem(at: source.appendingPathComponent("content.js"))
    do {
        try BrowserExtensionFiles.prepare(from: source, at: destination)
        throw SelfTestFailure.assertion("An incomplete bundled extension was accepted")
    } catch is CocoaError {}
    scriptText = try String(contentsOf: script, encoding: .utf8)
    try require(scriptText == "updated script",
                "A missing bundled resource must leave the previously prepared extension intact")

    try Data("valid script".utf8).write(to: source.appendingPathComponent("content.js"))
    let blocked = root.appendingPathComponent("blocked")
    try Data("do not replace".utf8).write(to: blocked)
    do {
        try BrowserExtensionFiles.prepare(from: source, at: blocked)
        throw SelfTestFailure.assertion("Setup overwrote a file instead of an extension folder")
    } catch is CocoaError {}
    let blockedText = try String(contentsOf: blocked, encoding: .utf8)
    try require(blockedText == "do not replace", "Setup overwrote another file")
    let remainingFiles = try manager.contentsOfDirectory(atPath: root.path)
    try require(remainingFiles.allSatisfy { !$0.hasPrefix(".BrowserExtension-") },
                "Failed setup left staging files behind")

    try Data(#"{"manifest_version":2,"version":"1.0"}"#.utf8).write(to: source.appendingPathComponent("manifest.json"))
    do {
        try BrowserExtensionFiles.prepare(from: source, at: destination)
        throw SelfTestFailure.assertion("An unsupported extension manifest was accepted")
    } catch BrowserExtensionSetupError.invalidManifest {}
    scriptText = try String(contentsOf: script, encoding: .utf8)
    try require(scriptText == "updated script",
                "An invalid bundled extension must preserve the previous installation")
    var journey = BrowserExtensionSetupJourney()
    journey.advance()
    try require(journey.step == .files, "Setup must not advance when file preparation failed")
    journey.didPrepareFiles(); journey.advance()
    journey.advance()
    try require(journey.step == .browser, "Opening a browser must not imply developer mode is enabled")
    journey.browserConfigured = true; journey.advance()
    journey.advance()
    try require(journey.step == .installation, "Prepared files must not be reported as an installed extension")
    journey.installationConfirmed = true; journey.advance()
    journey.advance()
    try require(journey.step == .access, "Installation must not imply website permission")
    journey.accessConfirmed = true; journey.advance()
    try require(journey.step == .transfer && !journey.canAdvance, "A browser opening must not confirm a successful order transfer")
    journey.transferConfirmed = true; journey.advance()
    try require(journey.step == .transfer && journey.canAdvance, "Completed setup must remain bounded at its final step")
    journey.select(.safari)
    try require(journey.step == .files && journey.filesPrepared && !journey.browserConfigured &&
                !journey.installationConfirmed && !journey.accessConfirmed && !journey.transferConfirmed,
                "Switching browser must retain files and reset browser-specific confirmations")
    journey.advance(); journey.browserConfigured = true; journey.advance(); journey.back()
    try require(journey.step == .browser && journey.filesPrepared, "Back must preserve the prepared folder")
    journey.restart()
    try require(journey.step == .files && journey.filesPrepared && !journey.browserConfigured,
                "Reopening setup must clear previous confirmations")
    print("Browser extension setup passed: resource copy, stable updates, validation, failure recovery")
}
