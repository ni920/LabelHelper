import Foundation

public struct ApplicationDataLocation: Sendable {
    public let rootURL: URL
    public let migratedLegacyData: Bool
    public let warning: String?

    public init(rootURL: URL, migratedLegacyData: Bool, warning: String? = nil) {
        self.rootURL = rootURL
        self.migratedLegacyData = migratedLegacyData
        self.warning = warning
    }
}

public enum ApplicationDataError: LocalizedError {
    case invalidBackup
    case unsafeBackupLocation
    case symbolicLinkInBackup
    case operationFailed(String)
    case rollbackFailed(operation: String, rollback: String)

    public var errorDescription: String? {
        switch self {
        case .invalidBackup:
            "Der gewählte Ordner ist keine gültige Label-Helper-Datensicherung."
        case .unsafeBackupLocation:
            "Die Datensicherung darf nicht innerhalb des aktiven Label-Helper-Datenordners liegen."
        case .symbolicLinkInBackup:
            "Die Datensicherung enthält einen symbolischen Link und wird aus Sicherheitsgründen nicht wiederhergestellt."
        case .operationFailed(let message):
            message
        case let .rollbackFailed(operation, rollback):
            "Die Wiederherstellung ist fehlgeschlagen: \(operation) Auch der Rückweg zum bisherigen Datenstand ist fehlgeschlagen: \(rollback)"
        }
    }
}

public enum ApplicationDataManager {
    public static let currentDirectoryName = "LabelHelper"
    public static let legacyDirectoryName = "MunbynLabeler"
    public static let backupDataDirectoryName = "Data"
    public static let backupManifestName = "LabelHelperBackup.json"

    private struct BackupManifest: Codable {
        let formatVersion: Int
        let createdAt: Date
        let sourceDirectoryName: String
    }

    public static func prepareDefaultLocation(fileManager: FileManager = .default) -> ApplicationDataLocation {
        let parent = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return prepareLocation(in: parent, fileManager: fileManager)
    }

    public static func prepareLocation(in parent: URL, fileManager: FileManager = .default) -> ApplicationDataLocation {
        let current = parent.appendingPathComponent(currentDirectoryName, isDirectory: true)
        let legacy = parent.appendingPathComponent(legacyDirectoryName, isDirectory: true)

        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let currentType = itemType(at: current, fileManager: fileManager)
            let legacyType = itemType(at: legacy, fileManager: fileManager)

            if legacyType == .typeSymbolicLink {
                guard symbolicLink(at: legacy, pointsTo: current, fileManager: fileManager) else {
                    return fallbackLocation(
                        current: current,
                        legacy: legacy,
                        fileManager: fileManager,
                        warning: "Der alte Datenpfad ist ein unerwarteter symbolischer Link. Label Helper hat keine Daten verschoben."
                    )
                }
                if currentType == nil {
                    try fileManager.createDirectory(at: current, withIntermediateDirectories: true)
                } else if currentType != .typeDirectory {
                    throw ApplicationDataError.operationFailed("Der neue Label-Helper-Datenpfad ist kein Ordner.")
                }
                return ApplicationDataLocation(rootURL: current, migratedLegacyData: false)
            }

            if let currentType, currentType != .typeDirectory {
                throw ApplicationDataError.operationFailed("Der neue Label-Helper-Datenpfad ist kein Ordner.")
            }
            if let legacyType, legacyType != .typeDirectory {
                throw ApplicationDataError.operationFailed("Der bisherige Label-Helper-Datenpfad ist kein Ordner.")
            }

            if currentType == .typeDirectory, legacyType == .typeDirectory {
                if try directoryIsEmpty(current, fileManager: fileManager) {
                    try fileManager.removeItem(at: current)
                    return try migrate(legacy: legacy, current: current, fileManager: fileManager)
                }
                if try directoryIsEmpty(legacy, fileManager: fileManager) {
                    try fileManager.removeItem(at: legacy)
                    try fileManager.createSymbolicLink(at: legacy, withDestinationURL: current)
                    return ApplicationDataLocation(rootURL: current, migratedLegacyData: false)
                }
                return ApplicationDataLocation(
                    rootURL: legacy,
                    migratedLegacyData: false,
                    warning: "Am alten und am neuen Datenpfad liegen unterschiedliche Dateien. Label Helper verwendet aus Sicherheitsgründen weiterhin den alten Ordner und führt nichts automatisch zusammen."
                )
            }

            if legacyType == .typeDirectory {
                return try migrate(legacy: legacy, current: current, fileManager: fileManager)
            }

            if currentType == .typeDirectory {
                do {
                    try fileManager.createSymbolicLink(at: legacy, withDestinationURL: current)
                    return ApplicationDataLocation(rootURL: current, migratedLegacyData: false)
                } catch {
                    return ApplicationDataLocation(
                        rootURL: current,
                        migratedLegacyData: false,
                        warning: "Der neue Datenordner wird verwendet, aber der Kompatibilitätslink für ältere Installationen konnte nicht erstellt werden: \(error.localizedDescription)"
                    )
                }
            }

            try fileManager.createDirectory(at: current, withIntermediateDirectories: true)
            do {
                try fileManager.createSymbolicLink(at: legacy, withDestinationURL: current)
                return ApplicationDataLocation(rootURL: current, migratedLegacyData: false)
            } catch {
                return ApplicationDataLocation(
                    rootURL: current,
                    migratedLegacyData: false,
                    warning: "Der Datenordner wurde erstellt, aber der Kompatibilitätslink für ältere Installationen fehlt: \(error.localizedDescription)"
                )
            }
        } catch {
            return fallbackLocation(
                current: current,
                legacy: legacy,
                fileManager: fileManager,
                warning: "Der Datenordner konnte nicht auf den neuen Label-Helper-Pfad umgestellt werden: \(error.localizedDescription)"
            )
        }
    }

    @discardableResult
    public static func createBackup(
        of root: URL,
        in destinationParent: URL,
        fileManager: FileManager = .default,
        date: Date = Date(),
        namePrefix: String = "LabelHelper Backup"
    ) throws -> URL {
        guard itemType(at: root, fileManager: fileManager) == .typeDirectory else {
            throw ApplicationDataError.operationFailed("Der aktive Label-Helper-Datenordner wurde nicht gefunden.")
        }
        guard !isSameOrDescendant(destinationParent, of: root) else {
            throw ApplicationDataError.unsafeBackupLocation
        }
        try rejectSymbolicLinks(in: root, fileManager: fileManager)
        try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)

        let finalURL = availableBackupURL(in: destinationParent, prefix: namePrefix, date: date, fileManager: fileManager)
        let staging = destinationParent.appendingPathComponent(".LabelHelperBackup-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            try fileManager.copyItem(
                at: root,
                to: staging.appendingPathComponent(backupDataDirectoryName, isDirectory: true)
            )
            let manifest = BackupManifest(
                formatVersion: 1,
                createdAt: date,
                sourceDirectoryName: root.lastPathComponent
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(
                to: staging.appendingPathComponent(backupManifestName),
                options: .atomic
            )
            try fileManager.moveItem(at: staging, to: finalURL)
            return finalURL
        } catch {
            try? fileManager.removeItem(at: staging)
            throw ApplicationDataError.operationFailed("Die Datensicherung konnte nicht erstellt werden: \(error.localizedDescription)")
        }
    }

    @discardableResult
    public static func restoreBackup(
        from backup: URL,
        to root: URL,
        fileManager: FileManager = .default,
        date: Date = Date()
    ) throws -> URL? {
        guard !isSameOrDescendant(backup, of: root) else {
            throw ApplicationDataError.unsafeBackupLocation
        }
        let backupData = try validatedBackupData(at: backup, fileManager: fileManager)
        let parent = root.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let staging = parent.appendingPathComponent(".LabelHelperRestore-\(UUID().uuidString)", isDirectory: true)
        let rollback = parent.appendingPathComponent(".LabelHelperRollback-\(UUID().uuidString)", isDirectory: true)
        let existingRoot = itemType(at: root, fileManager: fileManager) == .typeDirectory
        let safetyBackup = existingRoot
            ? try createBackup(
                of: root,
                in: parent,
                fileManager: fileManager,
                date: date,
                namePrefix: "LabelHelper Before Restore"
            )
            : nil

        do {
            try fileManager.copyItem(at: backupData, to: staging)
            if existingRoot {
                try fileManager.moveItem(at: root, to: rollback)
            }
            do {
                try fileManager.moveItem(at: staging, to: root)
            } catch {
                if existingRoot {
                    do {
                        if itemType(at: root, fileManager: fileManager) != nil {
                            try fileManager.removeItem(at: root)
                        }
                        try fileManager.moveItem(at: rollback, to: root)
                    } catch let rollbackError {
                        throw ApplicationDataError.rollbackFailed(
                            operation: error.localizedDescription,
                            rollback: rollbackError.localizedDescription
                        )
                    }
                }
                throw error
            }
            try? fileManager.removeItem(at: rollback)
            return safetyBackup
        } catch let error as ApplicationDataError {
            try? fileManager.removeItem(at: staging)
            throw error
        } catch {
            try? fileManager.removeItem(at: staging)
            throw ApplicationDataError.operationFailed("Die Datensicherung konnte nicht wiederhergestellt werden: \(error.localizedDescription)")
        }
    }

    private static func migrate(
        legacy: URL,
        current: URL,
        fileManager: FileManager
    ) throws -> ApplicationDataLocation {
        try fileManager.moveItem(at: legacy, to: current)
        do {
            try fileManager.createSymbolicLink(at: legacy, withDestinationURL: current)
            return ApplicationDataLocation(rootURL: current, migratedLegacyData: true)
        } catch {
            do {
                try fileManager.moveItem(at: current, to: legacy)
            } catch let rollbackError {
                throw ApplicationDataError.rollbackFailed(
                    operation: error.localizedDescription,
                    rollback: rollbackError.localizedDescription
                )
            }
            throw error
        }
    }

    private static func fallbackLocation(
        current: URL,
        legacy: URL,
        fileManager: FileManager,
        warning: String
    ) -> ApplicationDataLocation {
        let root = itemType(at: legacy, fileManager: fileManager) == .typeDirectory ? legacy : current
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return ApplicationDataLocation(rootURL: root, migratedLegacyData: false, warning: warning)
    }

    private static func validatedBackupData(at backup: URL, fileManager: FileManager) throws -> URL {
        guard itemType(at: backup, fileManager: fileManager) == .typeDirectory else {
            throw ApplicationDataError.invalidBackup
        }
        let manifestURL = backup.appendingPathComponent(backupManifestName)
        let dataURL = backup.appendingPathComponent(backupDataDirectoryName, isDirectory: true)
        guard let manifestData = try? Data(contentsOf: manifestURL) else {
            throw ApplicationDataError.invalidBackup
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(BackupManifest.self, from: manifestData),
              manifest.formatVersion == 1,
              itemType(at: dataURL, fileManager: fileManager) == .typeDirectory else {
            throw ApplicationDataError.invalidBackup
        }
        try rejectSymbolicLinks(in: dataURL, fileManager: fileManager)
        return dataURL
    }

    private static func rejectSymbolicLinks(in directory: URL, fileManager: FileManager) throws {
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw ApplicationDataError.invalidBackup
        }
        for case let url as URL in enumerator {
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            } catch {
                throw ApplicationDataError.invalidBackup
            }
            if values.isSymbolicLink == true {
                throw ApplicationDataError.symbolicLinkInBackup
            }
        }
        if enumerationError != nil {
            throw ApplicationDataError.invalidBackup
        }
    }

    private static func itemType(at url: URL, fileManager: FileManager) -> FileAttributeType? {
        (try? fileManager.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType
    }

    private static func symbolicLink(at link: URL, pointsTo destination: URL, fileManager: FileManager) -> Bool {
        guard let rawDestination = try? fileManager.destinationOfSymbolicLink(atPath: link.path) else {
            return false
        }
        let resolved: URL
        if rawDestination.hasPrefix("/") {
            resolved = URL(fileURLWithPath: rawDestination)
        } else {
            resolved = link.deletingLastPathComponent().appendingPathComponent(rawDestination)
        }
        return resolved.standardizedFileURL.path == destination.standardizedFileURL.path
    }

    private static func directoryIsEmpty(_ url: URL, fileManager: FileManager) throws -> Bool {
        try fileManager.contentsOfDirectory(atPath: url.path).isEmpty
    }

    private static func isSameOrDescendant(_ candidate: URL, of directory: URL) -> Bool {
        let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        let directoryPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
        return candidatePath == directoryPath || candidatePath.hasPrefix(directoryPath + "/")
    }

    private static func availableBackupURL(
        in parent: URL,
        prefix: String,
        date: Date,
        fileManager: FileManager
    ) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let baseName = "\(prefix) \(formatter.string(from: date))"
        var candidate = parent.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while itemType(at: candidate, fileManager: fileManager) != nil {
            candidate = parent.appendingPathComponent("\(baseName) \(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }
}
