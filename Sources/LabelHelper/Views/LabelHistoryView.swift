import AppKit
import LabelCore
import SwiftUI

struct LabelHistoryView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject var letters: LetterFlowStore
    @ObservedObject var labels: LabelHistoryStore

    private enum Item: Identifiable {
        case letter(LetterShipmentFlow)
        case label(LabelHistoryRecord)

        var id: UUID {
            switch self {
            case .letter(let flow): flow.id
            case .label(let record): record.id
            }
        }

        var date: Date {
            switch self {
            case .letter(let flow): flow.createdAt
            case .label(let record): record.createdAt
            }
        }
    }

    private var items: [Item] {
        (letters.flows.map(Item.letter) + labels.records.map(Item.label)).sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView("Noch keine Labels", systemImage: "clock.arrow.circlepath",
                    description: Text(letters.storageError ?? labels.storageError ?? "Gedruckte Briefe und Paketlabel erscheinen hier mit ihrer Sendungsnummer."))
            } else {
                List(items) { item in
                    switch item {
                    case .letter(let flow): letterRow(flow)
                    case .label(let record): labelRow(record)
                    }
                }
            }
        }
        .navigationTitle("Label-Verlauf")
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
        }
        .padding(.vertical, 6)
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
