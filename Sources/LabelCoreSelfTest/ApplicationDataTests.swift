import Foundation
import LabelCore

func runApplicationDataTests() throws {
    let fileManager = FileManager.default
    let temporaryRoot = fileManager.temporaryDirectory
        .appendingPathComponent("LabelHelper-ApplicationDataTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: temporaryRoot) }
    try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

    try testLegacyMigration(in: temporaryRoot.appendingPathComponent("Migration"), fileManager: fileManager)
    try testMigrationRollback(in: temporaryRoot.appendingPathComponent("MigrationRollback"))
    try testConflictingDirectories(in: temporaryRoot.appendingPathComponent("Conflict"), fileManager: fileManager)
    try testBackupAndRestore(in: temporaryRoot.appendingPathComponent("Backup"), fileManager: fileManager)
    try testRestoreRollback(in: temporaryRoot.appendingPathComponent("RestoreRollback"), fileManager: fileManager)
    try testBackupValidation(in: temporaryRoot.appendingPathComponent("Validation"), fileManager: fileManager)
}

private func testLegacyMigration(in parent: URL, fileManager: FileManager) throws {
    let legacy = parent.appendingPathComponent(ApplicationDataManager.legacyDirectoryName, isDirectory: true)
    let current = parent.appendingPathComponent(ApplicationDataManager.currentDirectoryName, isDirectory: true)
    try fileManager.createDirectory(at: legacy, withIntermediateDirectories: true)
    try Data("history".utf8).write(to: legacy.appendingPathComponent("print-jobs.json"))

    let migrated = ApplicationDataManager.prepareLocation(in: parent, fileManager: fileManager)
    try require(migrated.rootURL == current, "Legacy data did not move to the new application data path")
    try require(migrated.migratedLegacyData, "Successful legacy migration was not reported")
    try require(migrated.warning == nil, "Successful legacy migration returned a warning")
    let migratedHistory = try Data(contentsOf: current.appendingPathComponent("print-jobs.json"))
    try require(
        migratedHistory == Data("history".utf8),
        "Legacy migration lost persisted data"
    )
    let legacyDestination = try fileManager.destinationOfSymbolicLink(atPath: legacy.path)
    try require(
        legacyDestination == current.path,
        "Legacy compatibility link points to the wrong directory"
    )

    let repeated = ApplicationDataManager.prepareLocation(in: parent, fileManager: fileManager)
    try require(repeated.rootURL == current, "Repeated migration changed the application data path")
    try require(!repeated.migratedLegacyData, "Repeated migration was not idempotent")
    try require(repeated.warning == nil, "Repeated migration returned a warning")
}

private func testMigrationRollback(in parent: URL) throws {
    let fileManager = SymlinkFailingFileManager()
    let legacy = parent.appendingPathComponent(ApplicationDataManager.legacyDirectoryName, isDirectory: true)
    let current = parent.appendingPathComponent(ApplicationDataManager.currentDirectoryName, isDirectory: true)
    try fileManager.createDirectory(at: legacy, withIntermediateDirectories: true)
    try Data("preserve".utf8).write(to: legacy.appendingPathComponent("data.txt"))

    let result = ApplicationDataManager.prepareLocation(in: parent, fileManager: fileManager)
    try require(result.rootURL == legacy, "Failed migration did not return to the legacy data path")
    try require(result.warning != nil, "Failed migration did not report a warning")
    try require(fileManager.fileExists(atPath: legacy.appendingPathComponent("data.txt").path), "Migration rollback lost legacy data")
    try require(!fileManager.fileExists(atPath: current.path), "Migration rollback left a partial current data directory")
}

private func testConflictingDirectories(in parent: URL, fileManager: FileManager) throws {
    let legacy = parent.appendingPathComponent(ApplicationDataManager.legacyDirectoryName, isDirectory: true)
    let current = parent.appendingPathComponent(ApplicationDataManager.currentDirectoryName, isDirectory: true)
    try fileManager.createDirectory(at: legacy, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: current, withIntermediateDirectories: true)
    try Data("legacy".utf8).write(to: legacy.appendingPathComponent("legacy.txt"))
    try Data("current".utf8).write(to: current.appendingPathComponent("current.txt"))

    let result = ApplicationDataManager.prepareLocation(in: parent, fileManager: fileManager)
    try require(result.rootURL == legacy, "Conflicting data directories should retain the legacy path")
    try require(result.warning != nil, "Conflicting data directories did not produce a warning")
    try require(fileManager.fileExists(atPath: legacy.appendingPathComponent("legacy.txt").path), "Legacy conflict data was changed")
    try require(fileManager.fileExists(atPath: current.appendingPathComponent("current.txt").path), "Current conflict data was changed")
}

private func testBackupAndRestore(in testRoot: URL, fileManager: FileManager) throws {
    let root = testRoot.appendingPathComponent("Application Support/LabelHelper", isDirectory: true)
    let backupParent = testRoot.appendingPathComponent("Backups", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("original".utf8).write(to: root.appendingPathComponent("print-jobs.json"))

    let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
    let backup = try ApplicationDataManager.createBackup(
        of: root,
        in: backupParent,
        fileManager: fileManager,
        date: fixedDate
    )
    try require(
        fileManager.fileExists(atPath: backup.appendingPathComponent(ApplicationDataManager.backupManifestName).path),
        "Backup manifest is missing"
    )
    let backedUpJobs = try Data(contentsOf: backup
        .appendingPathComponent(ApplicationDataManager.backupDataDirectoryName)
        .appendingPathComponent("print-jobs.json"))
    try require(
        backedUpJobs == Data("original".utf8),
        "Backup does not contain the application data"
    )

    try Data("changed".utf8).write(to: root.appendingPathComponent("print-jobs.json"))
    try Data("remove-me".utf8).write(to: root.appendingPathComponent("temporary.txt"))
    let safetyBackup = try ApplicationDataManager.restoreBackup(
        from: backup,
        to: root,
        fileManager: fileManager,
        date: fixedDate
    )
    try require(safetyBackup != nil, "Restore did not create a safety backup")
    let restoredJobs = try Data(contentsOf: root.appendingPathComponent("print-jobs.json"))
    try require(
        restoredJobs == Data("original".utf8),
        "Restore did not replace the current data"
    )
    try require(
        !fileManager.fileExists(atPath: root.appendingPathComponent("temporary.txt").path),
        "Restore retained files that were not present in the backup"
    )
    if let safetyBackup {
        let safetyData = safetyBackup
            .appendingPathComponent(ApplicationDataManager.backupDataDirectoryName)
            .appendingPathComponent("print-jobs.json")
        let safetyJobs = try Data(contentsOf: safetyData)
        try require(safetyJobs == Data("changed".utf8), "Safety backup lost the pre-restore data")
    }

    do {
        _ = try ApplicationDataManager.createBackup(of: root, in: root, fileManager: fileManager)
        throw SelfTestFailure.assertion("Backup inside the active data directory was accepted")
    } catch ApplicationDataError.unsafeBackupLocation {
    }

    let nestedDirectory = root.appendingPathComponent("Nested", isDirectory: true)
    let nestedAlias = testRoot.appendingPathComponent("NestedAlias", isDirectory: true)
    try fileManager.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
    try fileManager.createSymbolicLink(at: nestedAlias, withDestinationURL: nestedDirectory)
    do {
        _ = try ApplicationDataManager.createBackup(of: root, in: nestedAlias, fileManager: fileManager)
        throw SelfTestFailure.assertion("Backup through a symbolic link into the active data directory was accepted")
    } catch ApplicationDataError.unsafeBackupLocation {
    }
}

private func testRestoreRollback(in testRoot: URL, fileManager: FileManager) throws {
    let root = testRoot.appendingPathComponent("Live", isDirectory: true)
    let backupParent = testRoot.appendingPathComponent("Backups", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("backup".utf8).write(to: root.appendingPathComponent("data.txt"))
    let backup = try ApplicationDataManager.createBackup(of: root, in: backupParent, fileManager: fileManager)
    try Data("live".utf8).write(to: root.appendingPathComponent("data.txt"))

    let failingFileManager = RestoreSwapFailingFileManager()
    failingFileManager.failedRootPath = root.path
    do {
        _ = try ApplicationDataManager.restoreBackup(from: backup, to: root, fileManager: failingFileManager)
        throw SelfTestFailure.assertion("Injected restore failure unexpectedly succeeded")
    } catch let error as ApplicationDataError {
        guard case .operationFailed = error else { throw error }
    }
    let retainedData = try Data(contentsOf: root.appendingPathComponent("data.txt"))
    try require(retainedData == Data("live".utf8), "Restore rollback did not preserve the live data")
}

private func testBackupValidation(in testRoot: URL, fileManager: FileManager) throws {
    let root = testRoot.appendingPathComponent("Live", isDirectory: true)
    let backupParent = testRoot.appendingPathComponent("Backups", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("live".utf8).write(to: root.appendingPathComponent("data.txt"))

    let invalid = testRoot.appendingPathComponent("Invalid", isDirectory: true)
    try fileManager.createDirectory(at: invalid, withIntermediateDirectories: true)
    do {
        _ = try ApplicationDataManager.restoreBackup(from: invalid, to: root, fileManager: fileManager)
        throw SelfTestFailure.assertion("Folder without a backup manifest was accepted")
    } catch ApplicationDataError.invalidBackup {
    }

    let backup = try ApplicationDataManager.createBackup(of: root, in: backupParent, fileManager: fileManager)
    let linkedFile = backup
        .appendingPathComponent(ApplicationDataManager.backupDataDirectoryName)
        .appendingPathComponent("linked-data")
    try fileManager.createSymbolicLink(atPath: linkedFile.path, withDestinationPath: root.appendingPathComponent("data.txt").path)
    do {
        _ = try ApplicationDataManager.restoreBackup(from: backup, to: root, fileManager: fileManager)
        throw SelfTestFailure.assertion("Backup containing a symbolic link was accepted")
    } catch ApplicationDataError.symbolicLinkInBackup {
    }
}

private final class SymlinkFailingFileManager: FileManager, @unchecked Sendable {
    override func createSymbolicLink(at url: URL, withDestinationURL destURL: URL) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}

private final class RestoreSwapFailingFileManager: FileManager, @unchecked Sendable {
    var failedRootPath: String?

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if srcURL.lastPathComponent.hasPrefix(".LabelHelperRestore-"),
           dstURL.path == failedRootPath {
            throw CocoaError(.fileWriteUnknown)
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}
