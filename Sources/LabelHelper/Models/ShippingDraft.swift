import Foundation
import LabelCore

struct ShippingDraft: Codable, Equatable {
    let journey: ShippingRoute
    let recipient: RecipientAddress
    let browserOrder: BrowserOrderPayload?
    let csvOrderID: String?
    let withPostage: Bool
    let stampID: String
    let postageIDs: Set<String>
    let letterFlowID: UUID?
    let addressJobID: UUID?
}
