import AppKit
import CoreText
import Foundation
import LabelCore

enum EtsyAddressLabelWriterError: LocalizedError {
    case cannotCreateDirectory
    case cannotCreateDocument
    case addressDoesNotFit
    case stampDoesNotFit

    var errorDescription: String? {
        switch self {
        case .cannotCreateDirectory: "Der Ordner für Adressetiketten konnte nicht erstellt werden."
        case .cannotCreateDocument: "Das Adressetikett konnte nicht erzeugt werden."
        case .stampDoesNotFit: "Adresse und Briefmarke passen nicht zusammen auf dieses Etikett. Bitte ein größeres Format oder im Etikett-Design eine andere Anordnung wählen."
        case .addressDoesNotFit: "Die Adresse passt nicht vollständig auf dieses Etikett. Bitte ein größeres Format wählen oder im Etikett-Design Schrift und Rand verkleinern."
        }
    }
}

enum EtsyAddressLabelWriter {
    private static let compactMargin: CGFloat = 9
    private static let compactSenderFontSize: CGFloat = 9
    private static let compactSenderGap: CGFloat = 6

    static func continuousFormat(
        recipient: RecipientAddress,
        sender: SenderAddress,
        design: AddressLabelDesign = .standard,
        widthMM: Double = LabelFormat.continuousRollWidthMM
    ) -> LabelFormat {
        let width = widthMM * 72 / 25.4
        let margin = compactMargin + extraMargin(design)
        let recipient = compactRecipient(recipientLines(recipient), width: width - 2 * margin, design: design)
        let senderHeight = showsSender(sender, design)
            ? compactSenderFontSize * CGFloat(design.senderScale) * 1.65 + compactSenderGap
            : 0
        return .continuous(widthMM: widthMM, heightMM: (2 * margin + senderHeight + recipient.height) * 25.4 / 72)
    }

    /// One label with address and stamp. Pass no stamp for a layout preview.
    static func makeCombinedPDF(
        recipient: RecipientAddress,
        sender: SenderAddress,
        stamp: PostageStamp?,
        stampSize: CGSize,
        format: LabelFormat,
        continuous: Bool,
        settings: CombinedLabelSettings,
        placement: PostageStampPlacement,
        design: AddressLabelDesign
    ) throws -> (data: Data, format: LabelFormat) {
        let measure: ((Double) -> LabelFormat)? = continuous
            ? { continuousFormat(recipient: recipient, sender: sender, design: design, widthMM: $0) }
            : nil
        guard let layout = CombinedLabelLayout(format: format, stampSize: stampSize, settings: settings, placement: placement,
                                               continuousAddressFormat: measure) else {
            throw EtsyAddressLabelWriterError.stampDoesNotFit
        }
        let address = try makePDFData(recipient: recipient, sender: sender, format: layout.addressFormat, design: design)
        return (try PostagePDFService.combinedLabelData(addressPDF: address, layout: layout, stamp: stamp), layout.format)
    }

    static func write(
        order: EtsyOrder,
        sender: SenderAddress,
        format: LabelFormat,
        fileManager: FileManager = .default
    ) throws -> URL {
        try write(
            recipient: order.recipientAddress,
            sender: sender,
            format: format,
            filenamePrefix: "Etsy-\(order.id)",
            footer: nil,
            design: .standard,
            fileManager: fileManager
        )
    }

    static func write(
        recipient: RecipientAddress,
        sender: SenderAddress,
        format: LabelFormat,
        design: AddressLabelDesign = .standard,
        fileManager: FileManager = .default
    ) throws -> URL {
        try write(
            recipient: recipient,
            sender: sender,
            format: format,
            filenamePrefix: "Adresse-\(UUID().uuidString)",
            footer: nil,
            design: design,
            fileManager: fileManager
        )
    }

    private static func write(
        recipient: RecipientAddress,
        sender: SenderAddress,
        format: LabelFormat,
        filenamePrefix: String,
        footer: String?,
        design: AddressLabelDesign,
        fileManager: FileManager
    ) throws -> URL {
        let directory = ApplicationDataManager.prepareDefaultLocation(fileManager: fileManager).rootURL
            .appendingPathComponent("Address Labels", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw EtsyAddressLabelWriterError.cannotCreateDirectory
        }

        let safePrefix = sanitizedFilename(filenamePrefix)
        let safeName = sanitizedFilename(recipient.name)
        let url = directory.appendingPathComponent("\(safePrefix)-\(safeName).pdf")
        let pdf = try makePDFData(
            recipient: recipient,
            sender: sender,
            format: format,
            footer: footer,
            design: design
        )
        do {
            try pdf.write(to: url, options: .atomic)
        } catch {
            throw EtsyAddressLabelWriterError.cannotCreateDocument
        }

        guard fileManager.fileExists(atPath: url.path),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 0 else {
            throw EtsyAddressLabelWriterError.cannotCreateDocument
        }
        return url
    }

    static func makePDFData(
        recipient: RecipientAddress,
        sender: SenderAddress,
        format: LabelFormat,
        footer: String? = nil,
        design: AddressLabelDesign = .standard
    ) throws -> Data {
        let pointsPerMillimeter = 72.0 / 25.4
        var mediaBox = CGRect(
            x: 0,
            y: 0,
            width: format.widthMM * pointsPerMillimeter,
            height: format.heightMM * pointsPerMillimeter
        )
        let data = NSMutableData()

        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw EtsyAddressLabelWriterError.cannotCreateDocument
        }

        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(mediaBox)
        context.setFillColor(NSColor.black.cgColor)

        let compact = format.usesAutomaticHeight
        let margin = (compact ? compactMargin : max(9, min(mediaBox.width, mediaBox.height) * 0.055)) + extraMargin(design)
        let senderFontSize = (compact ? compactSenderFontSize : max(5.5, min(9, mediaBox.height * 0.07))) * CGFloat(design.senderScale)
        let hasSenderBlock = design.senderPlacement != .hidden && !(compact && senderLine(sender).isEmpty)
        let senderHeight = hasSenderBlock ? senderFontSize * 1.65 : 0
        let senderGap = hasSenderBlock ? (compact ? compactSenderGap : 10) : 0
        let footerHeight = footer == nil ? 0 : max(8, mediaBox.height * 0.08)
        let contentBottom = margin + footerHeight
        let contentTop = mediaBox.height - margin
        let senderOnTop = design.senderPlacement != .bottom
        let senderRect = CGRect(
            x: margin,
            y: senderOnTop ? contentTop - senderHeight : contentBottom,
            width: mediaBox.width - 2 * margin,
            height: senderHeight
        )
        if hasSenderBlock {
            drawFittedLine(
                senderLine(sender),
                in: senderRect,
                maximumFontSize: senderFontSize,
                minimumFontSize: 5.0,
                design: design,
                context: context
            )
            if design.showsSeparator {
                let y = senderOnTop ? senderRect.minY - senderGap / 2 : senderRect.maxY + senderGap / 2
                context.setStrokeColor(NSColor.black.cgColor)
                context.setLineWidth(0.75)
                context.strokeLineSegments(between: [CGPoint(x: senderRect.minX, y: y), CGPoint(x: senderRect.maxX, y: y)])
            }
        }

        let senderBlock = senderHeight + senderGap
        let recipientBottom = contentBottom + (senderOnTop ? 0 : senderBlock)
        let recipientRect = CGRect(
            x: margin,
            y: recipientBottom,
            width: mediaBox.width - 2 * margin,
            height: max(20, contentTop - (senderOnTop ? senderBlock : 0) - recipientBottom)
        )
        if compact {
            let content = compactRecipient(recipientLines(recipient), width: recipientRect.width, design: design)
            guard content.height <= recipientRect.height else {
                context.endPDFPage()
                context.closePDF()
                throw EtsyAddressLabelWriterError.cannotCreateDocument
            }
            let rect = CGRect(x: recipientRect.minX, y: recipientRect.maxY - content.height,
                              width: recipientRect.width, height: content.height)
            let framesetter = CTFramesetterCreateWithAttributedString(content.text)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                                CGPath(rect: rect, transform: nil), nil)
            guard CTFrameGetVisibleStringRange(frame).length == CFAttributedStringGetLength(content.text) else {
                context.endPDFPage()
                context.closePDF()
                throw EtsyAddressLabelWriterError.cannotCreateDocument
            }
            CTFrameDraw(frame, context)
        } else {
            guard drawRecipient(recipientLines(recipient), in: recipientRect, design: design, context: context) else {
                context.endPDFPage()
                context.closePDF()
                throw EtsyAddressLabelWriterError.addressDoesNotFit
            }
        }

        if let footer {
            drawLine(
                footer,
                in: CGRect(x: margin, y: margin, width: mediaBox.width - 2 * margin, height: footerHeight),
                font: NSFont.systemFont(ofSize: max(5.5, min(8, footerHeight * 0.65))),
                context: context,
                alignment: .right,
                truncate: true
            )
        }

        context.endPDFPage()
        context.closePDF()
        guard data.length > 0 else {
            throw EtsyAddressLabelWriterError.cannotCreateDocument
        }
        return data as Data
    }

    private static func compactRecipient(_ lines: [String], width: CGFloat, design: AddressLabelDesign) -> (text: CFAttributedString, height: CGFloat) {
        // Fixed readable type, independent of roll length. Long addresses wrap
        // and grow the label instead of being clipped to a short paper size.
        var fontSize = 13 * CGFloat(design.recipientScale)
        while fontSize > 8.5 && widestLine(lines, fontSize: fontSize, design: design) > width { fontSize -= 0.5 }
        let text = recipientText(lines, fontSize: fontSize, design: design)
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), nil
        )
        return (text, ceil(size.height + fontSize * 0.2))
    }

    /// Returns false instead of printing an address with lines cut off.
    private static func drawRecipient(_ lines: [String], in rect: CGRect, design: AddressLabelDesign, context: CGContext) -> Bool {
        guard rect.width > 0 else { return false }
        let upperBound = min(18, max(9.5, min(rect.width / 19, rect.height / 5.2))) * CGFloat(design.recipientScale)
        var fontSize = upperBound
        while fontSize > 8.5 {
            let attributed = recipientText(lines, fontSize: fontSize, design: design)
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let textLength = CFAttributedStringGetLength(attributed)
            let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                CFRange(location: 0, length: textLength),
                nil,
                CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                nil
            )
            if suggested.height <= rect.height && widestLine(lines, fontSize: fontSize, design: design) <= rect.width { break }
            fontSize -= 0.5
        }

        let attributed = recipientText(lines, fontSize: fontSize, design: design)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let textLength = CFAttributedStringGetLength(attributed)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: textLength),
            nil,
            CGSize(width: rect.width, height: rect.height),
            nil
        )
        let textHeight = min(rect.height, suggested.height + fontSize * 0.2)
        let freeHeight = max(0, rect.height - textHeight)
        let verticalOffset: CGFloat
        switch design.recipientVerticalPlacement {
        case .top: verticalOffset = freeHeight
        case .center: verticalOffset = freeHeight / 2
        case .bottom: verticalOffset = 0
        }
        let textRect = CGRect(
            x: rect.minX,
            y: rect.minY + verticalOffset,
            width: rect.width,
            height: textHeight
        )
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: textLength), path, nil)
        guard CTFrameGetVisibleStringRange(frame).length == textLength else { return false }
        CTFrameDraw(frame, context)
        return true
    }

    private static func recipientText(_ lines: [String], fontSize: CGFloat, design: AddressLabelDesign) -> CFAttributedString {
        let text = lines.joined(separator: "\n")
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = fontSize * 0.12
        paragraph.alignment = textAlignment(design.recipientAlignment)
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: recipientFont(size: fontSize, isName: false, design: design),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph
            ]
        )
        if let firstLine = lines.first, !firstLine.isEmpty {
            attributed.addAttribute(
                .font,
                value: recipientFont(size: fontSize, isName: true, design: design),
                range: NSRange(location: 0, length: (firstLine as NSString).length)
            )
        }
        return attributed
    }

    private static func widestLine(_ lines: [String], fontSize: CGFloat, design: AddressLabelDesign) -> CGFloat {
        lines.enumerated().map { index, line in
            let font = recipientFont(size: fontSize, isName: index == 0, design: design)
            let attributed = NSAttributedString(string: line, attributes: [.font: font])
            return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil))
        }.max() ?? 0
    }

    private static func recipientFont(size: CGFloat, isName: Bool, design: AddressLabelDesign) -> NSFont {
        let weight: NSFont.Weight
        switch (design.recipientWeight, isName && design.emphasizesName) {
        case (.regular, false): weight = .regular
        case (.medium, false): weight = .medium
        case (.semibold, false), (.regular, true), (.medium, true): weight = .semibold
        case (.bold, false), (.semibold, true): weight = .bold
        case (.bold, true): weight = .heavy
        }
        return makeFont(size: size, weight: weight, typeface: design.typeface)
    }

    private static func makeFont(size: CGFloat, weight: NSFont.Weight, typeface: AddressLabelDesign.Typeface) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        let design: NSFontDescriptor.SystemDesign
        switch typeface {
        case .system: return system
        case .rounded: design = .rounded
        case .serif: design = .serif
        case .monospaced: design = .monospaced
        }
        return system.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? system
    }

    private static func textAlignment(_ placement: AddressLabelDesign.HorizontalPlacement) -> NSTextAlignment {
        switch placement {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
    }

    private static func extraMargin(_ design: AddressLabelDesign) -> CGFloat {
        CGFloat(design.extraMarginMM) * 72 / 25.4
    }

    private static func showsSender(_ sender: SenderAddress, _ design: AddressLabelDesign) -> Bool {
        design.senderPlacement != .hidden && !senderLine(sender).isEmpty
    }

    private static func drawFittedLine(
        _ text: String,
        in rect: CGRect,
        maximumFontSize: CGFloat,
        minimumFontSize: CGFloat,
        design: AddressLabelDesign,
        context: CGContext
    ) {
        var fontSize = maximumFontSize
        while fontSize > minimumFontSize {
            let font = makeFont(size: fontSize, weight: .regular, typeface: design.typeface)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
            if CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) <= rect.width { break }
            fontSize -= 0.25
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: makeFont(size: fontSize, weight: .regular, typeface: design.typeface),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let x: CGFloat
        switch design.senderAlignment {
        case .leading: x = rect.minX
        case .center: x = max(rect.minX, rect.midX - width / 2)
        case .trailing: x = max(rect.minX, rect.maxX - width)
        }
        context.textPosition = CGPoint(x: x, y: rect.midY - (ascent + descent) / 2)
        CTLineDraw(line, context)
    }

    private static func drawLine(
        _ text: String,
        in rect: CGRect,
        font: NSFont,
        context: CGContext,
        alignment: NSTextAlignment = .left,
        truncate: Bool = false
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = truncate ? .byTruncatingTail : .byWordWrapping
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        let y = rect.midY - (ascent + descent) / 2
        context.textPosition = CGPoint(x: rect.minX, y: y)
        if alignment == .right {
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            context.textPosition.x = max(rect.minX, rect.maxX - width)
        }
        CTLineDraw(line, context)
    }

    private static func sanitizedFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let value = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        return String(value).replacingOccurrences(of: "--", with: "-").prefix(60).description
    }

    private static func recipientLines(_ recipient: RecipientAddress) -> [String] {
        var lines = [recipient.name, recipient.street1]
        if !recipient.street2.isEmpty { lines.append(recipient.street2) }
        let locality = [recipient.postalCode, recipient.city]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !locality.isEmpty { lines.append(locality) }
        if !recipient.state.isEmpty, !lines.contains(recipient.state) { lines.append(recipient.state) }
        if !recipient.country.isEmpty, !isGermany(recipient.country) {
            lines.append(recipient.country.uppercased(with: Locale(identifier: "de_DE")))
        }
        return lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func senderLine(_ sender: SenderAddress) -> String {
        var parts = [sender.name, sender.street, "\(sender.postalCode) \(sender.city)"]
        if !sender.country.isEmpty, !isGermany(sender.country) { parts.append(sender.country) }
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private static func isGermany(_ value: String) -> Bool {
        let normalized = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
            .filter { $0.isLetter }
        return ["de", "deutschland", "germany", "bundesrepublikdeutschland"].contains(normalized)
    }
}
