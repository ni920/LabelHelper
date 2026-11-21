import LabelCore
import SwiftUI

struct GuidedShippingView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject var postage: PostageStampStore
    @ObservedObject var jobs: PrintJobStore
    @ObservedObject var controller: LetterFlowController
    @Binding var journey: GuidedShippingJourney
    @AppStorage("postageLabelFormatID") private var postageFormatID = LabelFormat.shipping100x150.id
    @AppStorage("postageCutGuides") private var cutGuides = true

    private var postageFormat: LabelFormat { appStore.postageFormat(for: postageFormatID) }
    private var available: [PostageStamp] { postage.entries.filter { $0.status == .available }.map(\.stamp) }
    private var selected: [PostageStamp] { available.filter { appStore.selectedPostageIDs.contains($0.id) } }
    private var parcel: PrintJob? { jobs.jobs.first { $0.id == journey.parcelJobID } }
    private var busy: Bool { appStore.printInProgress || appStore.printingPostageBatch || controller.activeFlowID != nil }
    private var layout: PostageSheetLayout {
        PostageSheetLayout(stampSizes: selected.map { $0.sourceRect.size }, format: postageFormat,
                           fitHeightToContent: appStore.labelStockMode == .continuous100)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let task = journey.task, let step = journey.step {
                    if appStore.guidedMode {
                        stepHeader(task: task, step: step)
                        stepContent(step)
                    } else {
                        directContent(task)
                    }
                }
                if let message = appStore.lastMessage {
                    Label(message, systemImage: "info.circle").font(.callout).textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle(journey.task?.title ?? "Versenden")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let actionTitle {
                HStack {
                    if let reason { Label(reason, systemImage: "info.circle").font(.callout) }
                    Spacer()
                    Button(actionTitle, action: advance).buttonStyle(.borderedProminent)
                        .disabled(reason != nil || busy)
                }.padding(16).background(.bar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: back) {
                    Label(showsPreviousStep ? "Zurück" : "Aufgaben", systemImage: "chevron.left")
                }.disabled(busy)
            }
        }
        .focusedSceneValue(\.shippingNavigation, ShippingNavigationActions(back: back, advance: advance,
            canGoBack: !busy, canAdvance: actionTitle != nil && reason == nil && !busy))
    }

    private var showsPreviousStep: Bool { appStore.guidedMode && journey.index > 0 }

    private func back() {
        if showsPreviousStep { journey.back() }
        else { appStore.showShippingHome() }
    }

    private var actionTitle: String? {
        if journey.task == .postage {
            if !appStore.guidedMode || journey.step == .review { return "Druckvorschau" }
            return "Weiter"
        }
        return appStore.guidedMode && journey.task == .letter && journey.step == .recipient ? "Druck prüfen" : nil
    }

    private var reason: String? {
        switch journey.task {
        case .letter:
            if !appStore.recipientAddress.isComplete { return "Ergänze zuerst die Empfängeradresse." }
            if !appStore.senderAddress.isComplete { return "Hinterlege den Absender." }
        case .postage:
            if available.isEmpty { return "Importiere zuerst ein Briefmarken-PDF." }
            if !appStore.guidedMode || journey.step != .postageSource {
                if selected.isEmpty { return "Wähle mindestens eine Briefmarke." }
                if layout.capacity == 0 { return "Wähle ein größeres Etikettenformat." }
            }
        default: break
        }
        return nil
    }

    private func advance() {
        guard actionTitle != nil, reason == nil, !busy else { return }
        if journey.task == .postage && (!appStore.guidedMode || journey.step == .review) {
            appStore.preparePostageSheets(format: postageFormat, cutGuides: cutGuides)
        } else {
            journey.advance()
        }
    }

    private func stepHeader(task: GuidedShippingJourney.Task, step: GuidedShippingJourney.Step) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(step.title).font(.title2.bold())
                Spacer()
                Text("Schritt \(journey.index + 1) von \(task.steps.count)").font(.callout).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(journey.index + 1), total: Double(task.steps.count))
                .accessibilityLabel("Fortschritt")
                .accessibilityValue("Schritt \(journey.index + 1) von \(task.steps.count)")
        }
    }

    @ViewBuilder private func directContent(_ task: GuidedShippingJourney.Task) -> some View {
        switch task {
        case .letter:
            recipientFields
            Divider()
            Text("Druck prüfen").font(.title2.bold())
            letterReview
        case .parcel:
            parcelReview
        case .postage:
            postageSelection
            if !selected.isEmpty { postageLayout }
        }
    }

    @ViewBuilder private func stepContent(_ step: GuidedShippingJourney.Step) -> some View {
        switch step {
        case .recipient: recipientFields
        case .parcelFile: parcelReview
        case .postageSource, .postageSelection: postageSelection
        case .format: postageLayout
        case .review:
            switch journey.task {
            case .letter: letterReview
            case .parcel: parcelReview
            case .postage:
                Label("\(selected.count) Marken auf \(layout.sheets.count) Etikett\(layout.sheets.count == 1 ? "" : "en")", systemImage: "rectangle.stack")
                Text(cutGuides ? "Mit Schnittlinien zum Ausschneiden." : "Ohne Schnittlinien.")
                    .foregroundStyle(.secondary)
            case nil: EmptyView()
            }
        }
    }

    private var recipientFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let orderID = appStore.activeBrowserOrder?.orderID ?? appStore.activeCSVOrderID {
                Label("Etsy-Bestellung #\(orderID)", systemImage: "cart")
            }
            GroupBox("Empfänger") { RecipientEditorView(appStore: appStore).padding(12) }
            Button("Aus Etsy-CSV übernehmen …") { appStore.showEtsyImporter = true }
            SenderSummaryView(appStore: appStore)
        }
        .disabled(busy || appStore.draftLetterFlowID != nil || appStore.draftAddressJobID != nil)
    }

    private var letterReview: some View {
        LetterReviewView(appStore: appStore, postage: postage, jobs: jobs, bluetooth: appStore.bluetooth)
    }

    @ViewBuilder private var parcelReview: some View {
        if let error = appStore.parcelImportError {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        if let parcel {
            PrintPreviewView(appStore: appStore, job: parcel, embedded: true)
                .id(parcel.id)
            if parcel.status != .printing {
                Button("Andere Datei wählen …", action: appStore.chooseDHLLabelImport).disabled(busy)
            }
        } else {
            Text("Wähle das PDF deiner gekauften DHL-Versandmarke. Das Paketlabel wird im Format 100 × 150 mm vorbereitet.")
                .foregroundStyle(.secondary)
            Button(appStore.parcelImportError == nil ? "DHL-PDF auswählen …" : "Andere Datei wählen …",
                   action: appStore.chooseDHLLabelImport).buttonStyle(.borderedProminent)
        }
    }

    private var postageSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if available.isEmpty {
                Text("Keine Briefmarken verfügbar. Importiere ein Bündel mit Internetmarken ohne Motiv und Adresse.")
                    .foregroundStyle(.secondary)
            } else if !appStore.guidedMode || journey.step != .postageSource {
                HStack {
                    Text("\(selected.count) von \(available.count) ausgewählt").font(.headline)
                    Spacer()
                    Button("Alle") { appStore.selectedPostageIDs = Set(available.map(\.id)) }
                    Button("Keine") { appStore.selectedPostageIDs = [] }
                }
                ForEach(available) { stamp in
                    Toggle("\(stamp.amount) € · Marke \(stamp.number) · …\(stamp.id.suffix(8))", isOn: Binding(
                        get: { appStore.selectedPostageIDs.contains(stamp.id) },
                        set: { if $0 { appStore.selectedPostageIDs.insert(stamp.id) } else { appStore.selectedPostageIDs.remove(stamp.id) } }
                    ))
                }
            } else {
                Text("\(available.count) Marken im Bestand verfügbar.")
            }
            Button("Briefmarken-PDF importieren …") { appStore.showPostageImporter = true }
                .buttonStyle(.borderedProminent)
        }.disabled(busy)
    }

    private var postageLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            PostageFormatControls(appStore: appStore, formatID: $postageFormatID)
            Toggle("Schnittlinien drucken", isOn: $cutGuides)
            Text("\(selected.count) Marken auf \(layout.sheets.count) Etikett\(layout.sheets.count == 1 ? "" : "en") · Originalgröße")
            PostageMaterialRequirement(appStore: appStore, bluetooth: appStore.bluetooth)
        }.disabled(busy)
    }
}
