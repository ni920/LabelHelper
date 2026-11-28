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
    @State private var editingRecipient = false

    private var available: [PostageStamp] { postage.entries.filter { $0.status == .available }.map(\.stamp) }
    private var savedJob: PrintJob? { jobs.jobs.first { $0.id == appStore.draftAddressJobID } }
    private var settings: LetterReviewSettings { appStore.letterReviewSettings }

    var body: some View {
        Group {
            if let savedJob, savedJob.status == .printed {
                ShipmentCompletionView(appStore: appStore, status: appStore.lastMessage ?? "Adressetikett gedruckt.")
            } else if savedJob?.status == .printing {
                ProgressView("Adressetikett wird gedruckt …")
            } else if savedJob != nil || appStore.draftLetterFlowID != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text(appStore.recipientName).font(.title2.weight(.semibold))
                    if let error = savedJob?.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    Button("Druckauftrag öffnen …") { appStore.openExistingLetterPrint() }
                        .buttonStyle(.borderedProminent)
                        .disabled(appStore.shippingBusy)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        shipmentDetails.frame(minWidth: 250, maxWidth: 320)
                        preview.frame(minWidth: 295, maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        shipmentDetails
                        preview
                    }
                }
            }
        }
        .task(id: settings) {
            pageIndex = 0
            plan = nil
            renderError = nil
            guard savedJob == nil, appStore.draftLetterFlowID == nil,
                  settings.recipient.isComplete, settings.sender.isComplete,
                  !settings.needsStamp || settings.stamp != nil else { return }
            do { plan = try LetterPrintPlan.make(for: settings) }
            catch { renderError = error.localizedDescription }
        }
    }

    private var shipmentDetails: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Empfänger") {
                VStack(alignment: .leading, spacing: 10) {
                    if editingRecipient || !settings.recipient.isComplete {
                        RecipientEditorView(appStore: appStore)
                        ViewThatFits(in: .horizontal) {
                            HStack { addressEditorActions }
                            VStack(alignment: .leading) { addressEditorActions }
                        }
                    } else {
                        Text(settings.recipient.lines.joined(separator: "\n"))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        if let orderID = appStore.activeBrowserOrder?.orderID ?? appStore.activeCSVOrderID {
                            Text("Etsy #\(orderID)").font(.callout).foregroundStyle(.secondary)
                        }
                        Button("Bearbeiten …") { editingRecipient = true }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let stamp = settings.stamp {
                LabeledContent("Porto", value: "\(stamp.amount) €")
            } else if settings.needsStamp {
                Label("Keine Briefmarke verfügbar", systemImage: "exclamationmark.circle")
                Button("Briefmarken-PDF öffnen …") { appStore.requestFileImport(.postage) }
            } else {
                Label("Nur Adressetikett", systemImage: "envelope")
            }

            if settings.continuous {
                DisclosureGroup("Packhinweis") {
                    TextField("Zum Beispiel 1 × Capy Gold", text: $appStore.packingNote, axis: .vertical)
                        .lineLimit(1...6)
                        .textFieldStyle(.roundedBorder)
                        .padding(.top, 6)
                }
            }
            DisclosureGroup("Frankierung ändern") {
                Form {
                    Toggle("Mit Briefmarke", isOn: $appStore.letterWithPostage)
                    if settings.needsStamp && !available.isEmpty {
                        Picker("Briefmarke", selection: $appStore.selectedLetterPostageID) {
                            ForEach(available) { stamp in
                                Text("\(stamp.amount) € · …\(stamp.id.suffix(8))").tag(stamp.id)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
            if !settings.sender.isComplete {
                SettingsLink { Label("Absender einrichten …", systemImage: "gearshape") }
            }
        }
        .disabled(appStore.shippingBusy)
    }

    @ViewBuilder private var addressEditorActions: some View {
        Button("Etsy-CSV öffnen …") { appStore.requestFileImport(.etsyCSV) }
        if settings.recipient.isComplete {
            Button("Übernehmen") { editingRecipient = false }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let plan, plan.settings == settings, !plan.pages.isEmpty {
                let page = plan.pages[min(pageIndex, plan.pages.count - 1)]
                LabeledContent(page.title, value: appStore.printedLabelFormat(page.format).sizeDescription)
                if plan.pages.count > 1 {
                    Picker("Etikett in der Vorschau", selection: $pageIndex) {
                        ForEach(plan.pages.indices, id: \.self) { Text(plan.pages[$0].title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                LabelPaperCanvas(image: page.image).frame(height: 260)
                    .accessibilityLabel("Druckvorschau: \(page.title)")
            } else {
                LabelPaperCanvas(image: nil, placeholder: previewPlaceholder).frame(height: 260)
            }

            if renderError != nil { SettingsLink { Text("Etikettenformat prüfen …") } }
            if settings.needsStamp {
                PostageMaterialRequirement(appStore: appStore, bluetooth: bluetooth)
            }
            ViewThatFits(in: .horizontal) {
                HStack { printerActions }
                VStack(alignment: .leading) { printerActions }
            }
        }
    }

    @ViewBuilder private var printerActions: some View {
        if !bluetooth.connectionState.isReady && (settings.needsStamp || appStore.canPrintSelectedMaterialOverBluetooth) {
            PrinterConnectionView(appStore: appStore, bluetooth: bluetooth)
        }
        Button(printTitle) {
            if let plan { appStore.printReviewedLetter(plan) }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canPrint)
    }

    private var previewPlaceholder: String? {
        if !settings.recipient.isComplete { return "Empfängeradresse vervollständigen" }
        if !settings.sender.isComplete { return "Absender einrichten" }
        if settings.needsStamp && settings.stamp == nil { return "Briefmarken importieren oder nur die Adresse drucken" }
        return renderError
    }

    private var printTitle: String {
        if !settings.needsStamp && !appStore.canPrintSelectedMaterialOverBluetooth { return "Über USB drucken" }
        return settings.needsStamp ? "Brief drucken" : "Adresse drucken"
    }

    private var canPrint: Bool {
        guard let plan, plan.settings == settings, !appStore.shippingBusy else { return false }
        if settings.needsStamp {
            return bluetooth.connectionState.isReady && appStore.canPrintSelectedMaterialOverBluetooth
        }
        return bluetooth.connectionState.isReady || !appStore.canPrintSelectedMaterialOverBluetooth
    }
}
