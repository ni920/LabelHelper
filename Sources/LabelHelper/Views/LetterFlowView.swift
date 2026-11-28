import AppKit
import LabelCore
import SwiftUI

struct LetterFlowView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject var store: LetterFlowStore
    @ObservedObject var controller: LetterFlowController
    @ObservedObject var bluetooth: BluetoothPrinterService
    let initialFlow: LetterShipmentFlow
    @State private var step = 0
    @State private var image: NSImage?
    @State private var previewError: String?
    @State private var confirmStampRetry = false
    @State private var reprintSelection: LetterShipmentFlow.ReprintSelection = .address
    @State private var confirmReprint = false
    @AppStorage("letterFlowAutoCopyTracking") private var autoCopy = false

    private var flow: LetterShipmentFlow { store.flow(initialFlow.id) ?? initialFlow }
    private var active: Bool { controller.activeFlowID == flow.id }
    private var canStart: Bool {
        bluetooth.connectionState.isReady && appStore.canPrintSelectedMaterialOverBluetooth &&
        !appStore.printInProgress && !appStore.printingPostageBatch && controller.activeFlowID == nil && previewError == nil &&
        (!flow.needsPostagePrint || appStore.postage.canPrint([flow.stamp.id], reservationID: flow.id) ||
         (flow.reprintSelection != nil && appStore.postage.canReprint(flow.stamp.id, for: flow.id)))
    }
    private var canReprint: Bool {
        bluetooth.connectionState.isReady && appStore.canPrintSelectedMaterialOverBluetooth &&
        !appStore.printInProgress && !appStore.printingPostageBatch && previewError == nil &&
        controller.reprintUnavailableReason(flow.id, selection: reprintSelection) == nil
    }

    var body: some View {
        HStack(spacing: 24) {
            VStack(spacing: 12) {
                if !flow.isCombined {
                    Picker("Vorschau", selection: $step) {
                        Text("1 · Adresse").tag(0)
                        Text("2 · Briefmarke").tag(1)
                    }.pickerStyle(.segmented)
                }
                LabelPaperCanvas(image: image, placeholder: previewError)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 14) {
              ScrollView {
               VStack(alignment: .leading, spacing: 14) {
                Text("Briefversand").font(.title2.bold())
                Text(flow.recipientName).font(.headline)
                if let order = flow.orderID { Text("Etsy #\(order)").foregroundStyle(.secondary) }
                LabeledContent("Porto", value: "\(flow.stamp.amount) €")
                Text(flow.isCombined ? "Ein gemeinsames Etikett" : "Zwei Etiketten")
                    .font(.callout).foregroundStyle(.secondary)
                Divider()
                HStack {
                    if active { ProgressView().controlSize(.small) }
                    if flow.stage != .completed { Text(flow.statusTitle).font(.headline) }
                }
                if let error = flow.errorMessage ?? controller.message ?? store.storageError {
                    Text(error).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if let previewError { Text(previewError).font(.callout).foregroundStyle(.red) }
                if flow.stage == .ready || flow.stage == .addressPrinted {
                    PostageMaterialRequirement(appStore: appStore, bluetooth: bluetooth)
                    if !bluetooth.connectionState.isReady {
                        PrinterConnectionView(appStore: appStore, bluetooth: bluetooth)
                    }
                    if flow.needsPostagePrint && !appStore.postage.canPrint([flow.stamp.id], reservationID: flow.id) &&
                        !(flow.reprintSelection != nil && appStore.postage.canReprint(flow.stamp.id, for: flow.id)) {
                        Text("Diese Briefmarke ist nicht mehr verfügbar. Bitte im Briefformular eine andere Marke auswählen und einen neuen Ablauf vorbereiten.")
                            .font(.callout).foregroundStyle(.orange)
                    }
                }
                if flow.stage == .completed {
                    ShipmentCompletionView(appStore: appStore, status: "Brief gedruckt",
                                           trackingNumbers: [flow.stamp.trackingNumber].compactMap { $0 })
                    DisclosureGroup("Nachdruck") {
                        reprintOptions.padding(.top, 8)
                    }
                }
               }.frame(maxWidth: .infinity, alignment: .leading)
              }
                actions
                if !active {
                    HStack {
                        Button("Schließen", role: .cancel) { appStore.letterFlowPreview = nil }
                        Spacer()
                        ShipmentImportMenu(appStore: appStore)
                    }
                }
            }.frame(width: 290)
        }
        .padding(24).frame(minWidth: 840, minHeight: 610)
        .interactiveDismissDisabled(active)
        .onAppear {
            if [.addressPrinted, .printingStamp, .stampCheck].contains(flow.stage) { step = 1 }
            if flow.isCombined { reprintSelection = .stamp }
            render()
        }
        .onChange(of: step) { _, _ in render() }
        .onChange(of: appStore.labelStockMode) { _, _ in render() }
        .onChange(of: appStore.continuousExtraFeedMM) { _, _ in render() }
        .onChange(of: reprintSelection) { _, selection in step = selection == .stamp ? 1 : 0 }
        .onChange(of: flow.stage) { _, stage in
            if stage == .printingAddress { step = 0 }
            if stage == .printingStamp { step = 1 }
            if stage == .completed {
                reprintSelection = flow.isCombined ? .stamp : .address
                step = 0
                if autoCopy && flow.needsPostagePrint { _ = copyTrackingNumbers([flow.stamp]) }
            }
        }
        .alert("Nur die Briefmarke erneut drucken?", isPresented: $confirmStampRetry) {
            Button("Abbrechen", role: .cancel) {}
            Button("Briefmarke erneut drucken") { controller.resolveStamp(flow.id, alreadyPrinted: false) }
        } message: { Text("Bitte nur fortsetzen, wenn der vorherige Briefmarkenausdruck unbrauchbar ist. Die Adresse wird dabei nicht erneut gedruckt.") }
        .alert("Briefmarke erneut drucken?", isPresented: $confirmReprint) {
            Button("Abbrechen", role: .cancel) {}
            Button(reprintTitle) { controller.reprint(flow.id, selection: reprintSelection) }
        } message: {
            Text("Nur fortsetzen, wenn der alte Briefmarkenausdruck unbrauchbar ist und vernichtet wurde. Die Marke darf nur für diesen einen Brief verwendet werden, nicht für eine weitere Sendung.")
        }
    }

    private var reprintTitle: String { flow.isCombined ? "Etikett erneut drucken" : reprintSelection.actionTitle }

    private var startTitle: String {
        if flow.isCombined { return flow.reprintSelection == nil ? "Etikett drucken" : "Etikett erneut drucken" }
        return flow.stage == .ready ? (flow.reprintSelection?.actionTitle ?? "Adresse + Briefmarke drucken") : "Nur Briefmarke drucken"
    }

    private var reprintOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !flow.isCombined {
                Picker("Auswahl", selection: $reprintSelection) {
                    ForEach(LetterShipmentFlow.ReprintSelection.allCases) { selection in
                        Text(selection.title).tag(selection)
                    }
                }
            }
            if let reason = controller.reprintUnavailableReason(flow.id, selection: reprintSelection) {
                Text(reason).font(.callout).foregroundStyle(.secondary)
            }
            PostageMaterialRequirement(appStore: appStore, bluetooth: bluetooth)
            if !bluetooth.connectionState.isReady {
                PrinterConnectionView(appStore: appStore, bluetooth: bluetooth)
            }
            Button(reprintTitle) {
                if reprintSelection == .address {
                    controller.reprint(flow.id, selection: .address)
                } else {
                    confirmReprint = true
                }
            }
            .disabled(!canReprint)
        }
    }

    @ViewBuilder private var actions: some View {
        switch flow.stage {
        case .ready, .addressPrinted:
            Button(startTitle) { controller.start(flow.id) }
                .buttonStyle(.borderedProminent).disabled(!canStart)
        case .addressCheck:
            Text("Ist die Adresse bereits korrekt gedruckt?").font(.callout)
            Button(flow.needsPostagePrint ? "Ja · nur Briefmarke drucken" : "Ja · Nachdruck abschließen") { controller.resolveAddress(flow.id, alreadyPrinted: true) }
                .disabled(controller.activeFlowID != nil)
            Button("Nein · Adresse erneut drucken") { controller.resolveAddress(flow.id, alreadyPrinted: false) }
                .disabled(controller.activeFlowID != nil)
        case .stampCheck:
            Text("Bitte den letzten Briefmarkenausdruck prüfen.").font(.callout)
            Button("Marke ist korrekt gedruckt") { controller.resolveStamp(flow.id, alreadyPrinted: true) }
                .disabled(controller.activeFlowID != nil)
            Button("Marke ist unbrauchbar …") { confirmStampRetry = true }.disabled(controller.activeFlowID != nil)
        case .completed, .printingAddress, .printingStamp:
            EmptyView()
        }
    }

    private func render() {
        image = nil; previewError = nil
        let job = step == 0 ? flow.addressJob : flow.stampJob
        do { image = LabelPreviewRenderer.image(from: try appStore.renderLabel(job)) }
        catch { previewError = error.localizedDescription }
    }
}
