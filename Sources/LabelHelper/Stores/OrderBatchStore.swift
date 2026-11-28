import Foundation
import LabelCore

struct BatchOrder: Identifiable, Codable, Equatable {
    var id = UUID()
    let orderID: String
    let recipient: RecipientAddress
    let packingNote: String
    var submitted = false

    func matches(_ other: Self) -> Bool {
        if !orderID.isEmpty, orderID != "Unbekannt", !orderID.hasPrefix("Zeile-") {
            return orderID == other.orderID
        }
        return recipient == other.recipient && packingNote == other.packingNote
    }
}

@MainActor
final class OrderBatchStore: ObservableObject {
    typealias Submit = (@escaping (Result<Void, Error>) -> Void) -> Void
    typealias Prepare = (BatchOrder) throws -> Submit

    @Published private(set) var orders: [BatchOrder] = []
    @Published private(set) var running = false
    @Published private(set) var stopping = false
    @Published private(set) var message: String?
    @Published private(set) var storageError: String?
    private let url: URL
    private var activeID: UUID?
    private var completed = 0
    private var total = 0

    init(directory: URL) {
        url = directory.appendingPathComponent("Sammeldruck.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { orders = try JSONDecoder().decode([BatchOrder].self, from: Data(contentsOf: url)) }
        catch { storageError = "Der gespeicherte Sammeldruck konnte nicht gelesen werden." }
    }

    @discardableResult
    func add(_ additions: [BatchOrder]) -> Bool {
        guard !running, storageError == nil else { return false }
        var updated = orders
        for entry in additions where !updated.contains(where: { $0.matches(entry) }) {
            updated.append(entry)
        }
        let count = updated.count - orders.count
        guard save(updated) else { return false }
        message = count == 0 ? "Bereits im Sammeldruck." : "\(count) hinzugefügt · \(updated.count) im Sammeldruck."
        return true
    }

    func remove(_ id: UUID) {
        guard !running, storageError == nil else { return }
        _ = save(orders.filter { $0.id != id })
    }

    func start(prepare: @escaping Prepare) {
        guard !running, storageError == nil, orders.contains(where: { !$0.submitted }) else { return }
        completed = 0
        total = orders.filter { !$0.submitted }.count
        stopping = false
        running = true
        next(prepare)
    }

    func stopAfterCurrent() { stopping = true }

    private func next(_ prepare: @escaping Prepare) {
        guard running else { return }
        guard !stopping, let index = orders.firstIndex(where: { !$0.submitted }) else {
            finish("\(completed) von \(total) Briefen gedruckt.")
            return
        }
        let entry = orders[index]
        do {
            let submit = try prepare(entry)
            var updated = orders
            updated[index].submitted = true
            // Persist the handoff before any paper moves. An interrupted job
            // can then only be resumed individually from its history entry.
            guard save(updated) else { finish(storageError ?? "Speichern fehlgeschlagen."); return }
            activeID = entry.id
            message = "Brief \(completed + 1) von \(total) · \(entry.recipient.name)"
            submit { [weak self] result in
                guard let self, self.activeID == entry.id else { return }
                self.activeID = nil
                switch result {
                case .success:
                    guard self.save(self.orders.filter { $0.id != entry.id }) else {
                        self.finish(self.storageError ?? "Speichern fehlgeschlagen.")
                        return
                    }
                    self.completed += 1
                    Task { @MainActor in self.next(prepare) }
                case .failure(let error):
                    self.finish("Angehalten bei \(entry.recipient.name). \(error.localizedDescription) Bitte den Auftrag im Label-Verlauf prüfen.")
                }
            }
        } catch {
            finish("Angehalten bei \(entry.recipient.name). \(error.localizedDescription)")
        }
    }

    private func finish(_ text: String) {
        message = text
        stopping = false
        running = false
    }

    private func save(_ updated: [BatchOrder]) -> Bool {
        do {
            try JSONEncoder().encode(updated).write(to: url, options: .atomic)
            orders = updated
            return true
        } catch {
            storageError = "Der Sammeldruck konnte nicht gespeichert werden: \(error.localizedDescription)"
            return false
        }
    }
}
