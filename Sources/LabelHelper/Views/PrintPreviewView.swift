import AppKit
import LabelCore
import SwiftUI

struct PrintPreviewView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject var bluetooth: BluetoothPrinterService
    @ObservedObject private var jobs: PrintJobStore
    let job: PrintJob
    var embedded = false

    init(appStore: AppStore, job: PrintJob, embedded: Bool = false) {
        self.appStore = appStore
        self.bluetooth = appStore.bluetooth
        self.job = job
        self.jobs = appStore.jobs
        self.embedded = embedded
        _printPhase = State(initialValue: job.status == .printed ? .printed : .idle)
    }

    private enum PrintPhase { case idle, printing, printed }

    @State private var previewImage: NSImage?
    @State private var previewError: String?
    @State private var printPhase = PrintPhase.idle
    @State private var printError: String?
    @State private var usedSystemPrint = false

    private var record: LabelHistoryRecord? {
        appStore.labelHistory.records.first { $0.id == job.id }
    }

    private var tracking: [String] {
        record?.trackingNumber.map { [$0] } ?? (job.postageStampIDs ?? []).compactMap(PostageStamp.trackingNumber(forID:))
    }

    private var canPrint: Bool {
        guard previewImage != nil, previewError == nil, printPhase == .idle, !appStore.shippingBusy else { return false }
        if let stampIDs = job.postageStampIDs {
            return appStore.postage.canPrint(stampIDs) && appStore.canPrintSelectedMaterialOverBluetooth && bluetooth.connectionState.isReady
        }
        return !appStore.canPrintSelectedMaterialOverBluetooth || bluetooth.connectionState.isReady
    }


    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            previewCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: embedded ? 280 : nil)
                .accessibilityLabel("Druckvorschau, \(appStore.printedLabelFormat(job.resolvedLabelFormat).sizeDescription)")

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(record?.kind == .parcel && record?.trackingNumber != nil ? "DHL-Paketlabel" : "Druckvorschau")
                        .font(.title2.weight(.semibold))
                    Text(job.title).foregroundStyle(.secondary).lineLimit(2)
                    if let record, !record.addressLines.isEmpty {
                        Text(record.addressLines.joined(separator: "\n")).textSelection(.enabled)
                    }
                    if printPhase != .printed, let trackingNumber = record?.trackingNumber {
                        LabeledContent("Sendungsnummer", value: trackingNumber).textSelection(.enabled)
                    }
                }

                Divider()

                LabeledContent("Druckformat", value: appStore.printedLabelFormat(job.resolvedLabelFormat).sizeDescription)
                if appStore.labelStockMode == .continuous100 {
                    LabeledContent("Material", value: "Endlosrolle")
                    Label(
                        bluetooth.supportsContinuousStock
                            ? "Bluetooth mit Firmware \(bluetooth.firmwareVersion ?? "1.1.49"). Mit Schnittlinie und 2 mm Zugabe."
                            : "Für Bluetooth den Drucker mit Firmware ab 1.1.49 verbinden. Alternativ über USB mit Medientyp Endlos/Continuous drucken.",
                        systemImage: "info.circle"
                    )
                        .font(.callout)
                }
                DisclosureGroup("Druckeinstellungen") {
                    LabeledContent("Auflösung", value: "203 dpi")
                    LabeledContent("Druckdichte", value: "\(appStore.density)")
                    LabeledContent("Geschwindigkeit", value: "\(appStore.speed)")
                }

                if printPhase == .printed {
                    ShipmentCompletionView(appStore: appStore,
                        status: usedSystemPrint ? "An macOS-Systemdruck übergeben." : "Etikett gedruckt.",
                        trackingNumbers: tracking)
                    if job.postageStampIDs == nil {
                        Button("Erneut drucken …") { printPhase = .idle }
                    }
                } else {
                    if printPhase == .printing { ProgressView("Wird gedruckt …") }
                    if let error = previewError ?? printError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.red)
                    }
                    if printPhase == .idle {
                        Text("Prüfe Adresse, Ausrichtung und Größe.").font(.callout).foregroundStyle(.secondary)
                        if job.postageStampIDs != nil {
                            PostageMaterialRequirement(appStore: appStore, bluetooth: bluetooth)
                        }
                        if !bluetooth.connectionState.isReady {
                            PrinterConnectionView(appStore: appStore, bluetooth: bluetooth)
                        }
                        Button(!appStore.canPrintSelectedMaterialOverBluetooth && job.postageStampIDs == nil
                               ? "Über USB drucken" : "Jetzt drucken", action: startPrint)
                            .buttonStyle(.borderedProminent).controlSize(.large).disabled(!canPrint)
                    }
                }
                if !embedded {
                    Button("Schließen", role: .cancel) { appStore.closePrintPreview() }
                        .disabled(printPhase == .printing)
                }
            }
            .frame(width: 270)
        }
        .padding(embedded ? 0 : 24)
        .frame(minWidth: embedded ? nil : 760, minHeight: embedded ? nil : 570)
        .interactiveDismissDisabled(printPhase == .printing)
        .onAppear(perform: renderPreview)
        .onChange(of: appStore.labelStockMode) { _, _ in renderPreview() }
        .onChange(of: appStore.continuousExtraFeedMM) { _, _ in renderPreview() }
    }

    private var previewCanvas: some View {
        LabelPaperCanvas(image: previewImage, placeholder: previewError)
    }

    private func startPrint() {
        guard canPrint else { return }
        printError = nil
        usedSystemPrint = !appStore.canPrintSelectedMaterialOverBluetooth
        printPhase = .printing
        appStore.printFromPreview(jobs.jobs.first { $0.id == job.id } ?? job) { result in
            switch result {
            case .success:
                printPhase = .printed
            case .failure(let error):
                printPhase = .idle
                printError = error.localizedDescription
            }
        }
    }

    private func renderPreview() {
        previewError = nil
        previewImage = nil
        do {
            let raster = try appStore.renderLabel(job)
            guard let image = LabelPreviewRenderer.image(from: raster) else {
                previewError = "Die Rastervorschau konnte nicht erstellt werden."
                return
            }
            previewImage = image
        } catch {
            previewError = error.localizedDescription
        }
    }
}
