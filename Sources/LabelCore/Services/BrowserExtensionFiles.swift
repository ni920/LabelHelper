import Foundation

public enum BrowserExtensionSetupError: LocalizedError {
    case missingBundle
    case invalidManifest
    case cleanupFailed(preparation: String, cleanup: String)

    public var errorDescription: String? {
        switch self {
        case .missingBundle:
            "Die Erweiterungsdateien fehlen in dieser App. Bitte die vollständige Label-Helper-App aus dem Release installieren."
        case .invalidManifest:
            "Die mitgelieferte Browser-Erweiterung ist unvollständig oder ungültig. Bitte Label Helper erneut installieren."
        case let .cleanupFailed(preparation, cleanup):
            "Die Vorbereitung ist fehlgeschlagen: \(preparation) Temporäre Dateien konnten nicht entfernt werden: \(cleanup)"
        }
    }
}

public enum BrowserExtensionFiles {
    public static let resourcePaths = [
        "manifest.json", "etsy-order.js", "content.js", "README.md",
        "icons/icon-16.png", "icons/icon-32.png", "icons/icon-48.png", "icons/icon-128.png"
    ]

    public static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("MunbynLabeler/BrowserExtension", isDirectory: true)
    }

    /// Keeps the unpacked extension at a stable path, independent of app updates.
    @discardableResult
    public static func prepare(from source: URL, at destination: URL) throws -> URL {
        let files = try resourcePaths.map { path in
            (path: path, data: try Data(contentsOf: source.appendingPathComponent(path)))
        }
        guard let manifestData = files.first(where: { $0.path == "manifest.json" })?.data,
              let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              manifest["manifest_version"] as? Int == 3,
              let version = manifest["version"] as? String, !version.isEmpty else {
            throw BrowserExtensionSetupError.invalidManifest
        }

        let manager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".BrowserExtension-\(UUID().uuidString)", isDirectory: true)
        do {
            try manager.createDirectory(at: staging.appendingPathComponent("icons"), withIntermediateDirectories: true)
            for file in files {
                try file.data.write(to: staging.appendingPathComponent(file.path), options: .atomic)
            }
            if manager.fileExists(atPath: destination.path) {
                let values = try destination.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    throw CocoaError(.fileWriteFileExists)
                }
                _ = try manager.replaceItemAt(destination, withItemAt: staging)
            } else {
                try manager.moveItem(at: staging, to: destination)
            }
        } catch {
            let preparationError = error
            if manager.fileExists(atPath: staging.path) {
                do {
                    try manager.removeItem(at: staging)
                } catch {
                    throw BrowserExtensionSetupError.cleanupFailed(
                        preparation: preparationError.localizedDescription, cleanup: error.localizedDescription)
                }
            }
            throw preparationError
        }
        return destination
    }
}
