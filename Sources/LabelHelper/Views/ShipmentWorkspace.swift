import LabelCore
import SwiftUI

struct ShipmentWorkspace: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject var jobs: PrintJobStore
    let route: ShippingRoute

    private var parcel: PrintJob? { jobs.jobs.first { $0.id == route.parcelJobID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch route.task {
                case .letter:
                    LetterReviewView(appStore: appStore, postage: appStore.postage, jobs: jobs, bluetooth: appStore.bluetooth)
                        .id(appStore.shippingImportSequence)
                case .parcel:
                    parcelContent
                case .postage, nil:
                    EmptyView()
                }
                if let message = appStore.lastMessage {
                    Label(message, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle(route.task?.title ?? "Versenden")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: appStore.showShippingHome) {
                    Label("Versandübersicht", systemImage: "chevron.left")
                }
                .disabled(appStore.shippingBusy)
                .help("Zur Versandübersicht")
            }
        }
    }

    @ViewBuilder private var parcelContent: some View {
        if let error = appStore.parcelImportError {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
        if let parcel {
            PrintPreviewView(appStore: appStore, job: parcel, embedded: true)
                .id(parcel.id)
        } else {
            ContentUnavailableView {
                Label("DHL-Paketlabel", systemImage: "shippingbox")
            } description: {
                Text("Öffne die PDF deiner gekauften Versandmarke.")
            } actions: {
                Button("PDF öffnen …", action: appStore.chooseDHLLabelImport)
                    .buttonStyle(.borderedProminent)
            }
        }
        if parcel != nil {
            Button("Andere PDF öffnen …", action: appStore.chooseDHLLabelImport)
                .disabled(appStore.shippingBusy)
        }
    }
}
