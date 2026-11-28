import AppKit
import CoreText
import LabelCore

/// Composes the detachable part into the job PDF so a retry uses the same slip.
enum PackingSlipWriter {
    enum SlipError: LocalizedError {
        case tooLong
        var errorDescription: String? { "Der Packhinweis ist zu lang für ein Etikett. Bitte kürze ihn in der Briefvorschau." }
    }

    static func append(_ note: String, to pdf: Data, format: LabelFormat,
                       additionalFeedMM: Double) throws -> (Data, LabelFormat) {
        guard let provider = CGDataProvider(data: pdf as CFData),
              let page = CGPDFDocument(provider)?.page(at: 1) else { throw LabelRendererError.cannotReadDocument }

        let pt = 72.0 / 25.4
        let width = format.widthMM * pt
        let margin = 3 * pt
        let attributed = NSAttributedString(string: note, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.black
        ])
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let textWidth = width - 2 * margin
        let size = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil,
            CGSize(width: textWidth, height: .greatestFiniteMagnitude), nil)
        let textHeight = ceil(size.height) + 2
        let guideMM = ContinuousLabelCutGuide.extraLengthMM
        let stripMM = max(additionalFeedMM, (textHeight + 2 * margin) / pt)
        let totalMM = ceil((format.heightMM + guideMM + stripMM) * LabelFormat.dotsPerMillimeter) / LabelFormat.dotsPerMillimeter
        guard totalMM <= 300 else { throw SlipError.tooLong }
        let result = LabelFormat.continuousWithPackingSlip(widthMM: format.widthMM, heightMM: totalMM)
        var bounds = CGRect(x: 0, y: 0, width: width, height: totalMM * pt)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else {
            throw LabelRendererError.cannotCreateBitmap
        }
        let offset = (totalMM - format.heightMM) * pt
        let textRect = CGRect(x: margin, y: (offset - guideMM * pt - textHeight) / 2,
                              width: textWidth, height: textHeight)
        let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: textRect, transform: nil), nil)
        guard CTFrameGetVisibleStringRange(frame).length == attributed.length else { throw SlipError.tooLong }

        context.beginPDFPage(nil)
        context.saveGState()
        context.translateBy(x: 0, y: offset)
        context.drawPDFPage(page)
        context.restoreGState()
        let y = offset - guideMM * pt / 2
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setLineWidth(pt / 4)
        context.setLineDash(phase: 0, lengths: [2 * pt, pt])
        context.move(to: CGPoint(x: 2 * pt, y: y))
        context.addLine(to: CGPoint(x: width - 2 * pt, y: y))
        context.strokePath()
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.endPDFPage()
        context.closePDF()
        return (data as Data, result)
    }
}
