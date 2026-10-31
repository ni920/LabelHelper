import AppKit
import LabelCore
import PDFKit

private enum TestFailure: Error {
    case assertion(String)
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure.assertion(message) }
}

@main
struct PrintLayoutTests {
    static func main() {
        do {
            try runTests()
        } catch {
            fputs("Print layout tests failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func runTests() throws {
        let sender = SenderAddress(name: "Test Shop", street: "Musterweg 1", postalCode: "12345", city: "Teststadt", country: "Deutschland")
        let short = RecipientAddress(name: "Alex Muster", street1: "Teststrasse 42", postalCode: "54321", city: "Musterstadt", country: "Deutschland")
        let international = RecipientAddress(name: "Robin Example", street1: "123 Example Street", street2: "Apartment 456",
                                             postalCode: "90210", city: "Example City", state: "California", country: "United States")
        let long = RecipientAddress(name: String(repeating: "Example ", count: 16) + "LASTNAME",
                                    street1: String(repeating: "Longstreet ", count: 16) + "987",
                                    street2: "Additional address line", postalCode: "12345", city: "Lastcity", state: "Laststate", country: "Lastcountry")
        let shortFormat = EtsyAddressLabelWriter.continuousFormat(recipient: short, sender: sender)
        try require(shortFormat.heightMM < 36, "A normal address must be shorter than 36 mm, not 55 mm")
        for recipient in [short, international, long] {
            let format = EtsyAddressLabelWriter.continuousFormat(recipient: recipient, sender: sender)
            let data = try EtsyAddressLabelWriter.makePDFData(recipient: recipient, sender: sender, format: format)
            guard let page = PDFDocument(data: data)?.page(at: 0), let text = page.string else {
                throw TestFailure.assertion("Address PDF is unreadable")
            }
            let normalized = text.filter { !$0.isWhitespace }.uppercased()
            for field in [recipient.name, recipient.street1, recipient.street2, recipient.postalCode,
                          recipient.city, recipient.state, sender.name, sender.street, sender.postalCode, sender.city] where !field.isEmpty {
                try require(normalized.contains(field.filter { !$0.isWhitespace }.uppercased()), "Address field missing: \(field)")
            }
            if recipient.country != "Deutschland" {
                try require(normalized.contains(recipient.country.filter { !$0.isWhitespace }.uppercased()), "Country missing")
            }
            let bounds = page.bounds(for: .mediaBox)
            try require(abs(bounds.height - format.heightMM * 72 / 25.4) < 0.01, "Address PDF uses a stale fixed height")
            let raster = try LabelRenderer.render(pdfData: data, format: format)
            try checkPrintGeometry(raster, format: format)
            let blackRows = (0..<raster.height).filter { y in
                raster.bitmap[(y * raster.bytesPerRow)..<((y + 1) * raster.bytesPerRow)].contains { $0 != 0 }
            }
            try require(!blackRows.isEmpty, "Address raster is empty")
            if let first = blackRows.first, let last = blackRows.last {
                try require(first >= 16 && raster.height - last >= 16, "Address ink touches a cut edge")
                try require(first < 48 && raster.height - last < 48,
                            "Excessive blank space above or below address: top \(first), bottom \(raster.height - last), height \(raster.height) dots")
            }
            print("Address output: \(format.sizeDescription), \(raster.height) rows")
        }
        let longFormat = EtsyAddressLabelWriter.continuousFormat(recipient: long, sender: sender)
        try require(longFormat.heightMM > shortFormat.heightMM, "Long address must grow instead of clipping")
        for format in [LabelFormat.address89x36, .product100x50, .continuousLetter100x55] {
            let data = try EtsyAddressLabelWriter.makePDFData(recipient: short, sender: sender, format: format)
            let bounds = PDFDocument(data: data)!.page(at: 0)!.bounds(for: .mediaBox)
            try require(abs(bounds.height - format.heightMM * 72 / 25.4) < 0.01, "Existing fixed address format changed")
        }
        try checkPostage(addressFormat: shortFormat)
        print("Print layout tests passed: complete addresses, compact PDFs, unchanged postage pixels and shorter printer payloads")
    }

    private static func checkPrintGeometry(_ raster: LabelRaster, format: LabelFormat) throws {
        let printed = ContinuousLabelCutGuide.applying(to: raster)
        let paper = ContinuousLabelCutGuide.printFormat(for: format)
        try require(printed.width == 800 && printed.height == paper.heightDots, "Physical print size differs from preview")
        try require(printed.bitmap.prefix(raster.bitmap.count) == raster.bitmap, "Cut strip changed content pixels")
        let sections = MunbynRW403BProtocol.printSections(raster: printed)
        try require(!sections.isEmpty && sections.reduce(0) { $0 + $1.uncompressedLength } == 100 * paper.heightDots,
                    "Bluetooth payload contains extra feed rows or loses rows")
    }

    private static func checkPostage(addressFormat: LabelFormat) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("print-layout-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("synthetic-stamp.pdf")
        var box = CGRect(x: 0, y: 0, width: 116, height: 68)
        guard let context = CGContext(source as CFURL, mediaBox: &box, nil) else {
            throw TestFailure.assertion("Cannot write synthetic stamp")
        }
        context.beginPDFPage(nil)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 4, y: 4, width: 30, height: 30))
        context.fill(CGRect(x: 43, y: 45, width: 68, height: 4))
        context.fill(CGRect(x: 43, y: 12, width: 50, height: 3))
        context.endPDFPage()
        context.closePDF()
        let stamp = PostageStamp(id: "TEST", sourceURL: source, pageNumber: 1, number: 1, amount: "TEST", sourceRect: box)
        let fixed = try PostagePDFService.writeSheets(stamps: [stamp], format: .shipping100x150, cutGuides: false, directory: directory)[0]
        let compact = try PostagePDFService.writeSheets(stamps: [stamp], format: .shipping100x150, cutGuides: false,
                                                       directory: directory, fitHeightToContent: true)[0]
        let originalRaster = try LabelRenderer.render(url: fixed.url, format: fixed.format)
        let compactRaster = try LabelRenderer.render(url: compact.url, format: compact.format)
        try require(compact.format.heightMM < 30, "Single postage stamp uses more than 30 mm")
        try require(originalRaster.bitmap.prefix(compactRaster.bitmap.count) == compactRaster.bitmap,
                    "Shortening changed original postage pixels or position")
        try require(originalRaster.bitmap.dropFirst(compactRaster.bitmap.count).allSatisfy { $0 == 0 },
                    "Shortening discarded printed content")
        try checkPrintGeometry(compactRaster, format: compact.format)
        let combinedLength = addressFormat.heightMM + compact.format.heightMM + 2 * ContinuousLabelCutGuide.extraLengthMM
        try require(combinedLength < 70, "Normal address + stamp must use less than 70 mm instead of 114 mm")
        let saved = try JSONEncoder().encode(compact.format)
        let restored = try JSONDecoder().decode(LabelFormat.self, from: saved)
        try require(restored == compact.format, "Saved print format lost its automatic dimensions")
        print("Synthetic postage: \(compact.format.sizeDescription); address + postage with cut strips: \(combinedLength) mm (previously 114 mm)")
    }
}
