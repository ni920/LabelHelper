import LabelCore
import SwiftUI
import UniformTypeIdentifiers

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
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appStore: AppStore
    @State private var journey = GuidedShippingJourney()
    @State private var presentsDraft = false
    @State private var hasLoadedDraft = false
    @State private var replacementTask: GuidedShippingJourney.Task?
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
                if presentsDraft, let task = journey.task {
                    GuidedShippingView(appStore: appStore, postage: appStore.postage, jobs: appStore.jobs,
                                       controller: appStore.letterFlowController, journey: $journey)
                        .id(task)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if let task = journey.task {
                                GroupBox("Aktueller Entwurf") {
                                    HStack {
                                        Label(appStore.recipientName.isEmpty ? task.title : appStore.recipientName,
                                              systemImage: task.icon)
                                        Spacer()
                                        Button("Entwurf fortsetzen") { presentsDraft = true }
                                            .buttonStyle(.borderedProminent)
                                    }.padding(8)
                                }
                            }
                            ShippingTaskPicker(disabled: appStore.shippingBusy, choose: selectNewTask)
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
            allowedContentTypes: [.pdf, .png, .jpeg],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): appStore.importFiles(urls)
            case .failure(let error): appStore.lastMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $appStore.showDHLImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): appStore.importDHLLabel(url)
            case .failure(let error): appStore.reportDHLImportError(error)
            }
        }
        .fileImporter(
            isPresented: $appStore.showPostageImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { appStore.importPostageBundle(url) }
            case .failure(let error): appStore.lastMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $appStore.showEtsyImporter,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { appStore.loadEtsyCSV(url) }
            case .failure(let error): appStore.lastMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $appStore.showEtsyImportReview) {
            EtsyImportView(appStore: appStore)
        }
        .sheet(isPresented: $appStore.showBrowserOrderReview) {
            BrowserOrderReviewView(appStore: appStore)
        }
        .sheet(item: $appStore.previewJob) { job in
            PrintPreviewView(appStore: appStore, job: job)
        }
        .sheet(item: $appStore.postagePreview) { batch in
            PostagePrintPreviewView(appStore: appStore, bluetooth: appStore.bluetooth, batch: batch)
        }
        .sheet(item: $appStore.letterFlowPreview) { flow in
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
            if let saved = appStore.loadShippingDraft() { journey = saved }
            hasLoadedDraft = true
        }
        .onChange(of: appStore.shippingDraft(for: journey)) { _, draft in
            if hasLoadedDraft { appStore.saveShippingDraft(draft) }
        }
        .onChange(of: appStore.guidedMode) { _, guided in
            if guided, presentsDraft, journey.task == .letter, journey.step == .recipient,
               appStore.recipientAddress.isComplete, appStore.senderAddress.isComplete {
                journey.advance()
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
            if selection == .printer, presentsDraft, journey.task == .postage {
                journey.receivePostage()
            } else {
                selection = .postage
            }
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
            ToolbarItem(placement: .principal) {
                if selection == .printer {
                    Picker("Bedienmodus", selection: $appStore.guidedMode) {
                        Text("Geführt").tag(true)
                        Text("Direkt").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .help("Geführt: Schritt für Schritt. Direkt: alle Versandfelder zusammen.")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu("Importieren") {
                    Button("PDF oder Bild …", action: appStore.requestLabelImport)
                    Button("Etsy-Adresse aus CSV …") { appStore.showEtsyImporter = true }
                    Button("Browser-Erweiterung einrichten …") { openWindow(id: "browser-extension-setup") }
                    Button("Briefmarken-Bündel …") { appStore.showPostageImporter = true }
                }
                .accessibilityLabel("Importieren")
                .help("Etikett, Briefmarken oder Etsy-Adressen importieren")
                PrinterConnectionView(appStore: appStore, bluetooth: appStore.bluetooth, handlesMenuRequests: true)
            }
        }
    }

    private func selectNewTask(_ task: GuidedShippingJourney.Task) {
        if journey.task != nil { replacementTask = task }
        else { beginNewTask(task) }
    }

    private func beginNewTask(_ task: GuidedShippingJourney.Task) {
        guard !appStore.shippingBusy else { return }
        replacementTask = nil
        appStore.resetShippingDraft()
        appStore.selectedShipmentKind = task == .parcel ? .parcel : .letter
        journey.choose(task)
        presentsDraft = true
    }

}
