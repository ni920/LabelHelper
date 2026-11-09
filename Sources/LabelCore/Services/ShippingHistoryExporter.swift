import Foundation

/// One CSV covering everything shipped: letter flows, the label history and
/// any print job in neither of them (stamp sheets).
public enum ShippingHistoryExporter {
    private static let header = [
        "Datum", "Art", "Empfänger / Titel", "Adresse", "Etsy-Bestellung", "Warenkorb-Nr.", "Porto",
        "Sendungsnummer", "Format", "Status", "Fehler"
    ]
    private static let separator = ";"
    private static let addressJobPrefix = "Brief · "

    public static func defaultFilename(date: Date = Date(), timeZone: TimeZone = .current) -> String {
        "Label-Helper-Verlauf-\(formatter("yyyy-MM-dd", timeZone).string(from: date)).csv"
    }

    /// Semicolons and a UTF-8 byte order mark so that a German Excel opens the
    /// file with columns and umlauts intact.
    public static func csvData(flows: [LetterShipmentFlow], records: [LabelHistoryRecord] = [], jobs: [PrintJob],
                               timeZone: TimeZone = .current) -> Data {
        let flowIDs = Set(flows.map(\.id))
        let recordIDs = Set(records.map(\.id))
        let standaloneJobs = jobs.filter { job in
            !recordIDs.contains(job.id) && (job.letterFlowID.map { !flowIDs.contains($0) } ?? true)
        }
        let dates = formatter("dd.MM.yyyy HH:mm", timeZone)
        let rows = (flows.map { (date: $0.createdAt, cells: cells(for: $0)) }
            + records.map { (date: $0.createdAt, cells: cells(for: $0)) }
            + standaloneJobs.map { (date: $0.createdAt, cells: cells(for: $0)) })
            .sorted { $0.date > $1.date }
            .map { row in [dates.string(from: row.date)] + row.cells }
        let lines = ([header] + rows).map { $0.map(escaped).joined(separator: separator) }
        return Data(("\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    private static func cells(for flow: LetterShipmentFlow) -> [String] {
        [
            "Brief mit Briefmarke", flow.recipientName, "", flow.orderID ?? "", "", flow.stamp.amount,
            flow.stamp.trackingNumber ?? "", flow.addressJob.resolvedLabelFormat.sizeDescription,
            flow.statusTitle, flow.errorMessage ?? ""
        ]
    }

    private static func cells(for job: PrintJob) -> [String] {
        let isAddressOnly = job.sourceFingerprint.hasPrefix("manual-address:")
        let kind = isAddressOnly ? "Brief (nur Adresse)" : job.postageStampIDs != nil ? "Briefmarken" : "Etikett"
        let title = isAddressOnly && job.title.hasPrefix(addressJobPrefix)
            ? String(job.title.dropFirst(addressJobPrefix.count)) : job.title
        let tracking = (job.postageStampIDs ?? []).compactMap(PostageStamp.trackingNumber(forID:)).joined(separator: ", ")
        return [kind, title, "", "", "", "", tracking, job.resolvedLabelFormat.sizeDescription, job.status.label, job.errorMessage ?? ""]
    }

    private static func cells(for record: LabelHistoryRecord) -> [String] {
        [
            record.product.map { "\(record.kind.title) · \($0)" } ?? record.kind.title,
            record.title, record.addressLines.joined(separator: ", "), record.orderID ?? "", record.cartNumber ?? "", "",
            record.trackingNumber ?? "", record.labelFormat.sizeDescription, record.status.label, record.errorMessage ?? ""
        ]
    }

    private static func escaped(_ value: String) -> String {
        // Names come from Etsy orders; a spreadsheet must not run them as formulas.
        let safe = value.first.map { "=+-@\t\r".contains($0) } == true ? "'" + value : value
        guard safe.contains(where: { "\";\r\n".contains($0) }) else { return safe }
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}
