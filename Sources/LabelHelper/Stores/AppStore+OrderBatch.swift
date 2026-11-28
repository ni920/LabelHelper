import Foundation
import LabelCore

extension AppStore {
    func collectBrowserBatch(_ orders: [BrowserOrderPayload]) {
        let entries = orders.map { BatchOrder(orderID: $0.orderID, recipient: $0.recipient, packingNote: $0.packingNote ?? "") }
        _ = orderBatch.add(entries)
        showOrderBatch = true
    }

    func collectBrowserOrder() {
        guard !shippingBusy, let order = incomingBrowserOrder,
              orderBatch.add([BatchOrder(orderID: order.orderID, recipient: order.recipient, packingNote: order.packingNote ?? "")]) else { return }
        dismissIncomingBrowserOrder()
        lastMessage = orderBatch.message
        showShippingHome()
    }

    func collectCSVOrders(_ orders: [EtsyOrder]) {
        guard !shippingBusy, !orders.isEmpty,
              orderBatch.add(orders.map { BatchOrder(orderID: $0.id, recipient: $0.recipientAddress, packingNote: $0.packingNote ?? "") }) else { return }
        reviewBatchAfterCSV = true
        showEtsyImportReview = false
        lastMessage = orderBatch.message
        showShippingHome()
    }

    func availableBatchStamps(amount: String) -> [PostageStamp] {
        postage.entries.filter { $0.status == .available && $0.stamp.amount == amount }.map(\.stamp)
    }

    func batchPrintIssue(withPostage: Bool, amount: String) -> String? {
        let pending = orderBatch.orders.filter { !$0.submitted }
        guard !pending.isEmpty else { return nil }
        if let error = orderBatch.storageError ?? labelHistory.storageError { return error }
        if !senderAddress.isComplete { return "Bitte zuerst den Absender in den Einstellungen ergänzen." }
        if let incomplete = pending.first(where: { !$0.recipient.isComplete }) {
            return "Unvollständige Adresse für Bestellung #\(incomplete.orderID)."
        }
        if withPostage {
            if let error = postage.storageError ?? letterFlows.storageError { return error }
            if availableBatchStamps(amount: amount).count < pending.count {
                return "Für diese Auswahl werden \(pending.count) verfügbare Marken derselben Portostufe benötigt."
            }
        }
        guard bluetooth.connectionState.isReady && canPrintSelectedMaterialOverBluetooth else {
            return "Für den Sammeldruck den RW403B über Bluetooth verbinden und das Etikettenmaterial prüfen."
        }
        return nil
    }

    func startOrderBatch(withPostage: Bool, amount: String) {
        guard !shippingBusy, batchPrintIssue(withPostage: withPostage, amount: amount) == nil else { return }
        let stock = labelStockMode
        let pending = orderBatch.orders.filter { !$0.submitted }
        let stamps = withPostage ? availableBatchStamps(amount: amount) : []
        var settings: [UUID: LetterReviewSettings] = [:]
        for (index, order) in pending.enumerated() {
            settings[order.id] = letterSettings(recipient: order.recipient, note: order.packingNote,
                needsStamp: withPostage, stamp: withPostage ? stamps[index] : nil)
        }
        orderBatch.start { [unowned self] order in
            guard let input = settings[order.id], stock == labelStockMode, bluetooth.connectionState.isReady,
                  canPrintSelectedMaterialOverBluetooth else { throw BluetoothPrinterError.notConnected }
            if let stamp = input.stamp, !postage.canPrint([stamp.id]) {
                throw batchError("Die vorgesehene Briefmarke ist nicht mehr verfügbar.")
            }
            guard letterFlows.flow(order.id) == nil,
                  !jobs.jobs.contains(where: { $0.sourceFingerprint.hasPrefix("manual-address:\(order.id)|") }) else {
                throw batchError("Dieser Brief wurde bereits vorbereitet. Bitte im Label-Verlauf öffnen.")
            }
            let plan = try LetterPrintPlan.make(for: input)
            let prepared = try prepareLetter(plan, id: order.id, orderID: order.orderID)
            return { [unowned self] done in
                switch prepared {
                case .stamped(let flow):
                    batchJobID = flow.id
                    letterFlowController.start(flow.id) { [unowned self] in
                        batchJobID = nil
                        let saved = letterFlows.flow(flow.id)
                        if saved?.stage == .completed { done(.success(())) }
                        else { done(.failure(batchError(saved?.errorMessage ?? letterFlowController.message ?? "Druckbestätigung fehlt."))) }
                    }
                case .address(let job):
                    batchJobID = job.id
                    printJob(job) { [unowned self] result in
                        batchJobID = nil
                        done(result)
                    }
                }
            }
        }
    }

    private func batchError(_ message: String) -> NSError {
        NSError(domain: "Sammeldruck", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
