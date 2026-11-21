import LabelCore
import SwiftUI

struct LetterReviewView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject var postage: PostageStampStore
    @ObservedObject var jobs: PrintJobStore
    @ObservedObject var bluetooth: BluetoothPrinterService
    @State private var plan: LetterPrintPlan?
    @State private var renderError: String?
    @State private var pageIndex = 0

    private var available: [PostageStamp] { postage.entries.filter { $0.status == .available }.map(\.stamp) }
    private var savedJob: PrintJob? { jobs.jobs.first { $0.id == appStore.draftAddressJobID } }
    private var settings: LetterReviewSettings { appStore.letterReviewSettings }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let savedJob, savedJob.status == .printed {
                ShipmentCompletionView(appStore: appStore, status: appStore.lastMessage ?? "Adressetikett gedruckt.")
            } else if savedJob?.status == .printing {
                ProgressView("Adressetikett wird gedruckt …")
            } else if savedJob != nil || appStore.draftLetterFlowID != nil {
                if let error = savedJob?.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                Button("Druckauftrag öffnen …") { appStore.openExistingLetterPrint() }
                    .buttonStyle(.borderedProminent)
            } else {
                franking
                GroupBox("Etikettenmaterial") {
                    LabelFormatControls(appStore: appStore, showHeading: false).padding(8)
                }
                if let plan, plan.settings == settings, !plan.pages.isEmpty {
                    let page = plan.pages[min(pageIndex, plan.pages.count - 1)]
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(plan.pages.count == 2 ? "2 getrennte Etiketten"
                                 : settings.stamp == nil ? "1 Adressetikett" : "1 gemeinsames Etikett").font(.headline)
                            Spacer()
                            Text(appStore.printedLabelFormat(page.format).sizeDescription).foregroundStyle(.secondary)
                        }
                        if plan.pages.count > 1 {
                            Picker("Etikett in der Vorschau", selection: $pageIndex) {
                                ForEach(plan.pages.indices, id: \.self) { Text(plan.pages[$0].title).tag($0) }
                            }.pickerStyle(.segmented)
                        }
                        LabelPaperCanvas(image: page.image, placeholder: nil).frame(height: 190)
                            .accessibilityLabel("Druckvorschau: \(page.title), \(appStore.printedLabelFormat(page.format).sizeDescription)")
                    }
                } else if let renderError {
                    Label(renderError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if settings.needsStamp {
                    PostageMaterialRequirement(appStore: appStore, bluetooth: bluetooth)
                }
                HStack {
                    if !bluetooth.connectionState.isReady {
                        PrinterConnectionView(appStore: appStore, bluetooth: bluetooth)
                    }
                    Spacer()
                    Button(printTitle) {
                        if let plan { appStore.printReviewedLetter(plan) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canPrint)
                }
            }
        }
        .task(id: settings) {
            pageIndex = 0
            plan = nil
            renderError = nil
            guard settings.recipient.isComplete, settings.sender.isComplete else { return }
            guard !settings.needsStamp || settings.stamp != nil else { return }
            do { plan = try LetterPrintPlan.make(for: settings) }
            catch { renderError = error.localizedDescription }
        }
    }

    private var franking: some View {
        GroupBox("Frankierung") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Was soll gedruckt werden?", selection: $appStore.letterWithPostage) {
                    Text("Nur Adressetikett").tag(false)
                    Text("Adresse und Briefmarke").tag(true)
                }.pickerStyle(.segmented)
                if appStore.letterWithPostage {
                    if available.isEmpty {
                        Label("Keine Briefmarken verfügbar", systemImage: "info.circle")
                        HStack {
                            Button("Briefmarken-PDF importieren …") { appStore.showPostageImporter = true }
                                .buttonStyle(.borderedProminent)
                            Button("Nur Adresse drucken") { appStore.letterWithPostage = false }
                        }
                    } else {
                        Picker("Briefmarke", selection: $appStore.selectedLetterPostageID) {
                            Text("Passenden Portowert auswählen …").tag("")
                            ForEach(available) { stamp in
                                Text("\(stamp.amount) € · …\(stamp.id.suffix(8))").tag(stamp.id)
                            }
                        }
                        Button("Briefmarken-PDF importieren …") { appStore.showPostageImporter = true }
                    }
                }
            }.padding(8)
        }
    }

    private var printTitle: String {
        !settings.needsStamp && !appStore.canPrintSelectedMaterialOverBluetooth ? "Über USB drucken" : "Jetzt drucken"
    }

    private var canPrint: Bool {
        guard let plan, plan.settings == settings, !appStore.shippingBusy else { return false }
        if settings.needsStamp {
            return bluetooth.connectionState.isReady && appStore.canPrintSelectedMaterialOverBluetooth
        }
        return bluetooth.connectionState.isReady || !appStore.canPrintSelectedMaterialOverBluetooth
    }
}
