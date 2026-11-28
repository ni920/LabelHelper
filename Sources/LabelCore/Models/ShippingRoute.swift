import Foundation

/// The selected shipment and, for a parcel, the exact prepared label.
public struct ShippingRoute: Equatable, Codable {
    public enum Task: String, CaseIterable, Identifiable, Codable {
        case letter, parcel, postage

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .letter: "Brief"
            case .parcel: "Paket"
            case .postage: "Briefmarken"
            }
        }

        public var icon: String {
            switch self {
            case .letter: "envelope"
            case .parcel: "shippingbox"
            case .postage: "rectangle.stack"
            }
        }
    }

    public private(set) var task: Task?
    public private(set) var parcelJobID: UUID?

    public init() {}

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        task = try values.decodeIfPresent(Task.self, forKey: .task)
        parcelJobID = try values.decodeIfPresent(UUID.self, forKey: .parcelJobID)
        // Versions through 0.8.8 also saved a step index. The shipment and job
        // are sufficient to restore those drafts in the new workspace.
        if parcelJobID != nil && task != .parcel {
            throw DecodingError.dataCorruptedError(forKey: .parcelJobID, in: values,
                                                   debugDescription: "Paketlabel ohne Paketentwurf")
        }
    }

    public mutating func choose(_ task: Task) {
        self.task = task
        parcelJobID = nil
    }

    public mutating func receiveParcel(_ id: UUID) {
        task = .parcel
        parcelJobID = id
    }

    public mutating func reset() {
        self = ShippingRoute()
    }
}
