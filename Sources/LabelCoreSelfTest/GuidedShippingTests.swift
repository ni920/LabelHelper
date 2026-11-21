import Foundation
import LabelCore

func runGuidedShippingTests() throws {
    func check(_ value: Bool, _ message: String) throws {
        if !value { throw NSError(domain: "GuidedShipping", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    var journey = GuidedShippingJourney()
    journey.advance(); journey.back()
    try check(journey.task == nil && journey.step == nil, "Home navigation must remain bounded")
    journey.choose(.letter)
    try check(journey.step == .recipient && journey.nextStep == .review, "Letter must go directly from address to print review")
    journey.advance()
    journey.receivePostage()
    try check(journey.task == .letter && journey.step == .review && journey.nextStep == nil,
              "Importing stamps for a letter must preserve its final review")
    journey.goBack(to: .format)
    try check(journey.step == .review, "Letter must not enter postage layout")
    journey.back()
    try check(journey.step == .recipient, "Back from review must return to recipient")
    let id = UUID()
    journey.receiveParcel(id)
    try check(journey.task == .parcel && journey.step == .review && journey.parcelJobID == id, "Imported parcel must review the actual job")
    journey.back()
    try check(journey.step == .parcelFile && journey.parcelJobID == id, "Replacing a parcel must retain the previous selection until imported")
    let restoredParcel = try JSONDecoder().decode(GuidedShippingJourney.self, from: JSONEncoder().encode(journey))
    try check(restoredParcel == journey, "Resuming a saved parcel must retain the exact print job")
    journey.receivePostage()
    try check(journey.task == .postage && journey.step == .postageSelection && journey.parcelJobID == nil, "Postage import must discard unrelated parcel navigation")
    journey.choose(.letter)
    try check(journey.index == 0 && journey.parcelJobID == nil, "Task switch must reset step and parcel reference")
    journey.back()
    try check(journey.task == nil, "Back from first step must return home")
    do {
        _ = try JSONDecoder().decode(GuidedShippingJourney.self, from: Data(#"{"task":"letter","index":8}"#.utf8))
        try check(false, "Invalid saved steps must be rejected")
    } catch DecodingError.dataCorrupted { }

}
