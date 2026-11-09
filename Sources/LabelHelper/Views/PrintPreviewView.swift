import AppKit
import LabelCore
import SwiftUI

struct PrintPreviewView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject var bluetooth: BluetoothPrinterService
    let job: PrintJob

    init(appStore: AppStore, job: PrintJob) {
        self.appStore = appStore
        self.bluetooth = appStore.bluetooth
        self.job = job
    }

    private enum PrintPhase { case idle, printing, printed }

    @State private var previewImage: NSImage?
    @State private var previewError: String?
    @State private var printPhase = PrintPhase.idle
    @State private var printError: String?

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            previewCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Druckvorschau")
                        .font(.title2.weight(.semibold))
                    Text(job.title)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
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

                switch printPhase {
                case .printed:
                    Label("Gedruckt", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                case .printing:
                    Label {
                        Text("Wird gedruckt …")
                    } icon: {
                        ProgressView().controlSize(.small)
                    }
                case .idle:
                    Text("Prüfe Adresse, Ausrichtung und Größe vor dem Drucken.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = previewError ?? printError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if printPhase == .idle && !bluetooth.connectionState.isReady {
                    PrinterConnectionView(appStore: appStore, bluetooth: bluetooth)
                }

                Spacer()

                HStack {
                    Button("Schließen", role: .cancel) {
                        appStore.closePrintPreview()
                    }
                    .disabled(printPhase == .printing)
                    Spacer()
                    if printPhase == .printed {
                        Button("Zurück zum Anfang", action: appStore.returnToStart)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    } else {
                        Button(appStore.canPrintSelectedMaterialOverBluetooth ? "Jetzt drucken" : "Über USB drucken", action: startPrint)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(
                                previewImage == nil
                                    || previewError != nil
                                    || printPhase == .printing
                                    || appStore.printInProgress || appStore.printingPostageBatch
                                    || (job.postageStampIDs.map { !appStore.postage.canPrint($0) } ?? false)
                                    || (appStore.canPrintSelectedMaterialOverBluetooth
                                        && !bluetooth.connectionState.isReady)
                            )
                    }
                }
            }
            .frame(width: 270)
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 570)
        .interactiveDismissDisabled(printPhase == .printing)
        .onAppear(perform: renderPreview)
        .onChange(of: appStore.labelStockMode) { _, _ in renderPreview() }
    }

    private var previewCanvas: some View {
        LabelPaperCanvas(image: previewImage, placeholder: previewError)
    }

    private func startPrint() {
        printError = nil
        printPhase = .printing
        appStore.printFromPreview(job) { result in
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
