import LabelCore
import SwiftUI

struct OrderBatchView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject var batch: OrderBatchStore
    @ObservedObject var postage: PostageStampStore
    @ObservedObject var bluetooth: BluetoothPrinterService
    @State private var withPostage = true
    @State private var chosenAmount: String?

    private var amounts: [String] {
        Set(postage.entries.filter { $0.status == .available }.map { $0.stamp.amount }).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
    private var amount: String {
        if let chosenAmount, amounts.contains(chosenAmount) { return chosenAmount }
        return postage.entries.first { $0.id == appStore.selectedLetterPostageID }?.stamp.amount ?? amounts.first ?? ""
    }
    private var count: Int { batch.orders.filter { !$0.submitted }.count }
    private var issue: String? { appStore.batchPrintIssue(withPostage: withPostage, amount: amount) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sammeldruck").font(.title2.weight(.semibold))
            if batch.orders.isEmpty {
                ContentUnavailableView("Keine Bestellungen gesammelt", systemImage: "square.stack",
                    description: Text("Öffne eine Etsy-CSV oder wähle beim Import aus dem Browser „Zum Sammeldruck“."))
            } else {
                List(batch.orders) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.recipient.name).font(.headline)
                            Text("#\(entry.orderID) · \(entry.recipient.lines.dropFirst().joined(separator: ", "))")
                                .font(.callout).foregroundStyle(.secondary)
                            if !entry.packingNote.isEmpty { Text(entry.packingNote).font(.callout) }
                            if entry.submitted && !batch.running {
                                Label("Auftrag im Label-Verlauf prüfen", systemImage: "exclamationmark.circle")
                            }
                        }
                        Spacer()
                        if !batch.running {
                            Button {
                                batch.remove(entry.id)
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Aus dem Sammeldruck entfernen")
                            .accessibilityLabel("\(entry.recipient.name) entfernen")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if count > 0 && !batch.running {
                HStack {
                    Toggle("Mit Briefmarke", isOn: $withPostage)
                    if withPostage && !amounts.isEmpty {
                        Picker("Porto je Brief", selection: Binding(get: { amount }, set: { chosenAmount = $0 })) {
                            ForEach(amounts, id: \.self) { value in
                                Text("\(value) € · \(appStore.availableBatchStamps(amount: value).count) verfügbar").tag(value)
                            }
                        }
                        .fixedSize()
                    }
                }
                if let issue { Text(issue).font(.callout).foregroundStyle(.secondary) }
                if !bluetooth.connectionState.isReady {
                    PrinterConnectionView(appStore: appStore, bluetooth: bluetooth)
                }
            }
            if let message = batch.storageError ?? batch.message {
                Text(message).font(.callout).textSelection(.enabled)
            }
            Divider()
            HStack {
                if batch.running {
                    ProgressView().controlSize(.small)
                    Spacer()
                    Button(batch.stopping ? "Hält nach diesem Brief an" : "Nach diesem Brief anhalten") { batch.stopAfterCurrent() }
                        .disabled(batch.stopping)
                } else {
                    Button("Etsy-CSV öffnen …") {
                        appStore.requestFileImport(.etsyCSV)
                        appStore.showOrderBatch = false
                    }
                    Spacer()
                    Button("Schließen") { appStore.showOrderBatch = false }
                        .keyboardShortcut(.cancelAction)
                    if count > 0 {
                        Button(count == 1 ? "1 Brief drucken" : "\(count) Briefe drucken") {
                            appStore.startOrderBatch(withPostage: withPostage, amount: amount)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(issue != nil || appStore.shippingBusy)
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 570, idealWidth: 620, minHeight: 420, idealHeight: 480)
        .interactiveDismissDisabled(batch.running)
    }
}
