import Foundation
import LabelCore

func runShippingRouteTests() throws {
    let decoder = JSONDecoder()
    for step in 0...1 {
        let letter = try decoder.decode(ShippingRoute.self, from: Data(#"{"task":"letter","index":\#(step)}"#.utf8))
        try require(letter.task == .letter && letter.parcelJobID == nil, "A saved letter must survive either old step")
    }
    for step in 0...3 {
        let postage = try decoder.decode(ShippingRoute.self, from: Data(#"{"task":"postage","index":\#(step)}"#.utf8))
        try require(postage.task == .postage, "A saved stamp selection must survive each old step")
    }
    let id = UUID()
    var route = try decoder.decode(ShippingRoute.self, from: Data(#"{"task":"parcel","index":1,"parcelJobID":"\#(id)"}"#.utf8))
    try require(route.task == .parcel && route.parcelJobID == id, "A saved parcel must retain its exact print job")
    let roundTrip = try decoder.decode(ShippingRoute.self, from: JSONEncoder().encode(route))
    try require(roundTrip == route, "New route must round trip")
    route.choose(.letter)
    try require(route.task == .letter && route.parcelJobID == nil, "A new letter must not reuse the parcel")
    route.receiveParcel(id)
    route.reset()
    try require(route.task == nil && route.parcelJobID == nil, "Starting over must clear the route")
}
