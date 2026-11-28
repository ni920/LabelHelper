import LabelCore
import SwiftUI

struct EtsyImportView: View {
    @ObservedObject var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<String>

    init(appStore: AppStore) {
        self.appStore = appStore
        _selectedIDs = State(initialValue: Set(appStore.pendingEtsyOrders.prefix(1).map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Etsy-Bestellungen")
                    .font(.title2.weight(.semibold))
                HStack {
                    Text("Mit ⌘-Klick wählst du mehrere Bestellungen aus.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Alle auswählen") { selectedIDs = Set(appStore.pendingEtsyOrders.map(\.id)) }
                        .buttonStyle(.link)
                }
            }

            List(appStore.pendingEtsyOrders, selection: $selectedIDs) { order in
                VStack(alignment: .leading, spacing: 3) {
                    Text(order.recipientName)
                        .fontWeight(.medium)
                    Text("#\(order.id) · \(order.street1), \(order.postalCode) \(order.city)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(order.id)
                .padding(.vertical, 4)
            }
            .frame(minHeight: 260)

            HStack {
                Button("Abbrechen") {
                    appStore.showEtsyImportReview = false
                    dismiss()
                }
                Spacer()
                Button("Zum Sammeldruck (\(selectedIDs.count))") {
                    appStore.collectCSVOrders(appStore.pendingEtsyOrders.filter { selectedIDs.contains($0.id) })
                }
                .disabled(selectedIDs.isEmpty || appStore.shippingBusy || appStore.orderBatch.storageError != nil)
                if selectedIDs.count == 1 {
                    Button("Adresse übernehmen") {
                        if let order = appStore.pendingEtsyOrders.first(where: { selectedIDs.contains($0.id) }) {
                            appStore.applyEtsyOrder(order)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appStore.shippingBusy)
                }
            }
        }
        .padding(24)
        .frame(width: 640, height: 460)
    }
}
