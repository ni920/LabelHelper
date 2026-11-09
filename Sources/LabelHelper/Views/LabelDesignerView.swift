import AppKit
import LabelCore
import SwiftUI

/// Settings for the label look. The address preview uses the real print path.
struct LabelDesignerView: View {
    private enum PreviewKind: Hashable { case address, stamp }

    /// Used until stamps are in stock; about the size of an Internetmarke crop.
    private static let fallbackStampSize = CGSize(width: 116, height: 68)

    @ObservedObject var appStore: AppStore
    @State private var previewKind = PreviewKind.address
    @State private var image: NSImage?
    @State private var error: String?
    @State private var combinedFormat: LabelFormat?

    private struct Input: Equatable {
        var recipient: RecipientAddress
        var sender: SenderAddress
        var format: LabelFormat
        var design: AddressLabelDesign
        var continuous: Bool
        var kind: PreviewKind
        var placement: PostageStampPlacement
        var stampFormat: LabelFormat
        var stampSize: CGSize
        var combined: CombinedLabelSettings
    }

    private static let sampleRecipient = RecipientAddress(
        name: "Alex Beispiel", street1: "Musterstraße 12", postalCode: "10115", city: "Berlin", country: "Deutschland"
    )
    private static let sampleSender = SenderAddress(
        name: "Dein Shop", street: "Beispielweg 1", postalCode: "12345", city: "Musterstadt", country: "Deutschland"
    )

    private var input: Input {
        let recipient = appStore.recipientAddress.isComplete ? appStore.recipientAddress : Self.sampleRecipient
        let sender = appStore.senderAddress.isComplete ? appStore.senderAddress : Self.sampleSender
        let continuous = appStore.labelStockMode == .continuous100
        let format = continuous
            ? EtsyAddressLabelWriter.continuousFormat(recipient: recipient, sender: sender, design: appStore.addressLabelDesign)
            : appStore.selectedLetterLabelFormat
        return Input(recipient: recipient, sender: sender, format: format, design: appStore.addressLabelDesign, continuous: continuous,
                     kind: previewKind, placement: appStore.postageStampPlacement, stampFormat: appStore.selectedLetterPostageFormat,
                     stampSize: appStore.postage.entries.first?.stamp.sourceRect.size ?? Self.fallbackStampSize,
                     combined: appStore.combinedLabel)
    }

    private var stampIsBesideAddress: Bool {
        input.combined.isEnabled && [.stampRight, .stampLeft].contains(input.combined.arrangement)
    }

    private var stampLayout: PostageSheetLayout {
        PostageSheetLayout(stampSizes: [input.stampSize], format: input.stampFormat,
                           fitHeightToContent: input.continuous, placement: input.placement)
    }

    private var previewSize: String {
        if input.combined.isEnabled, let combinedFormat { return appStore.printedLabelFormat(combinedFormat).sizeDescription }
        let format = previewKind == .address ? input.format : stampLayout.sheetFormats.first ?? input.stampFormat
        return appStore.printedLabelFormat(format).sizeDescription
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if input.combined.isEnabled {
                    Text("Vorschau · Adresse und Briefmarke").font(.headline)
                } else {
                    Picker("Vorschau", selection: $previewKind) {
                        Text("Adresse").tag(PreviewKind.address)
                        Text("Briefmarke").tag(PreviewKind.stamp)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                Spacer()
                Text(previewSize)
                    .font(.callout).foregroundStyle(.secondary)
            }
            LabelPaperCanvas(image: image, placeholder: error, raster: previewKind == .address || input.combined.isEnabled)
                .frame(height: 170)
            Form {
                Section("Absender") {
                    placementPicker("Position", selection: $appStore.addressLabelDesign.senderPlacement,
                                    options: AddressLabelDesign.SenderPlacement.allCases, title: \.title)
                    if appStore.addressLabelDesign.senderPlacement != .hidden {
                        placementPicker("Ausrichtung", selection: $appStore.addressLabelDesign.senderAlignment,
                                        options: AddressLabelDesign.HorizontalPlacement.allCases, title: \.title)
                        scaleSlider("Größe", value: $appStore.addressLabelDesign.senderScale)
                        Toggle("Trennlinie zur Adresse", isOn: $appStore.addressLabelDesign.showsSeparator)
                    }
                }
                Section("Empfänger") {
                    placementPicker("Ausrichtung", selection: $appStore.addressLabelDesign.recipientAlignment,
                                    options: AddressLabelDesign.HorizontalPlacement.allCases, title: \.title)
                    if !input.continuous {
                        placementPicker("Höhe", selection: $appStore.addressLabelDesign.recipientVerticalPlacement,
                                        options: AddressLabelDesign.VerticalPlacement.allCases, title: \.title)
                    }
                    scaleSlider("Größe", value: $appStore.addressLabelDesign.recipientScale)
                    placementPicker("Schriftstärke", selection: $appStore.addressLabelDesign.recipientWeight,
                                    options: AddressLabelDesign.Weight.allCases, title: \.title)
                    Toggle("Name hervorheben", isOn: $appStore.addressLabelDesign.emphasizesName)
                }
                Section("Briefmarke") {
                    Toggle("Adresse und Briefmarke auf einem Etikett", isOn: $appStore.combinedLabel.isEnabled)
                    if appStore.combinedLabel.isEnabled {
                        placementPicker("Marke neben der Adresse", selection: $appStore.combinedLabel.arrangement,
                                        options: CombinedLabelSettings.Arrangement.allCases, title: \.title)
                    }
                    if !stampIsBesideAddress {
                        placementPicker("Ausrichtung", selection: $appStore.postageStampPlacement.horizontal,
                                        options: PostageStampPlacement.Horizontal.allCases, title: \.title)
                    }
                    if input.combined.isEnabled ? stampIsBesideAddress : !input.continuous {
                        placementPicker("Höhe", selection: $appStore.postageStampPlacement.vertical,
                                        options: AddressLabelDesign.VerticalPlacement.allCases, title: \.title)
                    }
                }
                Section("Gesamtes Etikett") {
                    Picker("Schriftart", selection: $appStore.addressLabelDesign.typeface) {
                        ForEach(AddressLabelDesign.Typeface.allCases) { Text($0.title).tag($0) }
                    }
                    LabeledContent("Zusätzlicher Rand") {
                        HStack {
                            Slider(value: $appStore.addressLabelDesign.extraMarginMM,
                                   in: AddressLabelDesign.extraMarginRangeMM, step: 0.5)
                            Text("\(appStore.addressLabelDesign.extraMarginMM.formatted(.number.precision(.fractionLength(1)))) mm")
                                .monospacedDigit().frame(width: 52, alignment: .trailing)
                        }
                    }
                }
                Section {
                    Text("Gilt für neue Briefetiketten und Briefmarken. Bereits vorbereitete Etiketten und DHL-Paketlabel bleiben unverändert, Briefmarken behalten immer ihre Originalgröße.")
                        .font(.callout)
                    Button("Auf Standard zurücksetzen") {
                        appStore.addressLabelDesign = .standard
                        appStore.postageStampPlacement = .standard
                        appStore.combinedLabel = .standard
                    }
                    .disabled(appStore.addressLabelDesign == .standard && appStore.postageStampPlacement == .standard
                              && appStore.combinedLabel == .standard)
                }
            }
            .formStyle(.grouped)
        }
        .onAppear(perform: render)
        .onChange(of: input) { _, _ in render() }
        .onChange(of: appStore.addressLabelDesign) { _, _ in previewKind = .address }
        .onChange(of: appStore.postageStampPlacement) { _, _ in previewKind = .stamp }
    }

    private func placementPicker<Option: Hashable & Identifiable>(
        _ label: String,
        selection: Binding<Option>,
        options: [Option],
        title: KeyPath<Option, String>
    ) -> some View {
        Picker(label, selection: selection) {
            ForEach(options) { Text($0[keyPath: title]).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private func scaleSlider(_ label: String, value: Binding<Double>) -> some View {
        LabeledContent(label) {
            HStack {
                Slider(value: value, in: AddressLabelDesign.scaleRange, step: 0.05)
                Text(value.wrappedValue.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit().frame(width: 52, alignment: .trailing)
            }
        }
    }

    private func render() {
        if input.combined.isEnabled { renderCombined(); return }
        guard input.kind == .address else { renderStamp(); return }
        let input = input
        do {
            // In-memory PDF only, same renderer as the printed label.
            let data = try EtsyAddressLabelWriter.makePDFData(
                recipient: input.recipient, sender: input.sender, format: input.format, design: input.design
            )
            let raster = try LabelRenderer.render(pdfData: data, format: input.format)
            image = LabelPreviewRenderer.image(from: appStore.applyingMaterialCutGuide(to: raster))
            error = image == nil ? "Die Vorschau konnte nicht erstellt werden." : nil
        } catch {
            image = nil
            self.error = error.localizedDescription
        }
    }

    private func renderCombined() {
        let input = input
        do {
            let label = try appStore.combinedLetterPDF(stamp: nil, stampSize: input.stampSize,
                                                       recipient: input.recipient, sender: input.sender)
            let raster = try LabelRenderer.render(pdfData: label.data, format: label.format)
            image = LabelPreviewRenderer.image(from: appStore.applyingMaterialCutGuide(to: raster))
            combinedFormat = label.format
            error = image == nil ? "Die Vorschau konnte nicht erstellt werden." : nil
        } catch {
            image = nil
            combinedFormat = nil
            self.error = error.localizedDescription
        }
    }

    /// A marked box at the position computed for printing; no stamp is rendered.
    private func renderStamp() {
        let layout = stampLayout
        guard let rect = layout.sheets.first?.first?.rect, let format = layout.sheetFormats.first else {
            image = nil
            error = "Die Briefmarke passt nicht auf dieses Etikett."
            return
        }
        let size = CGSize(width: format.widthMM * 72 / 25.4, height: format.heightMM * 72 / 25.4)
        image = NSImage(size: size, flipped: false) { _ in
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            NSColor.black.setStroke()
            let box = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            box.lineWidth = 1
            box.stroke()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.black]
            let label = NSAttributedString(string: "Briefmarke", attributes: attributes)
            label.draw(at: NSPoint(x: rect.midX - label.size().width / 2, y: rect.midY - label.size().height / 2))
            return true
        }
        error = nil
    }
}
