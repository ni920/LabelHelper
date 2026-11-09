import Foundation

/// A parcel label, imported label or address-only letter in the label history.
/// Letters with a stamp keep their own record in `LetterShipmentFlow`.
public struct LabelHistoryRecord: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case parcel, addressLetter, imported

        public var title: String {
            switch self {
            case .parcel: "Paketlabel"
            case .addressLetter: "Brief (nur Adresse)"
            case .imported: "Etikett"
            }
        }
    }

    private static let addressJobPrefix = "Brief · "

    /// The print job's ID. The record outlives that job.
    public let id: UUID
    public let kind: Kind
    public let createdAt: Date
    public let sourceFingerprint: String
    public let fileTitle: String
    public let labelFormat: LabelFormat
    public let recipientName: String?
    public let addressLines: [String]
    public let trackingNumber: String?
    public let product: String?
    public let orderID: String?
    public let cartNumber: String?
    public var status: PrintJob.Status
    public var errorMessage: String?

    /// Returns nil for jobs the history shows elsewhere: letter flows and stamp sheets.
    public init?(job: PrintJob, parcelInfo: ParcelLabelInfo?, recipient: RecipientAddress? = nil, orderID: String? = nil) {
        guard job.letterFlowID == nil, job.postageStampIDs == nil else { return nil }
        let isAddressLetter = job.sourceFingerprint.hasPrefix("manual-address:")
        let format = job.resolvedLabelFormat
        id = job.id
        kind = isAddressLetter ? .addressLetter : (parcelInfo != nil || format == .shipping100x150) ? .parcel : .imported
        createdAt = job.createdAt
        sourceFingerprint = job.sourceFingerprint
        fileTitle = job.title
        labelFormat = format
        if isAddressLetter {
            recipientName = recipient?.name
                ?? (job.title.hasPrefix(Self.addressJobPrefix) ? String(job.title.dropFirst(Self.addressJobPrefix.count)) : nil)
        } else {
            recipientName = parcelInfo?.recipientName
        }
        addressLines = recipient?.lines ?? parcelInfo?.addressLines ?? []
        trackingNumber = parcelInfo?.trackingNumber
        product = parcelInfo?.product
        self.orderID = orderID
        cartNumber = parcelInfo?.cartNumber
        status = job.status
        errorMessage = job.errorMessage
    }

    public var title: String { recipientName ?? fileTitle }
}
