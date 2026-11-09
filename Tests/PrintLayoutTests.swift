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
        try checkDesign(recipient: short, long: long, sender: sender)
        try checkCombined(recipients: [short, international, long], sender: sender)
        print("Print layout tests passed: complete addresses, compact PDFs, unchanged postage pixels, shorter printer payloads and label designs")
    }

    private static func inkBounds(_ raster: LabelRaster) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
        var result: (minX: Int, maxX: Int, minY: Int, maxY: Int)?
        for y in 0..<raster.height {
            for x in 0..<raster.width where raster.bitmap[y * raster.bytesPerRow + x / 8] & (0x80 >> UInt8(x % 8)) != 0 {
                result = (min(result?.minX ?? x, x), max(result?.maxX ?? x, x), min(result?.minY ?? y, y), max(result?.maxY ?? y, y))
            }
        }
        return result
    }

    private static func ink(_ recipient: RecipientAddress, _ sender: SenderAddress, _ format: LabelFormat,
                            _ design: AddressLabelDesign) throws -> (minX: Int, maxX: Int, minY: Int, maxY: Int) {
        let data = try EtsyAddressLabelWriter.makePDFData(recipient: recipient, sender: sender, format: format, design: design)
        guard let bounds = inkBounds(try LabelRenderer.render(pdfData: data, format: format)) else {
            throw TestFailure.assertion("Designed label is empty")
        }
        return bounds
    }

    private static func checkCombined(recipients: [RecipientAddress], sender: SenderAddress) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("combined-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("stamp.pdf")
        var box = CGRect(x: 0, y: 0, width: 116, height: 68)
        guard let context = CGContext(source as CFURL, mediaBox: &box, nil) else { throw TestFailure.assertion("Cannot write stamp") }
        context.beginPDFPage(nil)
        context.fill(CGRect(x: 2, y: 2, width: 112, height: 64))
        context.endPDFPage()
        context.closePDF()
        let stamp = PostageStamp(id: "TEST", sourceURL: source, pageNumber: 1, number: 1, amount: "TEST", sourceRect: box)
        var settings = CombinedLabelSettings.standard
        settings.isEnabled = true
        for arrangement in CombinedLabelSettings.Arrangement.allCases {
            settings.arrangement = arrangement
            for recipient in recipients {
                let label = try EtsyAddressLabelWriter.makeCombinedPDF(
                    recipient: recipient, sender: sender, stamp: stamp, stampSize: box.size, format: .shipping100x150, continuous: true,
                    settings: settings, placement: .standard, design: .standard
                )
                let text = (PDFDocument(data: label.data)?.page(at: 0)?.string ?? "").filter { !$0.isWhitespace }.uppercased()
                for field in [recipient.name, recipient.street1, recipient.postalCode, recipient.city] {
                    try require(text.contains(field.filter { !$0.isWhitespace }.uppercased()), "Combined label lost \(field)")
                }
                let raster = try LabelRenderer.render(pdfData: label.data, format: label.format)
                try checkPrintGeometry(raster, format: label.format)
                let ink = raster.bitmap.reduce(0) { $0 + $1.nonzeroBitCount }
                let dotsPerPoint: Double = LabelFormat.dotsPerMillimeter * 25.4 / 72
                let stampInk = Int((112 * dotsPerPoint) * (64 * dotsPerPoint))
                try require(ink > stampInk * 9 / 10, "Combined label lost the stamp: \(ink) of \(stampInk) dots")
            }
        }
        settings.arrangement = .stampRight
        let fixed = try EtsyAddressLabelWriter.makeCombinedPDF(
            recipient: recipients[0], sender: sender, stamp: stamp, stampSize: box.size, format: .product100x50, continuous: false,
            settings: settings, placement: .standard, design: .standard
        )
        let raster = try LabelRenderer.render(pdfData: fixed.data, format: fixed.format)
        guard let bounds = inkBounds(raster) else { throw TestFailure.assertion("Combined fixed label is empty") }
        try require(fixed.format == .product100x50 && bounds.maxX > 760 && bounds.minY < 40, "Stamp is not in the top right corner")
        do {
            _ = try EtsyAddressLabelWriter.makeCombinedPDF(
                recipient: recipients[0], sender: sender, stamp: stamp, stampSize: box.size, format: .custom(widthMM: 50, heightMM: 30), continuous: false,
                settings: settings, placement: .standard, design: .standard
            )
            throw TestFailure.assertion("A label too small for address and stamp must be refused")
        } catch EtsyAddressLabelWriterError.stampDoesNotFit {}
    }

    private static func checkDesign(recipient: RecipientAddress, long: RecipientAddress, sender: SenderAddress) throws {
        let large = LabelFormat.shipping100x150
        var hidden = AddressLabelDesign.standard
        hidden.senderPlacement = .hidden

        let data = try EtsyAddressLabelWriter.makePDFData(recipient: recipient, sender: sender, format: large, design: hidden)
        let text = PDFDocument(data: data)?.page(at: 0)?.string ?? ""
        try require(!text.contains(sender.name) && text.contains(recipient.name), "Hidden sender is still printed")
        try require(EtsyAddressLabelWriter.continuousFormat(recipient: recipient, sender: sender, design: hidden).heightMM
                    < EtsyAddressLabelWriter.continuousFormat(recipient: recipient, sender: sender).heightMM,
                    "Hiding the sender must shorten a continuous label")

        var design = hidden
        design.recipientAlignment = .trailing
        let right = try ink(recipient, sender, large, design)
        design.recipientAlignment = .center
        let center = try ink(recipient, sender, large, design)
        let left = try ink(recipient, sender, large, hidden)
        try require(left.minX < center.minX && center.minX < right.minX, "Recipient alignment has no effect")
        try require(abs((center.minX + center.maxX) - large.widthDots) < 16, "Centered address is off-center")

        design = hidden
        design.recipientVerticalPlacement = .top
        let top = try ink(recipient, sender, large, design)
        design.recipientVerticalPlacement = .bottom
        let bottom = try ink(recipient, sender, large, design)
        try require(top.minY < 120 && large.heightDots - bottom.maxY < 120, "Vertical placement has no effect")

        var senderBelow = AddressLabelDesign.standard
        senderBelow.senderPlacement = .bottom
        let continuous = EtsyAddressLabelWriter.continuousFormat(recipient: recipient, sender: sender, design: senderBelow)
        let continuousPDF = try EtsyAddressLabelWriter.makePDFData(recipient: recipient, sender: sender, format: continuous, design: senderBelow)
        let topInk = try ink(recipient, sender, continuous, senderBelow)
        let standardTop = try ink(recipient, sender, EtsyAddressLabelWriter.continuousFormat(recipient: recipient, sender: sender), .standard)
        try require(!continuousPDF.isEmpty && topInk.minY != standardTop.minY, "Sender placement has no effect on continuous labels")

        var margin = AddressLabelDesign.standard
        margin.extraMarginMM = 5
        let marginInk = try ink(recipient, sender, large, margin)
        let standardInk = try ink(recipient, sender, large, .standard)
        try require(marginInk.minX - standardInk.minX >= 36, "Extra margin has no effect")

        // Every extreme either renders a complete address or refuses; it must never cut lines off.
        for format in [LabelFormat.address89x36, .address70x36, .square50, .product100x50, .shipping100x150] {
            for scale in [AddressLabelDesign.scaleRange.lowerBound, AddressLabelDesign.scaleRange.upperBound] {
                for typeface in AddressLabelDesign.Typeface.allCases {
                    var extreme = AddressLabelDesign.standard
                    extreme.recipientScale = scale
                    extreme.senderScale = scale
                    extreme.typeface = typeface
                    extreme.extraMarginMM = scale > 1 ? 8 : 0
                    extreme.showsSeparator = true
                    do {
                        let data = try EtsyAddressLabelWriter.makePDFData(recipient: recipient, sender: sender, format: format, design: extreme)
                        let text = (PDFDocument(data: data)?.page(at: 0)?.string ?? "").filter { !$0.isWhitespace }
                        for field in [recipient.name, recipient.street1, recipient.postalCode, recipient.city] {
                            try require(text.contains(field.filter { !$0.isWhitespace }), "Lost \(field) on \(format.name)")
                        }
                    } catch EtsyAddressLabelWriterError.addressDoesNotFit {
                        continue
                    }
                }
            }
        }
        do {
            _ = try EtsyAddressLabelWriter.makePDFData(recipient: long, sender: sender, format: .address70x36)
            throw TestFailure.assertion("An address that cannot fit must be refused, not cut off")
        } catch EtsyAddressLabelWriterError.addressDoesNotFit {}
        for scale in [0.7, 1.5] {
            var extreme = AddressLabelDesign.standard
            extreme.recipientScale = scale
            extreme.senderScale = scale
            extreme.extraMarginMM = 8
            extreme.showsSeparator = true
            let format = EtsyAddressLabelWriter.continuousFormat(recipient: long, sender: sender, design: extreme)
            _ = try EtsyAddressLabelWriter.makePDFData(recipient: long, sender: sender, format: format, design: extreme)
        }
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
