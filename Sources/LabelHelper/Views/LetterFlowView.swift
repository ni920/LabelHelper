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
    @State private var copied = false
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
                Text(flow.isCombined
                     ? "Adresse + \(flow.stamp.amount) € Briefmarke auf einem Etikett\nEtikett: \(appStore.printedLabelFormat(flow.stampJob.resolvedLabelFormat).sizeDescription)"
                     : "Adresse + \(flow.stamp.amount) € Briefmarke\nAdresse: \(appStore.printedLabelFormat(flow.addressJob.resolvedLabelFormat).sizeDescription)\nBriefmarke: \(appStore.printedLabelFormat(flow.stampJob.resolvedLabelFormat).sizeDescription)")
                    .font(.callout).foregroundStyle(.secondary)
                if appStore.labelStockMode == .continuous100 {
                    Text("Mit Schnittlinie unter jedem Etikett · 2 mm Zugabe").font(.callout)
                }
                Divider()
                HStack {
                    if active { ProgressView().controlSize(.small) }
                    Text(flow.statusTitle).font(.headline)
                }
                if let error = flow.errorMessage ?? controller.message ?? store.storageError {
                    Text(error).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if let previewError { Text(previewError).font(.callout).foregroundStyle(.red) }
                Text("Sendungsnummer").font(.headline)
                PostageTrackingNumberView(stamp: flow.stamp, showTitle: false)
                if flow.stage == .ready || flow.stage == .addressPrinted {
                    if flow.needsPostagePrint {
                        Toggle("Nach Abschluss automatisch kopieren", isOn: $autoCopy).font(.callout)
                    }
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
                    Text(flow.isCombined ? "Das Etikett ist bestätigt. Die Sendungsnummer ist diesem Brief zugeordnet." : "Beide Etiketten sind bestätigt. Die Sendungsnummer ist diesem Brief zugeordnet.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button(copied ? "Sendungsnummer kopiert" : "Sendungsnummer kopieren") {
                        copied = copyTrackingNumbers([flow.stamp])
                    }
                    Divider()
                    if !flow.isCombined {
                        Picker("Erneut drucken", selection: $reprintSelection) {
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
                }
               }.frame(maxWidth: .infinity, alignment: .leading)
              }
                actions
                if flow.stage == .completed {
                    Button("Zurück zum Anfang", action: appStore.returnToStart)
                        .buttonStyle(.borderedProminent).disabled(active)
                }
                Button(flow.stage == .completed ? "Fertig" : "Schließen", role: .cancel) { appStore.letterFlowPreview = nil }
                    .disabled(active)
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
        .onChange(of: reprintSelection) { _, selection in step = selection == .stamp ? 1 : 0 }
        .onChange(of: flow.stage) { _, stage in
            if stage == .printingAddress { step = 0 }
            if stage == .printingStamp { step = 1 }
            if stage == .completed {
                reprintSelection = flow.isCombined ? .stamp : .address
                step = 0
                if autoCopy && flow.needsPostagePrint { copied = copyTrackingNumbers([flow.stamp]) }
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
        case .completed:
            Button(reprintTitle) {
                if reprintSelection == .address {
                    controller.reprint(flow.id, selection: .address)
                } else {
                    confirmReprint = true
                }
            }.disabled(!canReprint)
        case .printingAddress, .printingStamp:
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
