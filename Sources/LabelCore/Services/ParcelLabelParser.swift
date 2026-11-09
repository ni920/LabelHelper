import Foundation
import PDFKit

public struct ParcelLabelInfo: Codable, Equatable, Sendable {
    public let recipientName: String?
    public let addressLines: [String]
    public let trackingNumber: String?
    public let product: String?
    public let cartNumber: String?
    public let createdOn: String?

    public init(
        recipientName: String?,
        addressLines: [String] = [],
        trackingNumber: String?,
        product: String? = nil,
        cartNumber: String? = nil,
        createdOn: String? = nil
    ) {
        self.recipientName = recipientName
        self.addressLines = addressLines
        self.trackingNumber = trackingNumber
        self.product = product
        self.cartNumber = cartNumber
        self.createdOn = createdOn
    }
}

/// Reads the text layer of a DHL online-franking PDF. Anything else, such as
/// an image-only label, yields nil and stays in the history by its file name.
public enum ParcelLabelParser {
    public static func parse(url: URL) -> ParcelLabelInfo? {
        guard url.pathExtension.lowercased() == "pdf",
              let document = PDFDocument(url: url), !document.isLocked else { return nil }
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        return parse(text: text)
    }

    public static func parse(text: String) -> ParcelLabelInfo? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let address = addressBlock(after: "Empfänger:", in: lines) ?? addressBlock(after: "An:", in: lines) ?? []
        let tracking = value(of: "Sendungsnummer:", in: lines).flatMap(normalizedTrackingNumber)
        guard !address.isEmpty || tracking != nil else { return nil }
        return ParcelLabelInfo(
            recipientName: address.first,
            addressLines: address,
            trackingNumber: tracking,
            product: value(of: "Produkt:", in: lines),
            cartNumber: value(of: "Warenkorb-Nr.:", in: lines),
            createdOn: value(of: "Erstelldatum:", in: lines)
        )
    }

    private static func value(of label: String, in lines: [String]) -> String? {
        guard let index = lines.firstIndex(where: { $0.hasPrefix(label) }) else { return nil }
        let inline = lines[index].dropFirst(label.count).trimmingCharacters(in: .whitespaces)
        if !inline.isEmpty { return inline }
        guard index + 1 < lines.count, !isFieldLabel(lines[index + 1]) else { return nil }
        return lines[index + 1]
    }

    private static func addressBlock(after label: String, in lines: [String]) -> [String]? {
        guard let start = lines.firstIndex(where: { $0.hasPrefix(label) }) else { return nil }
        let inline = lines[start].dropFirst(label.count).trimmingCharacters(in: .whitespaces)
        let following = lines[(start + 1)...].prefix { !isFieldLabel($0) }.prefix(6)
        let block = (inline.isEmpty ? [] : [inline]) + following
        return block.isEmpty ? nil : block
    }

    /// "Produkt: …" or "An:" ends an address; "Str. 5" or "c/o Name" does not.
    private static func isFieldLabel(_ line: String) -> Bool {
        guard let colon = line.firstIndex(of: ":") else { return false }
        return !line[..<colon].contains(" ")
    }

    private static func normalizedTrackingNumber(_ raw: String) -> String? {
        let value = raw.filter { !$0.isWhitespace && $0 != "." }.uppercased()
        guard value.count >= 10, value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return value
    }
}
