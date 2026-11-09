import Foundation
import LabelCore

@MainActor
private final class FlowHarness {
    let postage: PostageStampStore
    let store: LetterFlowStore
    let directory: URL
    let fixture: URL
    var ready = true
    var requested: [UUID] = []
    var requestedFormats: [LabelFormat] = []
    var pending: [(Result<Void, Error>) -> Void] = []
    lazy var controller = LetterFlowController(store: store, postage: postage,
        isReady: { [unowned self] in ready },
        printJob: { [unowned self] job, owner, completion in
            requested.append(job.id)
            requestedFormats.append(job.resolvedLabelFormat)
            if let ids = job.postageStampIDs {
                precondition(postage.canPrint(ids, reservationID: owner))
                postage.update(ids, status: .printing)
            }
            pending.append { [unowned self] result in
                if case .failure = result, let ids = job.postageStampIDs { postage.update(ids, status: .checkPrint) }
                completion(result)
            }
        })

    init(fixture: URL, directory: URL) throws {
        self.fixture = fixture; self.directory = directory
        postage = PostageStampStore(directory: directory.appendingPathComponent("postage"))
        store = LetterFlowStore(directory: directory.appendingPathComponent("flows"))
        try postage.importBundle(fixture)
    }

    func makeFlow(format: LabelFormat = .product100x50, stampFormat: LabelFormat? = nil) throws -> LetterShipmentFlow {
        let stamp = postage.entries.first { $0.status == .available }!.stamp
        let id = UUID()
        let address = PrintJob(sourceURL: fixture, sourceFingerprint: "address-\(id)", labelFormat: format, letterFlowID: id)
        let mark = PrintJob(sourceURL: fixture, sourceFingerprint: "stamp-\(id)", labelFormat: stampFormat ?? format,
                            postageStampIDs: [stamp.id], letterFlowID: id)
        let flow = LetterShipmentFlow(id: id, recipientName: "Testempfänger", orderID: "test-order", stamp: stamp,
                                      addressJob: address, stampJob: mark)
        try store.add(flow)
        return flow
    }

    func finish(_ result: Result<Void, Error>) throws {
        try require(!pending.isEmpty, "Flow scheduled no pending print")
        pending.removeFirst()(result)
    }

    func completedFlow() throws -> LetterShipmentFlow {
        let flow = try makeFlow()
        controller.start(flow.id)
        try finish(.success(()))
        try finish(.success(()))
        requested = []
        requestedFormats = []
        return store.flow(flow.id)!
    }
}

func runLetterFlowTests(fixture: URL, directory: URL) throws {
    try MainActor.assumeIsolated {
        try runLetterReprintTests(fixture: fixture, directory: directory.appendingPathComponent("reprints"))
        try runCombinedFlowTests(fixture: fixture, directory: directory.appendingPathComponent("combined"))
        let success = try FlowHarness(fixture: fixture, directory: directory.appendingPathComponent("success"))
        let flow = try success.makeFlow()
        success.controller.start(flow.id)
        try require(success.requested == [flow.addressJob.id], "Flow must send address first")
        try require(!success.postage.canPrint([flow.stamp.id]), "Reserved stamp leaked into ordinary bundle printing")
        try require(!success.postage.reserve(flow.stamp.id, for: UUID()), "Another flow stole the reserved stamp")
        success.controller.start(flow.id)
        try require(success.requested.count == 1, "Double-click submitted a duplicate address")
        try success.finish(.success(()))
        try require(success.requested == [flow.addressJob.id, flow.stampJob.id], "Stamp must follow confirmed address")
        try success.finish(.success(()))
        try require(success.store.flow(flow.id)?.stage == .completed && success.controller.activeFlowID == nil, "Successful flow did not finish")
        try require(success.postage.entries.first { $0.id == flow.stamp.id }?.status == .printed, "Used stamp did not enter print history")
        try require(success.store.flow(flow.id)?.stamp.trackingNumber == flow.stamp.trackingNumber, "Tracking number lost its recipient/order association")
        success.controller.start(flow.id)
        try require(success.requested.count == 2, "Completed flow was reprinted")

        let continuous = try FlowHarness(fixture: fixture, directory: directory.appendingPathComponent("continuous"))
        let addressFormat = LabelFormat.continuous(heightMM: 33)
        let stampFormat = LabelFormat.continuous(heightMM: 26)
        let continuousFlow = try continuous.makeFlow(format: addressFormat, stampFormat: stampFormat)
        let savedFlow = LetterFlowStore(directory: continuous.directory.appendingPathComponent("flows")).flow(continuousFlow.id)
        try require(savedFlow?.addressJob.resolvedLabelFormat == addressFormat && savedFlow?.stampJob.resolvedLabelFormat == stampFormat,
                    "Restoring a combined flow lost the independent address and stamp lengths")
        continuous.ready = MunbynFirmwareCapabilities.canPrint(.continuous, firmware: "1.1.48")
        continuous.controller.start(continuousFlow.id)
        try require(continuous.requested.isEmpty && continuous.postage.canPrint([continuousFlow.stamp.id]),
                    "Unsupported continuous firmware must not print or reserve postage")
        continuous.ready = MunbynFirmwareCapabilities.canPrint(.continuous, firmware: "1.1.49")
        continuous.controller.start(continuousFlow.id)
        try continuous.finish(.success(()))
        try require(continuous.requested == [continuousFlow.addressJob.id, continuousFlow.stampJob.id],
                    "Supported continuous flow must proceed from confirmed address to stamp")
        try require(continuous.requestedFormats == [addressFormat, stampFormat],
                    "Combined printing replaced the stamp's compact length with the address length")
        try continuous.finish(.success(()))
        try require(continuous.store.flow(continuousFlow.id)?.stage == .completed && !continuous.postage.canPrint([continuousFlow.stamp.id]),
                    "Continuous stamp must keep the same one-use ledger guarantees")

        let failedAddress = try FlowHarness(fixture: fixture, directory: directory.appendingPathComponent("address-failure"))
        let a = try failedAddress.makeFlow()
        failedAddress.controller.start(a.id)
        try failedAddress.finish(.failure(SelfTestFailure.assertion("simulated address interruption")))
        try require(failedAddress.store.flow(a.id)?.stage == .addressCheck && failedAddress.requested.count == 1, "Address failure must stop before postage")
        failedAddress.controller.resolveAddress(a.id, alreadyPrinted: true)
        try require(failedAddress.requested == [a.addressJob.id, a.stampJob.id], "Confirmed address was printed a second time during recovery")
        try failedAddress.finish(.success(()))

        let disconnected = try FlowHarness(fixture: fixture, directory: directory.appendingPathComponent("disconnect"))
        let d = try disconnected.makeFlow()
        disconnected.ready = false
        disconnected.controller.start(d.id)
        try require(disconnected.requested.isEmpty && disconnected.postage.canPrint([d.stamp.id]), "Preflight failure reserved or printed a stamp")
        disconnected.ready = true
        disconnected.controller.start(d.id)
        disconnected.ready = false
        try disconnected.finish(.success(()))
        try require(disconnected.requested.count == 1 && disconnected.store.flow(d.id)?.stage == .addressPrinted, "Disconnected stamp step did not preserve confirmed address")
        disconnected.ready = true
        disconnected.controller.start(d.id)
        try require(disconnected.requested == [d.addressJob.id, d.stampJob.id], "Resume after disconnect duplicated the address")
        try disconnected.finish(.success(()))

        let failedStamp = try FlowHarness(fixture: fixture, directory: directory.appendingPathComponent("stamp-failure"))
        let s = try failedStamp.makeFlow()
        failedStamp.controller.start(s.id)
        try failedStamp.finish(.success(()))
        try failedStamp.finish(.failure(SelfTestFailure.assertion("simulated stamp interruption")))
        try require(failedStamp.store.flow(s.id)?.stage == .stampCheck, "Ambiguous stamp failure must require review")
        failedStamp.controller.start(s.id)
        try require(failedStamp.requested.count == 2, "Ambiguous stamp was retried without review")
        failedStamp.controller.resolveStamp(s.id, alreadyPrinted: false)
        try require(failedStamp.requested == [s.addressJob.id, s.stampJob.id, s.stampJob.id], "Stamp-only retry printed another address")
        try failedStamp.finish(.success(()))

        let interrupted = try FlowHarness(fixture: fixture, directory: directory.appendingPathComponent("restart"))
        let r = try interrupted.makeFlow()
        interrupted.controller.start(r.id)
        try interrupted.finish(.success(()))
        let restoredPostage = PostageStampStore(directory: interrupted.directory.appendingPathComponent("postage"))
        let restoredFlows = LetterFlowStore(directory: interrupted.directory.appendingPathComponent("flows"))
        var recoveryPrints = 0
        let restored = LetterFlowController(store: restoredFlows, postage: restoredPostage, isReady: { true },
                                           printJob: { _, _, _ in recoveryPrints += 1 })
        try require(restoredFlows.flow(r.id)?.stage == .stampCheck, "Restart during stamp print must require review")
        restored.start(r.id)
        try require(recoveryPrints == 0, "Restart automatically reprinted an uncertain stamp")
        restored.resolveStamp(r.id, alreadyPrinted: true)
        try require(restoredFlows.flow(r.id)?.stage == .completed && recoveryPrints == 0, "Confirming existing stamp submitted a new print")

        let interruptedAddress = try FlowHarness(fixture: fixture, directory: directory.appendingPathComponent("restart-address"))
        let ra = try interruptedAddress.makeFlow()
        interruptedAddress.controller.start(ra.id)
        let restoredAddress = LetterFlowStore(directory: interruptedAddress.directory.appendingPathComponent("flows"))
        try require(restoredAddress.flow(ra.id)?.stage == .addressCheck, "Restart during address print must require review")

        let writeFailure = try FlowHarness(fixture: fixture, directory: directory.appendingPathComponent("save-failure"))
        let w = try writeFailure.makeFlow()
        let blockedDirectory = writeFailure.directory.appendingPathComponent("flows")
        try FileManager.default.removeItem(at: blockedDirectory)
        try Data("not a directory".utf8).write(to: blockedDirectory)
        writeFailure.controller.start(w.id)
        try require(writeFailure.requested.isEmpty && writeFailure.store.storageError != nil, "Flow printed without saving its pre-print checkpoint")
    }
    print("Letter flow tests passed: sequencing, reservations, double-clicks, disconnects, partial failures, restart recovery and checkpoint failures")
}

@MainActor
private func runLetterReprintTests(fixture: URL, directory: URL) throws {
        for selection in LetterShipmentFlow.ReprintSelection.allCases {
            let harness = try FlowHarness(fixture: fixture, directory: directory.appendingPathComponent(selection.rawValue))
            let flow = try harness.completedFlow()
            let originalCount = harness.postage.entries.first { $0.id == flow.stamp.id }!.printCount
            harness.controller.reprint(flow.id, selection: selection)
            harness.controller.reprint(flow.id, selection: selection)
            try require(harness.requested.count == 1, "Repeated reprint clicks submitted multiple jobs")
            try require(!harness.postage.canPrint([flow.stamp.id]), "Reprinting released postage into ordinary stock")
            try harness.finish(.success(()))
            if selection == .both { try harness.finish(.success(())) }
            let expected = selection == .address ? [flow.addressJob.id] : selection == .stamp ? [flow.stampJob.id] : [flow.addressJob.id, flow.stampJob.id]
            try require(harness.requested == expected, "Reprint selection printed the wrong labels")
            try require(harness.store.flow(flow.id)?.stage == .completed, "Reprint failed to finish")
            let entry = harness.postage.entries.first { $0.id == flow.stamp.id }!
            try require(entry.status == .printed && entry.reservationID == flow.id, "Reprint lost original stamp association")
            try require(entry.printCount == (originalCount ?? 0) + (selection == .address ? 0 : 1), "Reprint altered the wrong postage history")
            let restored = LetterFlowStore(directory: harness.directory.appendingPathComponent("flows")).flow(flow.id)
            try require(restored?.reprintSelection == selection && restored?.createdAt == flow.createdAt &&
                        restored?.stamp == flow.stamp && restored?.addressJob == flow.addressJob && restored?.stampJob == flow.stampJob,
                        "Reprint did not persist selection and original jobs")
        }

        let addressFailure = try FlowHarness(fixture: fixture, directory: directory.appendingPathComponent("address-failure"))
        let address = try addressFailure.completedFlow()
        addressFailure.controller.reprint(address.id, selection: .address)
        try addressFailure.finish(.failure(SelfTestFailure.assertion("address reprint interrupted")))
        try require(addressFailure.store.flow(address.id)?.stage == .addressCheck, "Address reprint failure skipped review")
        addressFailure.controller.resolveAddress(address.id, alreadyPrinted: false)
        try addressFailure.finish(.success(()))
        try require(addressFailure.requested == [address.addressJob.id, address.addressJob.id], "Address retry printed a paid stamp")

        let interrupted = try FlowHarness(fixture: fixture, directory: directory.appendingPathComponent("address-restart"))
        let restarting = try interrupted.completedFlow()
        interrupted.controller.reprint(restarting.id, selection: .address)
        let restoredStore = LetterFlowStore(directory: interrupted.directory.appendingPathComponent("flows"))
        let restoredPostage = PostageStampStore(directory: interrupted.directory.appendingPathComponent("postage"))
        var recoveryPrints = 0
        let restoredController = LetterFlowController(store: restoredStore, postage: restoredPostage, isReady: { true },
                                                      printJob: { _, _, _ in recoveryPrints += 1 })
        try require(restoredStore.flow(restarting.id)?.stage == .addressCheck, "Restart lost address reprint checkpoint")
        restoredController.start(restarting.id)
        try require(recoveryPrints == 0, "Restart automatically retried an ambiguous address")
        restoredController.resolveAddress(restarting.id, alreadyPrinted: true)
        try require(recoveryPrints == 0 && restoredStore.flow(restarting.id)?.stage == .completed,
                    "Confirming address-only reprint incorrectly printed postage")

        let bothFailure = try FlowHarness(fixture: fixture, directory: directory.appendingPathComponent("both-failure"))
        let both = try bothFailure.completedFlow()
        bothFailure.controller.reprint(both.id, selection: .both)
        try bothFailure.finish(.success(()))
        try bothFailure.finish(.failure(SelfTestFailure.assertion("stamp reprint interrupted")))
        bothFailure.controller.start(both.id)
        try require(bothFailure.requested.count == 2 && bothFailure.store.flow(both.id)?.stage == .stampCheck,
                    "Ambiguous reprint must not retry automatically")
        bothFailure.controller.resolveStamp(both.id, alreadyPrinted: false)
        try bothFailure.finish(.success(()))
        try require(bothFailure.requested == [both.addressJob.id, both.stampJob.id, both.stampJob.id],
                    "Stamp recovery duplicated the already reprinted address")

        let offline = try FlowHarness(fixture: fixture, directory: directory.appendingPathComponent("offline"))
        let offlineFlow = try offline.completedFlow()
        offline.ready = false
        offline.controller.reprint(offlineFlow.id, selection: .both)
        try require(offline.requested.isEmpty && offline.store.flow(offlineFlow.id)?.stage == .completed &&
                    offline.postage.canReprint(offlineFlow.stamp.id, for: offlineFlow.id),
                    "Offline reprint changed the completed flow or stamp")

        let reassigned = try FlowHarness(fixture: fixture, directory: directory.appendingPathComponent("reassigned"))
        let old = try reassigned.completedFlow()
        try require(reassigned.postage.reuse([old.stamp.id]), "Cannot prepare reassigned-stamp fixture")
        let other = UUID()
        try require(reassigned.postage.reserve(old.stamp.id, for: other), "Cannot reserve stamp for another flow")
        reassigned.controller.reprint(old.id, selection: .stamp)
        try require(reassigned.requested.isEmpty && reassigned.controller.message != nil, "Reprint stole another flow's stamp")
        reassigned.controller.reprint(old.id, selection: .address)
        try reassigned.finish(.success(()))
        try require(reassigned.postage.entries.first { $0.id == old.stamp.id }?.reservationID == other,
                    "Address-only reprint modified another flow's reservation")

        let missingFixture = directory.appendingPathComponent("missing-job.pdf")
        try FileManager.default.copyItem(at: fixture, to: missingFixture)
        let missing = try FlowHarness(fixture: missingFixture, directory: directory.appendingPathComponent("missing"))
        let missingFlow = try missing.completedFlow()
        try FileManager.default.removeItem(at: missingFixture)
        missing.controller.reprint(missingFlow.id, selection: .both)
        try require(missing.requested.isEmpty && missing.store.flow(missingFlow.id)?.stage == .completed &&
                    missing.controller.message != nil, "Missing PDF started a reprint")

        let writeFailure = try FlowHarness(fixture: fixture, directory: directory.appendingPathComponent("write-failure"))
        let unwritable = try writeFailure.completedFlow()
        let storeDirectory = writeFailure.directory.appendingPathComponent("flows")
        try FileManager.default.removeItem(at: storeDirectory)
        try Data("blocked".utf8).write(to: storeDirectory)
        writeFailure.controller.reprint(unwritable.id, selection: .both)
        try require(writeFailure.requested.isEmpty && writeFailure.postage.canReprint(unwritable.stamp.id, for: unwritable.id),
                    "Reprint reserved or printed postage without a saved checkpoint")
        let stampRestart = try FlowHarness(fixture: fixture, directory: directory.appendingPathComponent("stamp-restart"))
        let sr = try stampRestart.completedFlow()
        stampRestart.controller.reprint(sr.id, selection: .stamp)
        let restoredStampStore = LetterFlowStore(directory: stampRestart.directory.appendingPathComponent("flows"))
        let restoredStampPostage = PostageStampStore(directory: stampRestart.directory.appendingPathComponent("postage"))
        var stampRecoveryPrints = 0
        let stampController = LetterFlowController(store: restoredStampStore, postage: restoredStampPostage, isReady: { true },
                                                   printJob: { _, _, _ in stampRecoveryPrints += 1 })
        try require(restoredStampStore.flow(sr.id)?.stage == .stampCheck && restoredStampStore.flow(sr.id)?.reprintSelection == .stamp,
                    "Old successful stamp print incorrectly completed an interrupted reprint")
        stampController.start(sr.id)
        try require(stampRecoveryPrints == 0, "Restart retried an ambiguous paid-stamp reprint")
        stampController.resolveStamp(sr.id, alreadyPrinted: true)
        try require(restoredStampStore.flow(sr.id)?.stage == .completed &&
                    restoredStampPostage.entries.first { $0.id == sr.stamp.id }?.printCount == 2,
                    "Confirmed reprint did not preserve print history")

        let ledgerFailure = try FlowHarness(fixture: fixture, directory: directory.appendingPathComponent("ledger-failure"))
        let lf = try ledgerFailure.completedFlow()
        let ledgerDirectory = ledgerFailure.directory.appendingPathComponent("postage")
        try FileManager.default.removeItem(at: ledgerDirectory)
        try Data("blocked".utf8).write(to: ledgerDirectory)
        ledgerFailure.controller.reprint(lf.id, selection: .both)
        try require(ledgerFailure.requested.isEmpty && ledgerFailure.postage.storageError != nil,
                    "Reprint started before saving its exclusive postage reservation")
        print("Letter reprint tests passed: all selections, ownership, history, duplicate clicks, recovery, offline and persistence guards")
}

@MainActor
private func runCombinedFlowTests(fixture: URL, directory: URL) throws {
    let harness = try FlowHarness(fixture: fixture, directory: directory)
    func makeFlow() throws -> LetterShipmentFlow {
        let stamp = harness.postage.entries.first { $0.status == .available }!.stamp
        let id = UUID()
        let job = PrintJob(sourceURL: fixture, sourceFingerprint: "combined-\(id)", labelFormat: .product100x50,
                           postageStampIDs: [stamp.id], letterFlowID: id)
        let flow = LetterShipmentFlow(id: id, recipientName: "Testempfänger", orderID: nil, stamp: stamp,
                                      addressJob: job, stampJob: job, stage: .addressPrinted, isCombined: true)
        try harness.store.add(flow)
        return flow
    }

    let flow = try makeFlow()
    try require(flow.statusTitle == "Bereit", "A combined label must not claim a printed address")
    harness.controller.start(flow.id)
    harness.controller.start(flow.id)
    try require(harness.requested == [flow.stampJob.id], "Combined label must print exactly one job")
    try require(!harness.postage.canPrint([flow.stamp.id]), "Combined label did not reserve its stamp")
    try harness.finish(.success(()))
    try require(harness.store.flow(flow.id)?.stage == .completed && harness.pending.isEmpty, "Combined label did not complete after one print")
    try require(harness.postage.entries.first { $0.id == flow.stamp.id }?.status == .printed, "Combined label did not use up its stamp")

    harness.requested = []
    harness.controller.reprint(flow.id, selection: .stamp)
    try require(harness.requested == [flow.stampJob.id], "Combined reprint must print the one label")
    try harness.finish(.success(()))
    try require(harness.store.flow(flow.id)?.stage == .completed, "Combined reprint did not complete")

    let failing = try makeFlow()
    harness.requested = []
    harness.controller.start(failing.id)
    try harness.finish(.failure(NSError(domain: "Test", code: 1)))
    try require(harness.store.flow(failing.id)?.stage == .stampCheck, "A failed combined print must require a review of the stamp")

    let encoded = try JSONEncoder().encode(flow)
    let restored = try JSONDecoder().decode(LetterShipmentFlow.self, from: encoded)
    try require(restored.isCombined, "Combined flag was lost on restart")
    let normal = try harness.makeFlow()
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(normal)) as! [String: Any]
    json.removeValue(forKey: "combined")
    let legacy = try JSONDecoder().decode(LetterShipmentFlow.self, from: JSONSerialization.data(withJSONObject: json))
    try require(!legacy.isCombined, "Existing letter flows must stay two labels")
}
