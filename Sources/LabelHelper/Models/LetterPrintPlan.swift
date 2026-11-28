import AppKit
import LabelCore

struct LetterReviewSettings: Equatable {
    let recipient: RecipientAddress
    let sender: SenderAddress
    let stamp: PostageStamp?
    let needsStamp: Bool
    let combined: CombinedLabelSettings
    let stampPlacement: PostageStampPlacement
    let design: AddressLabelDesign
    let addressFormat: LabelFormat
    let stampFormat: LabelFormat
    let continuous: Bool
    let additionalFeedMM: Double
    let packingNote: String
}

struct LetterPrintPlan {
    struct Page {
        let title: String
        let pdf: Data
        let format: LabelFormat
        let image: NSImage
    }

    let settings: LetterReviewSettings
    let pages: [Page]

    static func make(for settings: LetterReviewSettings) throws -> Self {
        func page(_ title: String, _ source: Data, _ sourceFormat: LabelFormat, includesAddress: Bool) throws -> Page {
            let (pdf, format) = settings.continuous && includesAddress && !settings.packingNote.isEmpty
                ? try PackingSlipWriter.append(settings.packingNote, to: source, format: sourceFormat,
                                               additionalFeedMM: settings.additionalFeedMM)
                : (source, sourceFormat)
            let content = try LabelRenderer.render(pdfData: pdf, format: format)
            let raster = settings.continuous && !format.includesCutGuide
                ? ContinuousLabelCutGuide.applying(to: content, additionalFeedMM: settings.additionalFeedMM)
                : content
            guard let image = LabelPreviewRenderer.image(from: raster) else { throw LabelRendererError.cannotCreateBitmap }
            return Page(title: title, pdf: pdf, format: format, image: image)
        }

        if let stamp = settings.stamp, settings.combined.isEnabled {
            let label = try EtsyAddressLabelWriter.makeCombinedPDF(
                recipient: settings.recipient, sender: settings.sender, stamp: stamp, stampSize: stamp.sourceRect.size,
                format: settings.continuous ? .shipping100x150 : settings.addressFormat,
                continuous: settings.continuous, settings: settings.combined,
                placement: settings.stampPlacement, design: settings.design
            )
            return try Self(settings: settings, pages: [page("Adresse und Briefmarke", label.data, label.format, includesAddress: true)])
        }

        let address = try EtsyAddressLabelWriter.makePDFData(recipient: settings.recipient, sender: settings.sender,
                                                             format: settings.addressFormat, design: settings.design)
        var pages = try [page("Adresse", address, settings.addressFormat, includesAddress: true)]
        if let stamp = settings.stamp {
            let sheet = try PostagePDFService.singleStampSheet(stamp, format: settings.stampFormat,
                fitHeightToContent: settings.continuous, placement: settings.stampPlacement)
            pages.append(try page("Briefmarke", sheet.data, sheet.format, includesAddress: false))
        }
        return Self(settings: settings, pages: pages)
    }
}
