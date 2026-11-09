import Combine
import Foundation

/// Kept apart from the print queue, so clearing finished jobs keeps their history.
@MainActor
public final class LabelHistoryStore: ObservableObject {
    @Published public private(set) var records: [LabelHistoryRecord] = []
    @Published public private(set) var storageError: String?
    private var unreadable = false
    private let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("verlauf.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            records = try JSONDecoder().decode([LabelHistoryRecord].self, from: Data(contentsOf: url))
        } catch {
            unreadable = true
            storageError = "Der Label-Verlauf konnte nicht gelesen werden: \(error.localizedDescription)"
        }
    }

    public func add(_ record: LabelHistoryRecord) {
        var updated = records.filter { $0.id != record.id && $0.sourceFingerprint != record.sourceFingerprint }
        updated.insert(record, at: 0)
        save(updated)
    }

    public func updateStatus(_ id: UUID, status: PrintJob.Status, errorMessage: String?) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        var updated = records
        updated[index].status = status
        updated[index].errorMessage = errorMessage
        save(updated)
    }

    /// Adds jobs from before the history existed and repairs a status left
    /// behind when the app stopped during a print.
    public func adopt(_ jobs: [PrintJob], parse: (URL) -> ParcelLabelInfo? = ParcelLabelParser.parse(url:)) {
        var updated = records
        for job in jobs {
            if let index = updated.firstIndex(where: { $0.id == job.id }) {
                updated[index].status = job.status
                updated[index].errorMessage = job.errorMessage
            } else if !updated.contains(where: { $0.sourceFingerprint == job.sourceFingerprint }),
                      let record = LabelHistoryRecord(job: job, parcelInfo: parse(job.sourceURL)) {
                updated.append(record)
            }
        }
        updated.sort { $0.createdAt > $1.createdAt }
        if updated != records { save(updated) }
    }

    /// Never writes over a file that could not be read.
    private func save(_ updated: [LabelHistoryRecord]) {
        guard !unreadable else { return }
        do {
            try JSONEncoder().encode(updated).write(to: url, options: .atomic)
            records = updated
        } catch {
            storageError = "Der Label-Verlauf konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }
}
