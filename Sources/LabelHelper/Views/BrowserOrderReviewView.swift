import LabelCore
import SwiftUI

struct BrowserOrderReviewView: View {
    @ObservedObject var appStore: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "cart.badge.checkmark")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Etsy-Bestellung empfangen")
                        .font(.title2.weight(.semibold))
                    if let order {
                        Text("Bestellung #\(order.orderID)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let order {
                GroupBox("Empfänger") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(order.recipient.lines, id: \.self) { line in
                            Text(line)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                if !appStore.recipientName.isEmpty && appStore.draftLetterFlowID == nil && appStore.draftAddressJobID == nil {
                    Text("Die Bestellung ersetzt den aktuellen Versandentwurf.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("Keine Bestellung", systemImage: "cart")
            }

            HStack {
                Button("Abbrechen", role: .cancel) {
                    appStore.dismissIncomingBrowserOrder()
                }
                Spacer()
                Button("Zum Sammeldruck") { appStore.collectBrowserOrder() }
                    .disabled(order == nil || appStore.shippingBusy || appStore.orderBatch.storageError != nil)
                Button("Paketlabel öffnen …") { appStore.acceptIncomingBrowserOrder(as: .parcel) }
                    .disabled(order == nil || appStore.shippingBusy)
                Button("Brief vorbereiten") { appStore.acceptIncomingBrowserOrder(as: .letter) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(order == nil || appStore.shippingBusy)
            }
        }
        .padding(24)
        .frame(minWidth: 660)
    }

    private var order: BrowserOrderPayload? {
        appStore.incomingBrowserOrder
    }
}
