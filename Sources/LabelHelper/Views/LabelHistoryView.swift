import AppKit
import LabelCore
import SwiftUI

struct LabelHistoryView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject var letters: LetterFlowStore
    @ObservedObject var labels: LabelHistoryStore
    @ObservedObject var jobs: PrintJobStore
    @State private var search = ""

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
                    description: Text(letters.storageError ?? labels.storageError ?? "Gedruckte Briefe und Paketlabel erscheinen hier mit ihrer Sendungsnummer."))
            } else if visibleItems.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List(visibleItems) { item in
                    switch item {
                    case .letter(let flow): letterRow(flow)
                    case .label(let record): labelRow(record)
                    case .stampSheet(let job): stampSheetRow(job)
                    }
                }
            }
        }
        .navigationTitle("Label-Verlauf")
        .searchable(text: $search, prompt: "Name, Bestellung oder Sendungsnummer")
        .toolbar {
            Button("Verlauf exportieren …", action: appStore.exportHistory)
                .help("Label-Verlauf als CSV-Datei speichern")
                .disabled(items.isEmpty && appStore.jobs.jobs.isEmpty)
        }
    }

    private func letterRow(_ flow: LetterShipmentFlow) -> some View {
        HStack(spacing: 14) {
            kindIcon("envelope")
            VStack(alignment: .leading, spacing: 4) {
                Text(flow.recipientName).font(.headline)
                if let order = flow.orderID { Text("Etsy #\(order)").font(.caption).foregroundStyle(.secondary) }
                Text(flow.statusTitle).font(.callout).foregroundStyle(flow.stage == .completed ? .green : .secondary)
                dateText(flow.createdAt)
            }
            Spacer()
            PostageTrackingNumberView(stamp: flow.stamp)
            Button(flow.stage == .completed ? "Erneut drucken …" : "Öffnen / fortsetzen") { appStore.letterFlowPreview = flow }
        }
        .padding(.vertical, 6)
    }

    private func labelRow(_ record: LabelHistoryRecord) -> some View {
        HStack(spacing: 14) {
            kindIcon(record.kind == .parcel ? "shippingbox" : record.kind == .addressLetter ? "envelope" : "doc")
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title).font(.headline).lineLimit(2)
                Text(detail(record)).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                Text(record.status.label).font(.callout).foregroundStyle(statusColor(record.status))
                if let error = record.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
                dateText(record.createdAt)
            }
            Spacer()
            if let number = record.trackingNumber { TrackingNumberView(number: number) }
            if let job = jobs.jobs.first(where: { $0.id == record.id }) {
                Button("Öffnen …") { appStore.presentPrintPreview(job) }
                    .disabled(job.status == .printing || appStore.shippingBusy)
            }

        }
        .padding(.vertical, 6)
    }

    private func stampSheetRow(_ job: PrintJob) -> some View {
        HStack(spacing: 14) {
            kindIcon("rectangle.stack")
            VStack(alignment: .leading, spacing: 4) {
                Text(job.title).font(.headline)
                Text(job.status.label).font(.callout).foregroundStyle(statusColor(job.status))
                dateText(job.createdAt)
            }
            Spacer()
            Button("Öffnen …") { appStore.presentPrintPreview(job) }
                .disabled(job.status == .printing || appStore.shippingBusy)
        }.padding(.vertical, 6)
    }

    private func detail(_ record: LabelHistoryRecord) -> String {
        let order = record.orderID.map { "Etsy #\($0)" }
        let cart = record.cartNumber.map { "Warenkorb \($0)" }
        let head = [record.product ?? record.kind.title, order, cart].compactMap { $0 }.joined(separator: " · ")
        let address = record.addressLines.dropFirst().joined(separator: ", ")
        return address.isEmpty ? head : "\(head)\n\(address)"
    }

    private func kindIcon(_ name: String) -> some View {
        Image(systemName: name).font(.title3).foregroundStyle(.secondary).frame(width: 26).accessibilityHidden(true)
    }

    private func dateText(_ date: Date) -> some View {
        Text(date.formatted(.dateTime.day().month().hour().minute())).font(.caption).foregroundStyle(.secondary)
    }

    private func statusColor(_ status: PrintJob.Status) -> Color {
        switch status {
        case .printed: .green
        case .failed: .red
        case .ready, .printing: .secondary
        }
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
