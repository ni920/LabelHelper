import LabelCore
import SwiftUI

private enum SidebarSelection: String, CaseIterable, Identifiable {
    case printer
    case labels
    case postage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .printer: "Versenden"
        case .labels: "Label-Verlauf"
        case .postage: "Briefmarken"
        }
    }

    var icon: String {
        switch self {
        case .printer: "printer.fill"
        case .labels: "clock.arrow.circlepath"
        case .postage: "rectangle.stack"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var journey = ShippingRoute()
    @State private var presentsDraft = false
    @State private var hasLoadedDraft = false
    @State private var replacementTask: ShippingRoute.Task?
    @State private var selection: SidebarSelection? = .printer

    var body: some View {
        NavigationSplitView {
            List(SidebarSelection.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationTitle("Label Helper")
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 260)
        } detail: {
            switch selection ?? .printer {
            case .printer:
                if presentsDraft, journey.task != nil {
                    ShipmentWorkspace(appStore: appStore, jobs: appStore.jobs, route: journey)
                        .id(journey.task)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if let task = journey.task, task != .postage {
                                GroupBox("Aktueller Entwurf") {
                                    HStack {
                                        Label(appStore.recipientName.isEmpty ? task.title : appStore.recipientName,
                                              systemImage: task.icon)
                                        Spacer()
                                        Button("Öffnen") { presentsDraft = true }
                                    }.padding(8)
                                }
                            }
                            ShippingTaskPicker(disabled: appStore.shippingBusy, choose: selectNewTask)
                            Button {
                                appStore.showOrderBatch = true
                            } label: {
                                let count = appStore.orderBatch.orders.count
                                Label(count == 0 ? "Sammeldruck …" : "Sammeldruck (\(count)) …", systemImage: "square.stack")
                            }
                            .frame(maxWidth: .infinity)
                            .disabled(appStore.shippingBusy)
                            if let message = appStore.lastMessage {
                                Label(message, systemImage: "info.circle").font(.callout)
                            }
                        }
                        .padding(32)
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                    }
                    .navigationTitle("Versenden")
                }
            case .labels:
                LabelHistoryView(appStore: appStore, letters: appStore.letterFlows, labels: appStore.labelHistory, jobs: appStore.jobs)
            case .postage:
                PostageBundleView(appStore: appStore, store: appStore.postage)
            }
        }
        .fileImporter(
            isPresented: $appStore.showImporter,
            allowedContentTypes: appStore.fileImport?.contentTypes ?? [.pdf],
            allowsMultipleSelection: appStore.fileImport == .label,
            onCompletion: { appStore.finishFileImport($0) },
            onCancellation: { appStore.finishFileImport() }
        )
        .sheet(isPresented: $appStore.showOrderBatch, onDismiss: appStore.importSheetDismissed) {
            OrderBatchView(appStore: appStore, batch: appStore.orderBatch, postage: appStore.postage, bluetooth: appStore.bluetooth)
        }
        .sheet(isPresented: $appStore.showPrinterConnection) {
            VStack(alignment: .trailing, spacing: 0) {
                PrinterConnectionControls(appStore: appStore, bluetooth: appStore.bluetooth)
                Button("Fertig") { appStore.showPrinterConnection = false }
                    .keyboardShortcut(.defaultAction)
                    .padding([.trailing, .bottom], 20)
            }
        }
        .sheet(isPresented: $appStore.showEtsyImportReview, onDismiss: appStore.importSheetDismissed) {
            EtsyImportView(appStore: appStore)
        }
        .sheet(isPresented: $appStore.showBrowserOrderReview, onDismiss: appStore.importSheetDismissed) {
            BrowserOrderReviewView(appStore: appStore)
        }
        .sheet(item: $appStore.previewJob, onDismiss: appStore.importSheetDismissed) { job in
            PrintPreviewView(appStore: appStore, job: job)
        }
        .sheet(item: $appStore.postagePreview, onDismiss: appStore.importSheetDismissed) { batch in
            PostagePrintPreviewView(appStore: appStore, bluetooth: appStore.bluetooth, batch: batch)
        }
        .sheet(item: $appStore.letterFlowPreview, onDismiss: appStore.importSheetDismissed) { flow in
            LetterFlowView(appStore: appStore, store: appStore.letterFlows, controller: appStore.letterFlowController,
                           bluetooth: appStore.bluetooth, initialFlow: flow)
        }
        .alert("Export fehlgeschlagen", isPresented: Binding(
            get: { appStore.historyExportError != nil },
            set: { if !$0 { appStore.historyExportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appStore.historyExportError ?? "")
        }
        .alert("Etsy-Import fehlgeschlagen", isPresented: $appStore.showEtsyImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appStore.lastMessage ?? "Die CSV-Datei konnte nicht importiert werden.")
        }
        .confirmationDialog("Aktuellen Entwurf ersetzen?", isPresented: Binding(
            get: { replacementTask != nil },
            set: { if !$0 { replacementTask = nil } }
        ), titleVisibility: .visible, presenting: replacementTask) { task in
            Button("Neuen Versand beginnen", role: .destructive) { beginNewTask(task) }
            Button("Entwurf behalten", role: .cancel) {}
        } message: { _ in
            Text("Die Eingaben dieses Entwurfs werden geleert. Bereits vorbereitete Druckaufträge findest du im Label-Verlauf.")
        }
        .onAppear {
            guard !hasLoadedDraft else { return }
            if let saved = appStore.loadShippingDraft() {
                journey = saved
                if saved.task == .postage { selection = .postage }
            }
            hasLoadedDraft = true
        }
        .onChange(of: appStore.shippingDraft(for: journey)) { _, draft in
            if hasLoadedDraft { appStore.saveShippingDraft(draft) }
        }
        .onChange(of: appStore.printInProgress || appStore.printingPostageBatch) { _, busy in
            if !busy { appStore.presentNextImport() }
        }
        .onReceive(appStore.letterFlowController.$activeFlowID.receive(on: DispatchQueue.main)) { activeFlow in
            if activeFlow == nil { appStore.presentNextImport() }
        }
        .onChange(of: appStore.showEtsyImportError) { _, presented in
            if !presented { appStore.presentNextImport() }
        }
        .onChange(of: appStore.parcelImportError) { _, error in
            if let error, !(selection == .printer && presentsDraft && journey.task == .parcel) {
                appStore.lastMessage = error
            }
        }
        .onChange(of: appStore.shippingImportSequence) { _, _ in
            selection = .printer
            journey.choose(appStore.selectedShipmentKind == .letter ? .letter : .parcel)
            presentsDraft = true
        }
        .onChange(of: appStore.labelImportSequence) { _, _ in
            guard let id = appStore.lastImportedLabelJobID else { return }
            selection = .printer
            journey.receiveParcel(id)
            presentsDraft = true
        }
        .onChange(of: appStore.postageImportSequence) { _, _ in
            guard appStore.postageImportSucceeded else { return }
            if selection == .printer, presentsDraft, journey.task == .letter { return }
            selection = .postage
        }
        .onChange(of: appStore.draftHomeSequence) { _, _ in
            selection = .printer
            presentsDraft = false
        }
        .onChange(of: appStore.homeRequestSequence) { _, _ in
            selection = .printer
            presentsDraft = false
            journey.reset()
        }
        .onChange(of: appStore.historyRequestSequence) { _, _ in
            selection = .labels
            presentsDraft = false
            journey.reset()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if selection != .labels {
                    ShipmentImportMenu(appStore: appStore)
                    PrinterConnectionView(appStore: appStore, bluetooth: appStore.bluetooth)
                }
            }
        }
    }

    private func selectNewTask(_ task: ShippingRoute.Task) {
        if journey.task != nil && journey.task != .postage { replacementTask = task }
        else { beginNewTask(task) }
    }

    private func beginNewTask(_ task: ShippingRoute.Task) {
        guard !appStore.shippingBusy else { return }
        replacementTask = nil
        appStore.resetShippingDraft()
        appStore.selectedShipmentKind = task == .parcel ? .parcel : .letter
        journey.choose(task)
        presentsDraft = true
        if task == .parcel { appStore.chooseDHLLabelImport() }
    }
}

struct ShipmentImportMenu: View {
    let appStore: AppStore

    var body: some View {
        Menu("Importieren") {
            Button("DHL-PDF öffnen …", action: appStore.chooseDHLLabelImport)
            Button("PDF oder Bild öffnen …", action: appStore.requestLabelImport)
            Button("Etsy-CSV öffnen …") { appStore.requestFileImport(.etsyCSV) }
            Button("Briefmarken-PDF öffnen …") { appStore.requestFileImport(.postage) }
        }
        .help("Etiketten, Etsy-Adressen und Briefmarken importieren")
    }
}
