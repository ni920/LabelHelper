import AppKit
import LabelCore
import SwiftUI

struct LabelHistoryView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject var letters: LetterFlowStore
    @ObservedObject var labels: LabelHistoryStore
    @ObservedObject var jobs: PrintJobStore
    @State private var search = ""
    @State private var selectedID: UUID?

    private enum Item: Identifiable {
        case letter(LetterShipmentFlow)
        case label(LabelHistoryRecord)
        case stampSheet(PrintJob)

        var id: UUID {
            switch self {
            case .letter(let flow): flow.id
            case .label(let record): record.id
            case .stampSheet(let job): job.id
            }
        }

        var date: Date {
            switch self {
            case .letter(let flow): flow.createdAt
            case .label(let record): record.createdAt
            case .stampSheet(let job): job.createdAt
            }
        }
    }

    private var items: [Item] {
        let sheets = jobs.jobs.filter { $0.letterFlowID == nil && $0.postageStampIDs != nil }
        return (letters.flows.map(Item.letter) + labels.records.map(Item.label) + sheets.map(Item.stampSheet))
            .sorted { $0.date > $1.date }
    }

    private var visibleItems: [Item] {
        guard !search.isEmpty else { return items }
        return items.filter { item in
            let fields: [String]
            switch item {
            case .letter(let flow):
                fields = [flow.recipientName, flow.orderID ?? "", flow.stamp.trackingNumber ?? ""]
            case .label(let record):
                fields = [record.title, record.orderID ?? "", record.trackingNumber ?? "", record.fileTitle]
            case .stampSheet(let job):
                fields = [job.title] + (job.postageStampIDs ?? []).compactMap(PostageStamp.trackingNumber(forID:))
            }
            return fields.contains { $0.localizedStandardContains(search) }
        }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView("Noch keine Labels", systemImage: "clock.arrow.circlepath",
                    description: Text(letters.storageError ?? labels.storageError ?? "Hier findest du vorbereitete und gedruckte Etiketten."))
                .safeAreaInset(edge: .bottom, alignment: .leading, spacing: 0) {
                    if !jobs.jobs.isEmpty { exportButton }
                }
            } else {
                HSplitView {
                    VStack(spacing: 0) {
                        List(visibleItems, selection: $selectedID) { item in
                            historyRow(item).tag(item.id)
                        }
                        Divider()
                        exportButton
                    }
                    .frame(minWidth: 235, idealWidth: 315, maxWidth: 430)

                    ScrollView {
                        if visibleItems.isEmpty {
                            ContentUnavailableView.search(text: search)
                        } else if let item = visibleItems.first(where: { $0.id == selectedID }) {
                            historyDetail(item)
                                .id(item.id)
                                .padding(24)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ContentUnavailableView("Etikett auswählen", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                    .frame(minWidth: 255)
                }
                .onChange(of: visibleItems.map(\.id), initial: true) { _, ids in
                    if selectedID.map(ids.contains) != true { selectedID = ids.first }
                }
            }
        }
        .navigationTitle("Label-Verlauf")
        .searchable(text: $search, prompt: "Name, Bestellung oder Sendungsnummer")
    }

    private var exportButton: some View {
        Button("Verlauf als CSV exportieren …", action: appStore.exportHistory)
            .buttonStyle(.link)
            .help("Gesamten Label-Verlauf als CSV-Datei sichern")
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func historyRow(_ item: Item) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title(item)).font(.headline).lineLimit(1)
                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon(item)).accessibilityHidden(true)
        }
        .padding(.vertical, 5)
    }

    private func historyDetail(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title(item), systemImage: icon(item))
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(item.date.formatted(date: .long, time: .shortened))
                .foregroundStyle(.secondary)

            switch item {
            case .letter(let flow):
                Text(flow.statusTitle)
                if let order = flow.orderID { LabeledContent("Etsy", value: "#\(order)") }
                PostageTrackingNumberView(stamp: flow.stamp)
                if let error = flow.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                Button(flow.stage == .completed ? "Etikett öffnen …" : "Fortsetzen …") {
                    appStore.letterFlowPreview = flow
                }
                .disabled(appStore.shippingBusy)
            case .label(let record):
                Text(detail(record)).textSelection(.enabled)
                LabeledContent("Status", value: record.status.label)
                LabeledContent("Format", value: record.labelFormat.sizeDescription)
                if let number = record.trackingNumber { TrackingNumberView(number: number) }
                if let error = record.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                if let job = jobs.jobs.first(where: { $0.id == record.id }) {
                    Button("Etikett öffnen …") { appStore.presentPrintPreview(job) }
                        .disabled(appStore.shippingBusy)
                }
            case .stampSheet(let job):
                LabeledContent("Status", value: job.status.label)
                let tracking = (job.postageStampIDs ?? []).compactMap(PostageStamp.trackingNumber(forID:))
                ForEach(tracking, id: \.self) { TrackingNumberView(number: $0) }
                Button("Etikett öffnen …") { appStore.presentPrintPreview(job) }
                    .disabled(appStore.shippingBusy)
            }
        }
    }

    private func title(_ item: Item) -> String {
        switch item {
        case .letter(let flow): flow.recipientName
        case .label(let record): record.title
        case .stampSheet(let job): job.title
        }
    }

    private func icon(_ item: Item) -> String {
        switch item {
        case .letter: "envelope"
        case .label(let record):
            switch record.kind {
            case .parcel: "shippingbox"
            case .addressLetter: "envelope"
            default: "doc"
            }
        case .stampSheet: "rectangle.stack"
        }
    }

    private func detail(_ record: LabelHistoryRecord) -> String {
        let order = record.orderID.map { "Etsy #\($0)" }
        let cart = record.cartNumber.map { "Warenkorb \($0)" }
        let head = [record.product ?? record.kind.title, order, cart].compactMap { $0 }.joined(separator: " · ")
        let address = record.addressLines.dropFirst().joined(separator: ", ")
        return address.isEmpty ? head : "\(head)\n\(address)"
    }
}

private struct TrackingNumberView: View {
    let number: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Sendungsnummer").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(number).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(number, forType: .string)
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Sendungsnummer kopieren")
                .help(copied ? "Sendungsnummer kopiert" : "Sendungsnummer kopieren")
            }
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { copied = false }
        }
    }
}
