import CoreGraphics
import Foundation
import LabelCore

func runHistoryExportTests() throws {
    let source = URL(fileURLWithPath: "/tmp/label.pdf")
    let flowID = UUID()
    let trackingID = "0123456789ABCDEF0123"
    let stamp = PostageStamp(id: trackingID, sourceURL: source, pageNumber: 1, number: 1, amount: "0,95",
                             sourceRect: CGRect(x: 0, y: 0, width: 10, height: 10))
    let addressJob = PrintJob(sourceURL: source, sourceFingerprint: "letter-address", labelFormat: .address89x36, letterFlowID: flowID)
    let stampJob = PrintJob(sourceURL: source, sourceFingerprint: "letter-stamp", labelFormat: .address89x36,
                            postageStampIDs: [trackingID], letterFlowID: flowID)
    let flow = LetterShipmentFlow(id: flowID, recipientName: "Müller; \"Ana\"", orderID: "4711", stamp: stamp,
                                  addressJob: addressJob, stampJob: stampJob,
                                  createdAt: Date(timeIntervalSince1970: 2_000), stage: .completed)
    let addressOnly = PrintJob(sourceURL: source, sourceFingerprint: "manual-address:1|712x288",
                               createdAt: Date(timeIntervalSince1970: 3_000), labelFormat: .address89x36,
                               displayName: "Brief · =HYPERLINK(1)", status: .printed)
    let stampSheet = PrintJob(sourceURL: source, sourceFingerprint: "sheet", createdAt: Date(timeIntervalSince1970: 1_000),
                              labelFormat: .shipping100x150, displayName: "Briefmarken · 1 Marken",
                              postageStampIDs: [trackingID])

    let utc = TimeZone(identifier: "UTC")!
    let data = ShippingHistoryExporter.csvData(flows: [flow], jobs: [stampSheet, addressJob, stampJob, addressOnly], timeZone: utc)
    try require(data.starts(with: [0xEF, 0xBB, 0xBF]), "History CSV lacks the byte order mark Excel needs for umlauts")
    let rows = String(decoding: data, as: UTF8.self).dropFirst().components(separatedBy: "\r\n").filter { !$0.isEmpty }

    try require(rows.count == 4, "History must list the flow once and never its own print jobs, got \(rows.count) rows")
    try require(rows[0].hasPrefix("Datum;Art;"), "History CSV header is wrong")
    try require(rows[1].hasPrefix("01.01.1970 00:50;Brief (nur Adresse);"), "History is not sorted newest first: \(rows[1])")
    try require(rows[1].contains(";'=HYPERLINK(1);"), "A spreadsheet formula in a name was not neutralized: \(rows[1])")
    try require(rows[1].contains(";Gedruckt;"), "Print status is missing: \(rows[1])")
    try require(rows[2].contains(";Brief mit Briefmarke;\"Müller; \"\"Ana\"\"\";;4711;;0,95;\(trackingID);"),
                "Letter row is not escaped correctly: \(rows[2])")
    try require(rows[3].contains(";Briefmarken;") && rows[3].contains(trackingID), "Stamp sheet lost its tracking number: \(rows[3])")
    try require(ShippingHistoryExporter.defaultFilename(date: Date(timeIntervalSince1970: 0), timeZone: utc) == "Label-Helper-Verlauf-1970-01-01.csv",
                "Default export filename is wrong")

    try MainActor.assumeIsolated { try runParcelHistoryTests(source: source, utc: utc) }

    var design = AddressLabelDesign.standard
    design.senderPlacement = .bottom
    design.recipientScale = 1.25
    let restored = try JSONDecoder().decode(AddressLabelDesign.self, from: JSONEncoder().encode(design))
    try require(restored == design, "Saved label design lost its settings")
}

@MainActor
private func runParcelHistoryTests(source: URL, utc: TimeZone) throws {
    let text = """
    Absender: Test Shop GmbH
    Musterweg 1
    12345 Teststadt
    Deutschland
    Empfänger: Alex Muster
    c/o Robin Beispiel
    Teststr. 42
    54321 Musterstadt
    Deutschland
    Produkt: Päckchen M
    Warenkorb-Nr.: AB1CD2E3FG4H
    Erstelldatum: 01.11.2026
    Bitte beachten: langer Hinweistext
    Von:
    Test Shop GmbH
    An:
    Alex Muster
    Sendungsnummer: 12.345.678901 2
    max. 35 x 25 x 10 cm
    PAK-ID: ABC D1E F2G HIJ
    """
    guard let info = ParcelLabelParser.parse(text: text) else {
        throw SelfTestFailure.assertion("DHL label text was not recognized")
    }
    try require(info.recipientName == "Alex Muster", "Parcel recipient took the wrong line")
    try require(info.addressLines == ["Alex Muster", "c/o Robin Beispiel", "Teststr. 42", "54321 Musterstadt", "Deutschland"],
                "Parcel address block is wrong: \(info.addressLines)")
    try require(info.trackingNumber == "123456789012", "Tracking number was not normalized: \(info.trackingNumber ?? "nil")")
    try require(info.product == "Päckchen M" && info.cartNumber == "AB1CD2E3FG4H" && info.createdOn == "01.11.2026",
                "Parcel details are wrong")
    try require(ParcelLabelParser.parse(text: "Irgendein anderes Etikett\nOhne Felder") == nil, "Unrelated text must not yield parcel data")
    let fallback = ParcelLabelParser.parse(text: "An:\nRobin Beispiel\nTestweg 1\nSendungsnummer: 00340434161234567890")
    try require(fallback?.recipientName == "Robin Beispiel" && fallback?.trackingNumber == "00340434161234567890",
                "Second address block on the label was not used")
    try require(ParcelLabelParser.parse(url: URL(fileURLWithPath: "/nonexistent/label.pdf")) == nil, "Missing PDF must not yield data")

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("label-history-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let parcel = PrintJob(sourceURL: source, sourceFingerprint: "parcel|800x1200", createdAt: Date(timeIntervalSince1970: 5_000),
                          labelFormat: .shipping100x150, status: .ready)
    let flowJob = PrintJob(sourceURL: source, sourceFingerprint: "flow", labelFormat: .address89x36, letterFlowID: UUID())
    let stampJob = PrintJob(sourceURL: source, sourceFingerprint: "stamp", labelFormat: .shipping100x150, postageStampIDs: ["X"])
    let unknownFile = PrintJob(sourceURL: source, sourceFingerprint: "image", labelFormat: .address89x36, displayName: "motiv.png")

    let store = LabelHistoryStore(directory: directory)
    store.adopt([parcel, flowJob, stampJob, unknownFile]) { $0 == source ? nil : info }
    try require(store.records.count == 2, "Letter flows and stamp sheets must stay out of the label history")
    try require(store.records.first { $0.id == parcel.id }?.kind == .parcel, "A 100 × 150 label without text must still count as parcel")
    try require(store.records.first { $0.id == unknownFile.id }?.title == "motiv.png", "Unreadable labels must keep their file name")

    guard let record = LabelHistoryRecord(job: parcel, parcelInfo: info, orderID: "4711") else {
        throw SelfTestFailure.assertion("Parcel job produced no history record")
    }
    store.add(record)
    try require(store.records.count == 2 && store.records[0].trackingNumber == "123456789012", "Adding a label must replace its older record")
    store.updateStatus(parcel.id, status: .printed, errorMessage: nil)

    // Clearing the queue only ever removes jobs; a restart must keep the label and its status.
    let reloaded = LabelHistoryStore(directory: directory)
    reloaded.adopt([])
    try require(reloaded.records.first { $0.id == parcel.id }?.status == .printed, "Parcel history does not survive without its print job")

    let rows = String(decoding: ShippingHistoryExporter.csvData(flows: [], records: reloaded.records, jobs: [parcel], timeZone: utc), as: UTF8.self)
        .components(separatedBy: "\r\n").filter { !$0.isEmpty }
    try require(rows.count == 3, "Parcel must be exported once, got \(rows.count - 1) rows")
    try require(rows.contains { $0.contains(";Paketlabel · Päckchen M;Alex Muster;Alex Muster, c/o Robin Beispiel, Teststr. 42, 54321 Musterstadt, Deutschland;4711;AB1CD2E3FG4H;;123456789012;") },
                "Parcel row is wrong: \(rows)")

    let brokenDirectory = directory.appendingPathComponent("broken", isDirectory: true)
    try FileManager.default.createDirectory(at: brokenDirectory, withIntermediateDirectories: true)
    let brokenFile = brokenDirectory.appendingPathComponent("verlauf.json")
    try Data("kaputt".utf8).write(to: brokenFile)
    let broken = LabelHistoryStore(directory: brokenDirectory)
    broken.add(record)
    let brokenAfterAdd = try Data(contentsOf: brokenFile)
    try require(broken.storageError != nil && brokenAfterAdd == Data("kaputt".utf8), "An unreadable history file must never be overwritten")
    print("Label history tests passed: DHL parsing, persistence without print jobs, export and damaged files")
}
