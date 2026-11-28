import LabelCore
import SwiftUI

struct ShippingTaskPicker: View {
    var disabled: Bool
    var choose: (ShippingRoute.Task) -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Versenden", systemImage: "printer")
        } description: {
            Text("Importiere eine Etsy-Bestellung aus dem Browser oder öffne dein Versandlabel.")
        } actions: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { actions }
                VStack(spacing: 10) { actions }
            }
            .controlSize(.large)
            .disabled(disabled)
        }
    }

    @ViewBuilder private var actions: some View {
        Button { choose(.parcel) } label: { Label("DHL-PDF öffnen …", systemImage: "shippingbox") }
            .buttonStyle(.borderedProminent)
        Button { choose(.letter) } label: { Label("Brief vorbereiten", systemImage: "envelope") }
    }
}
