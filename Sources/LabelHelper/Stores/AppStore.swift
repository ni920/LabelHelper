import AppKit
import Combine
import Foundation
import LabelCore
import UniformTypeIdentifiers

@MainActor
final class AppStore: ObservableObject {
    enum LabelStockMode: String, CaseIterable, Identifiable {
        case dieCut
        case continuous100

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dieCut: "Vorgestanzte Etiketten"
            case .continuous100: "Endlosrolle 100 mm"
            }
        }
    }

    enum FileImport: Equatable {
        case label, dhl, postage, etsyCSV

        var contentTypes: [UTType] {
            switch self {
            case .label: [.pdf, .png, .jpeg]
            case .dhl, .postage: [.pdf]
            case .etsyCSV: [.commaSeparatedText]
            }
        }
    }

    private enum ImportRequest {
        case file(FileImport)
        case browser(BrowserOrderPayload)
        case browserBatch([BrowserOrderPayload])
    }

    @Published var showPrinterConnection = false
    @Published private(set) var homeRequestSequence = 0
    @Published private(set) var draftHomeSequence = 0
    @Published private(set) var historyRequestSequence = 0
    @Published private(set) var shippingImportSequence = 0
    @Published private(set) var labelImportSequence = 0
    @Published private(set) var lastImportedLabelJobID: UUID?
    @Published private(set) var postageImportSucceeded = false
    @Published var showImporter = false
    @Published private(set) var fileImport: FileImport?
    private var pendingImports: [ImportRequest] = []
    private var dismissingPreviewForImport = false
    @Published private(set) var parcelImportError: String?
    @Published var postagePreview: PostagePrintBatch?
    @Published var letterFlowPreview: LetterShipmentFlow?
    @Published var selectedLetterPostageID = ""
    @Published var letterWithPostage = true
    @Published private(set) var draftLetterFlowID: UUID?
    @Published private(set) var draftAddressJobID: UUID?
    @Published var selectedPostageIDs: Set<String> = []
    @Published private(set) var postageImportSequence = 0
    @Published private(set) var printInProgress = false
    @Published private(set) var printingPostageBatch = false
    @Published private(set) var postageBatchProgress = ""
    @Published private(set) var finishedPostageBatchID: UUID?
    private var runningPostageBatchID: UUID?
    private var postageBatchRemaining: [PrintJob] = []
    private var postageBatchTotal = 0
    private var postageBatchCompleted = 0
    private var stopPostageBatch = false
    @Published var showEtsyImportReview = false
    @Published var showEtsyImportError = false
    @Published var showBrowserOrderReview = false
    @Published var lastMessage: String?
    @Published var historyExportError: String?
    @Published var previewJob: PrintJob?
    @Published var selectedShipmentKind: ShipmentKind {
        didSet {
            defaults.set(selectedShipmentKind.rawValue, forKey: Keys.selectedShipmentKind)
        }
    }
    @Published var speed = 4
    @Published var density = 8
    @Published var labelStockMode: LabelStockMode {
        didSet { defaults.set(labelStockMode.rawValue, forKey: Keys.labelStockMode) }
    }
    @Published var letterFormatID: String {
        didSet {
            defaults.set(letterFormatID, forKey: Keys.lastLetterFormatID)
            defaults.set(letterFormatID, forKey: Keys.selectedFormatID)
        }
    }
    @Published var customWidthMM: Double {
        didSet { defaults.set(customWidthMM, forKey: Keys.customWidthMM) }
    }
    @Published var customHeightMM: Double {
        didSet { defaults.set(customHeightMM, forKey: Keys.customHeightMM) }
    }
    @Published var senderName: String {
        didSet { defaults.set(senderName, forKey: Keys.senderName) }
    }
    @Published var senderStreet: String {
        didSet { defaults.set(senderStreet, forKey: Keys.senderStreet) }
    }
    @Published var senderPostalCode: String {
        didSet { defaults.set(senderPostalCode, forKey: Keys.senderPostalCode) }
    }
    @Published var senderCity: String {
        didSet { defaults.set(senderCity, forKey: Keys.senderCity) }
    }
    @Published var senderCountry: String {
        didSet { defaults.set(senderCountry, forKey: Keys.senderCountry) }
    }
    @Published var addressLabelDesign: AddressLabelDesign {
        didSet { defaults.set(try? JSONEncoder().encode(addressLabelDesign), forKey: Keys.addressLabelDesign) }
    }
    @Published var postageStampPlacement: PostageStampPlacement {
        didSet { defaults.set(try? JSONEncoder().encode(postageStampPlacement), forKey: Keys.postageStampPlacement) }
    }
    @Published var combinedLabel: CombinedLabelSettings {
        didSet { defaults.set(try? JSONEncoder().encode(combinedLabel), forKey: Keys.combinedLabel) }
    }
    @Published var continuousExtraFeedMM: Double {
        didSet { defaults.set(continuousExtraFeedMM, forKey: Keys.continuousExtraFeedMM) }
    }
    @Published var recipientName = ""
    @Published var recipientStreet1 = ""
    @Published var recipientStreet2 = ""
    @Published var recipientPostalCode = ""
    @Published var recipientCity = ""
    @Published var recipientCountry = "Deutschland"
    @Published private(set) var pendingEtsyOrders: [EtsyOrder] = []
    @Published private(set) var incomingBrowserOrder: BrowserOrderPayload?
    @Published var packingNote = ""
    @Published private(set) var activeBrowserOrder: BrowserOrderPayload?
    @Published private(set) var activeCSVOrderID: String?

    let bluetooth = BluetoothPrinterService()
    let orderBatch: OrderBatchStore
    @Published var showOrderBatch = false
    var reviewBatchAfterCSV = false
    var batchJobID: UUID?
    let jobs: PrintJobStore
    let postage: PostageStampStore
    let letterFlows: LetterFlowStore
    let labelHistory: LabelHistoryStore
    let applicationDataLocation: ApplicationDataLocation
    lazy var letterFlowController = LetterFlowController(
        store: letterFlows, postage: postage,
        isReady: { [weak self] in
            guard let self else { return false }
            return self.bluetooth.connectionState.isReady && self.canPrintSelectedMaterialOverBluetooth && !self.printInProgress && !self.printingPostageBatch
        },
        printJob: { [weak self] job, flowID, completion in
            self?.printJob(job, letterFlowID: flowID, completion: completion)
        }
    )
    private let defaults: UserDefaults
    private var batchObservation: AnyCancellable?
    private var postageObservation: AnyCancellable?

    private enum Keys {
        static let selectedFormatID = "selectedLabelFormatID"
        static let lastLetterFormatID = "lastLetterLabelFormatID"
        static let selectedShipmentKind = "selectedShipmentKind"
        static let labelStockMode = "labelStockMode"
        static let customWidthMM = "customLabelWidthMM"
        static let customHeightMM = "customLabelHeightMM"
        static let senderName = "senderName"
        static let senderStreet = "senderStreet"
        static let senderPostalCode = "senderPostalCode"
        static let senderCity = "senderCity"
        static let senderCountry = "senderCountry"
        static let addressLabelDesign = "addressLabelDesign"
        static let postageStampPlacement = "postageStampPlacement"
        static let combinedLabel = "combinedLabel"
        static let continuousExtraFeedMM = "continuousExtraFeedMM"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        applicationDataLocation = ApplicationDataManager.prepareDefaultLocation()
        let root = applicationDataLocation.rootURL
        orderBatch = OrderBatchStore(directory: root)
        jobs = PrintJobStore(directory: root)
        postage = PostageStampStore(directory: root.appendingPathComponent("Briefmarken", isDirectory: true))
        letterFlows = LetterFlowStore(directory: root.appendingPathComponent("Briefversand", isDirectory: true))
        let history = LabelHistoryStore(directory: root.appendingPathComponent("Labelverlauf", isDirectory: true))
        history.adopt(jobs.jobs)
        jobs.onStatusChange = { [weak history] id, status, errorMessage in
            history?.updateStatus(id, status: status, errorMessage: errorMessage)
        }
        labelHistory = history
        let initialShipmentKind = ShipmentKind(
            rawValue: defaults.string(forKey: Keys.selectedShipmentKind) ?? ""
        ) ?? .letter
        selectedShipmentKind = initialShipmentKind
        labelStockMode = LabelStockMode(
            rawValue: defaults.string(forKey: Keys.labelStockMode) ?? ""
        ) ?? .dieCut
        let storedLetterFormatID = defaults.string(forKey: Keys.lastLetterFormatID)
            ?? defaults.string(forKey: Keys.selectedFormatID)
        letterFormatID = LabelFormat.normalizedLetterFormatID(storedLetterFormatID)
        customWidthMM = defaults.object(forKey: Keys.customWidthMM) as? Double ?? 89
        customHeightMM = defaults.object(forKey: Keys.customHeightMM) as? Double ?? 36
        senderName = defaults.string(forKey: Keys.senderName) ?? ""
        senderStreet = defaults.string(forKey: Keys.senderStreet) ?? ""
        senderPostalCode = defaults.string(forKey: Keys.senderPostalCode) ?? ""
        senderCity = defaults.string(forKey: Keys.senderCity) ?? ""
        senderCountry = defaults.string(forKey: Keys.senderCountry) ?? "Deutschland"
        addressLabelDesign = defaults.data(forKey: Keys.addressLabelDesign)
            .flatMap { try? JSONDecoder().decode(AddressLabelDesign.self, from: $0) } ?? .standard
        postageStampPlacement = defaults.data(forKey: Keys.postageStampPlacement)
            .flatMap { try? JSONDecoder().decode(PostageStampPlacement.self, from: $0) } ?? .standard
        combinedLabel = defaults.data(forKey: Keys.combinedLabel)
            .flatMap { try? JSONDecoder().decode(CombinedLabelSettings.self, from: $0) } ?? .standard
        continuousExtraFeedMM = defaults.double(forKey: Keys.continuousExtraFeedMM)
        lastMessage = applicationDataLocation.warning ?? (applicationDataLocation.migratedLegacyData
            ? "Die lokalen App-Daten wurden sicher in den neuen Label-Helper-Ordner verschoben."
            : nil)
        batchObservation = orderBatch.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        postageObservation = postage.$entries.sink { [weak self] entries in
            self?.selectAvailablePostage(in: entries)
        }
    }

    private func selectAvailablePostage(in entries: [PostageStampStore.Entry]) {
        let previous = entries.first { $0.id == selectedLetterPostageID }
        guard previous?.status != .available else { return }
        let available = entries.filter { $0.status == .available }
        let next = available.first { $0.stamp.amount == previous?.stamp.amount } ?? available.first
        let id = next?.id ?? ""
        if selectedLetterPostageID != id { selectedLetterPostageID = id }
    }

    var canManageApplicationData: Bool {
        !shippingBusy
    }

    var selectedLabelFormat: LabelFormat {
        selectedShipmentKind == .parcel ? .shipping100x150 : selectedLetterLabelFormat
    }

    var selectedPaperType: MunbynPaperType {
        labelStockMode == .continuous100 ? .continuous : .gap
    }

    var canPrintSelectedMaterialOverBluetooth: Bool {
        labelStockMode != .continuous100 || bluetooth.supportsContinuousStock
    }

    var postageFormats: [LabelFormat] {
        if labelStockMode == .continuous100 {
            return [.shipping100x150]
        }
        return [.shipping100x150, .product100x50, .address89x36, .address70x36, .square50]
    }

    func postageFormat(for id: String) -> LabelFormat {
        postageFormats.first { $0.id == id } ?? .shipping100x150
    }

    func printedLabelFormat(_ contentFormat: LabelFormat) -> LabelFormat {
        labelStockMode == .continuous100 && !contentFormat.includesCutGuide
            ? ContinuousLabelCutGuide.printFormat(for: contentFormat, additionalFeedMM: continuousExtraFeedMM)
            : contentFormat
    }

    func applyingMaterialCutGuide(to raster: LabelRaster) -> LabelRaster {
        labelStockMode == .continuous100
            ? ContinuousLabelCutGuide.applying(to: raster, additionalFeedMM: continuousExtraFeedMM)
            : raster
    }

    func renderLabel(_ job: PrintJob) throws -> LabelRaster {
        let raster = try LabelRenderer.render(url: job.sourceURL, format: job.resolvedLabelFormat)
        return job.resolvedLabelFormat.includesCutGuide ? raster : applyingMaterialCutGuide(to: raster)
    }

    var selectedLetterLabelFormat: LabelFormat { letterFormat(for: recipientAddress) }

    func letterFormat(for recipient: RecipientAddress) -> LabelFormat {
        if labelStockMode == .continuous100 {
            return EtsyAddressLabelWriter.continuousFormat(recipient: recipient, sender: senderAddress, design: addressLabelDesign)
        }
        if letterFormatID == "custom" {
            return .custom(widthMM: customWidthMM, heightMM: customHeightMM)
        }
        return LabelFormat.letterPresets.first(where: { $0.id == letterFormatID }) ?? .address89x36
    }

    var selectedLetterPostageFormat: LabelFormat {
        labelStockMode == .continuous100 ? .shipping100x150 : selectedLetterLabelFormat
    }

    var senderAddress: SenderAddress {
        SenderAddress(
            name: senderName,
            street: senderStreet,
            postalCode: senderPostalCode,
            city: senderCity,
            country: senderCountry
        )
    }

    var recipientAddress: RecipientAddress {
        RecipientAddress(
            name: recipientName,
            street1: recipientStreet1,
            street2: recipientStreet2,
            postalCode: recipientPostalCode,
            city: recipientCity,
            country: recipientCountry
        )
    }

    func importFiles(_ urls: [URL]) {
        var lastImportedJob: PrintJob?
        for url in urls {
            if url.pathExtension.lowercased() == "csv" {
                loadEtsyCSV(url)
                continue
            }
            if url.pathExtension.lowercased() == "pdf",
               (try? PostagePDFService.readStamps(from: url))?.isEmpty == false {
                importPostageBundle(url)
                continue
            }
            do {
                // Imported artwork must not inherit a height measured from the address editor.
                let importFormat = selectedLabelFormat.usesAutomaticHeight ? LabelFormat.continuousLetter100x55 : selectedLabelFormat
                let job = try jobs.enqueue(url: url, labelFormat: importFormat)
                recordImportedLabel(job)
                lastImportedJob = job
                lastMessage = job.status == .printed
                    ? "Dieses Etikett wurde bereits gedruckt."
                    : "\(url.lastPathComponent) ist druckbereit."
            } catch {
                lastMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
            }
        }

        if let lastImportedJob {
            presentPrintPreview(lastImportedJob)
        }
    }

    private func recordImportedLabel(_ job: PrintJob, parcelInfo: ParcelLabelInfo? = nil, linksCurrentOrder: Bool = false) {
        guard !labelHistory.records.contains(where: { $0.id == job.id }) else { return }
        let info = parcelInfo ?? ParcelLabelParser.parse(url: job.sourceURL)
        let address = info?.addressLines.map(Self.normalizedName).joined()
        let sameRecipient = address == recipientAddress.lines.map(Self.normalizedName).joined()
        let orderID = linksCurrentOrder && sameRecipient ? activeBrowserOrder?.orderID ?? activeCSVOrderID : nil
        if let record = LabelHistoryRecord(job: job, parcelInfo: info, orderID: orderID) {
            labelHistory.add(record)
        }
    }

    private static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .filter { !$0.isWhitespace }
    }

    func handleIncomingURL(_ url: URL) {
        do {
            if url.host?.lowercased() == BrowserOrderLink.batchHost {
                enqueueImport(.browserBatch(try BrowserOrderLink.decodeBatch(url)))
            } else {
                enqueueImport(.browser(try BrowserOrderLink.decode(url)))
            }
        } catch { lastMessage = "Browser-Import fehlgeschlagen: \(error.localizedDescription)" }
    }

    func requestFileImport(_ kind: FileImport) {
        enqueueImport(.file(kind))
    }

    private func enqueueImport(_ request: ImportRequest) {
        pendingImports.append(request)
        presentNextImport()
    }

    func presentNextImport() {
        if !shippingBusy, showOrderBatch, case .browserBatch(let orders) = pendingImports.first {
            pendingImports.removeFirst()
            collectBrowserBatch(orders)
            presentNextImport()
            return
        }
        guard !pendingImports.isEmpty, !shippingBusy, fileImport == nil, !dismissingPreviewForImport,
              !showOrderBatch, !showBrowserOrderReview, !showEtsyImportReview, !showEtsyImportError else { return }
        if previewJob != nil || letterFlowPreview != nil || postagePreview != nil {
            dismissingPreviewForImport = true
            closeShippingPreviews()
            return
        }
        switch pendingImports.removeFirst() {
        case .file(let kind):
            fileImport = kind
            showImporter = true
        case .browserBatch(let orders):
            collectBrowserBatch(orders)
        case .browser(let order):
            incomingBrowserOrder = order
            showBrowserOrderReview = true
        }
    }

    func importSheetDismissed() {
        dismissingPreviewForImport = false
        if reviewBatchAfterCSV {
            reviewBatchAfterCSV = false
            showOrderBatch = true
            return
        }
        presentNextImport()
    }

    func finishFileImport(_ result: Result<[URL], Error>? = nil) {
        guard let kind = fileImport else { return }
        showImporter = false
        // Give the system open panel time to dismiss before presenting a review.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.fileImport = nil
            switch result {
            case .success(let urls):
                switch kind {
                case .label: self.importFiles(urls)
                case .dhl: if let url = urls.first { self.importDHLLabel(url) }
                case .postage: if let url = urls.first { self.importPostageBundle(url) }
                case .etsyCSV: if let url = urls.first { self.loadEtsyCSV(url) }
                }
            case .failure(let error):
                if kind == .dhl { self.reportDHLImportError(error) }
                else { self.lastMessage = error.localizedDescription }
            case nil:
                break
            }
            if self.previewJob == nil { self.presentNextImport() }
        }
    }

    func acceptIncomingBrowserOrder(as shipmentKind: ShipmentKind) {
        guard !shippingBusy, let order = incomingBrowserOrder else { return }
        resetShippingDraft()
        applyRecipient(order.recipient)
        packingNote = order.packingNote ?? ""
        activeBrowserOrder = order
        activeCSVOrderID = nil
        selectedShipmentKind = shipmentKind
        shippingImportSequence &+= 1
        incomingBrowserOrder = nil
        if shipmentKind == .parcel { pendingImports.insert(.file(.dhl), at: 0) }
        showBrowserOrderReview = false
    }

    func dismissIncomingBrowserOrder() {
        incomingBrowserOrder = nil
        showBrowserOrderReview = false
    }

    func printTestLabel() {
        guard !shippingBusy else { return }
        // Keep a continuous-stock test short even if the current task is a parcel.
        let testFormat = labelStockMode == .continuous100 ? LabelFormat.continuousLetter100x55 : selectedLabelFormat
        if labelStockMode == .continuous100 && !canPrintSelectedMaterialOverBluetooth {
            printInProgress = true
            defer { printInProgress = false }
            do {
                try SystemPrinterService.print(
                    applyingMaterialCutGuide(to: LabelRenderer.testPattern(format: testFormat)),
                    format: printedLabelFormat(testFormat)
                )
                lastMessage = "Das Testetikett wurde an den macOS-Systemdruck übergeben."
            } catch {
                lastMessage = "Systemdruck fehlgeschlagen: \(error.localizedDescription)"
            }
            return
        }
        lastMessage = "Testetikett wird für den RW403B vorbereitet …"
        printInProgress = true
        bluetooth.printRaster(
            applyingMaterialCutGuide(to: LabelRenderer.testPattern(format: testFormat)),
            paperType: selectedPaperType
        ) { [weak self] result in
            self?.printInProgress = false
            switch result {
            case .success:
                self?.lastMessage = "Testetikett wurde vom RW403B gedruckt."
            case .failure(let error):
                self?.lastMessage = "Testdruck fehlgeschlagen: \(error.localizedDescription)"
            }
        }
    }

    func printJob(_ job: PrintJob, letterFlowID: UUID? = nil, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard !printInProgress, !orderBatch.running || (batchJobID != nil && (job.id == batchJobID || letterFlowID == batchJobID)) else {
            completion?(.failure(BluetoothPrinterError.transferInProgress)); return
        }
        guard (letterFlowController.activeFlowID == nil || letterFlowController.activeFlowID == letterFlowID),
              job.letterFlowID == letterFlowID else {
            lastMessage = "Dieser Auftrag gehört zu einem Briefablauf. Bitte im Bereich Briefversand öffnen."
            completion?(.failure(BluetoothPrinterError.transferInProgress)); return
        }
        if let ids = job.postageStampIDs {
            guard postage.canPrint(ids, reservationID: letterFlowID) else {
                let message = "Diese Marken sind bereits gedruckt oder ihr Ausdruck muss zuerst geprüft werden."
                lastMessage = message
                completion?(.failure(NSError(domain: "Briefmarken", code: 3, userInfo: [NSLocalizedDescriptionKey: message])))
                return
            }
            guard canPrintSelectedMaterialOverBluetooth else {
                let message = "Zum Drucken von Briefmarken auf Endlosrolle den RW403B mit Firmware ab 1.1.49 über Bluetooth verbinden."
                lastMessage = message
                completion?(.failure(NSError(domain: "Briefmarken", code: 4, userInfo: [NSLocalizedDescriptionKey: message])))
                return
            }
        }
        if labelStockMode == .continuous100 && !canPrintSelectedMaterialOverBluetooth {
            printInProgress = true
            defer { printInProgress = false }
            jobs.update(job.id, status: .printing)
            lastMessage = "macOS-Systemdruck wird vorbereitet …"
            do {
                let raster = try renderLabel(job)
                try SystemPrinterService.print(raster, format: printedLabelFormat(job.resolvedLabelFormat))
                jobs.update(job.id, status: .printed)
                lastMessage = "Das Etikett wurde an den macOS-Systemdruck übergeben."
                completion?(.success(()))
            } catch {
                jobs.update(job.id, status: .failed, errorMessage: error.localizedDescription)
                lastMessage = "Systemdruck fehlgeschlagen: \(error.localizedDescription)"
                completion?(.failure(error))
            }
            return
        }
        guard bluetooth.connectionState.isReady else {
            lastMessage = "Bitte zuerst den RW403B verbinden."
            completion?(.failure(BluetoothPrinterError.notConnected))
            return
        }

        jobs.update(job.id, status: .printing)
        lastMessage = "\(job.sourceURL.lastPathComponent) wird vorbereitet …"

        do {
            let raster = try renderLabel(job)
            if let ids = job.postageStampIDs, !postage.update(ids, status: .printing) {
                throw NSError(domain: "Briefmarken", code: 2, userInfo: [NSLocalizedDescriptionKey: postage.storageError ?? "Druckstatus konnte nicht gespeichert werden."])
            }
            printInProgress = true
            bluetooth.printRaster(raster, paperType: selectedPaperType) { [weak self] result in
                guard let self else { return }
                self.printInProgress = false
                switch result {
                case .success:
                    self.jobs.update(job.id, status: .printed)
                    self.lastMessage = "Etikett wurde vom RW403B gedruckt."
                    if let ids = job.postageStampIDs { self.postage.update(ids, status: .printed) }
                case .failure(let error):
                    self.jobs.update(job.id, status: .failed, errorMessage: error.localizedDescription)
                    self.lastMessage = "Druck fehlgeschlagen: \(error.localizedDescription)"
                    if let ids = job.postageStampIDs { self.postage.update(ids, status: .checkPrint) }
                }
                completion?(result)
            }
        } catch {
            jobs.update(job.id, status: .failed, errorMessage: error.localizedDescription)
            lastMessage = "Aufbereitung fehlgeschlagen: \(error.localizedDescription)"
            completion?(.failure(error))
        }
    }

    func importPostageBundle(_ url: URL) {
        do {
            let ids = try postage.importBundle(url)
            selectedPostageIDs = Set(ids.filter { id in postage.canPrint([id]) })
            postageImportSucceeded = true
            postageImportSequence &+= 1
            lastMessage = "\(ids.count) Briefmarken erkannt; \(selectedPostageIDs.count) davon verfügbar."
        } catch {
            postageImportSucceeded = false
            lastMessage = "Briefmarken-Import fehlgeschlagen: \(error.localizedDescription)"
            postageImportSequence &+= 1
        }
    }

    func preparePostageSheets(format: LabelFormat, cutGuides: Bool) {
        guard !shippingBusy else { return }
        let stamps = postage.entries.filter { selectedPostageIDs.contains($0.id) && $0.status == .available }.map(\.stamp)
        guard !stamps.isEmpty else { lastMessage = "Bitte verfügbare Briefmarken auswählen."; return }
        do {
            let sheets = try PostagePDFService.writeSheets(stamps: stamps, format: format, cutGuides: cutGuides,
                                                          directory: postage.directory, fitHeightToContent: labelStockMode == .continuous100,
                                                          placement: postageStampPlacement)
            let queued = try sheets.enumerated().map { index, sheet in
                try jobs.enqueue(url: sheet.url, labelFormat: sheet.format,
                                 displayName: "Briefmarken · \(sheet.stampIDs.count) Marken · Etikett \(index + 1)/\(sheets.count)",
                                 postageStampIDs: sheet.stampIDs)
            }
            postagePreview = PostagePrintBatch(jobs: queued)
        } catch { lastMessage = error.localizedDescription }
    }

    func printPostageSheets(_ batch: PostagePrintBatch) {
        guard !shippingBusy, bluetooth.connectionState.isReady,
              letterFlowController.activeFlowID == nil,
              canPrintSelectedMaterialOverBluetooth, postage.canPrint(batch.jobs.flatMap { $0.postageStampIDs ?? [] }) else {
            lastMessage = "Drucker verbinden und die Markenauswahl prüfen. Für Endlosrollen ist Firmware ab 1.1.49 erforderlich."
            return
        }
        runningPostageBatchID = batch.id
        finishedPostageBatchID = nil
        printingPostageBatch = true
        postageBatchProgress = "Druck wird vorbereitet …"
        postageBatchRemaining = batch.jobs
        postageBatchTotal = batch.jobs.count
        postageBatchCompleted = 0
        stopPostageBatch = false
        printNextPostageSheet()
    }

    func stopAfterCurrentPostageSheet() { stopPostageBatch = true }

    private func printNextPostageSheet() {
        guard !stopPostageBatch, !postageBatchRemaining.isEmpty else {
            printingPostageBatch = false
            postageBatchProgress = "\(postageBatchCompleted) von \(postageBatchTotal) Etiketten gedruckt."
            lastMessage = postageBatchProgress
            finishedPostageBatchID = runningPostageBatchID
            runningPostageBatchID = nil
            postageBatchRemaining = []
            selectedPostageIDs = Set(selectedPostageIDs.filter { postage.canPrint([$0]) })
            return
        }
        let job = postageBatchRemaining.removeFirst()
        postageBatchProgress = "Etikett \(postageBatchCompleted + 1) von \(postageBatchTotal) wird gedruckt …"
        printJob(job) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.postageBatchCompleted += 1
                self.printNextPostageSheet()
            case .failure:
                self.printingPostageBatch = false
                self.postageBatchRemaining = []
                self.postageBatchProgress = "Nach \(self.postageBatchCompleted) Etiketten angehalten. Bitte den letzten Ausdruck prüfen."
                self.lastMessage = self.postageBatchProgress
                self.finishedPostageBatchID = self.runningPostageBatchID
                self.runningPostageBatchID = nil
            }
        }
    }

    func loadEtsyCSV(_ url: URL) {
        let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            pendingEtsyOrders = try EtsyOrderCSVParser.parse(url: url)
            lastMessage = "\(pendingEtsyOrders.count) Etsy-Bestellungen wurden gefunden."
            showEtsyImportReview = !pendingEtsyOrders.isEmpty
        } catch {
            pendingEtsyOrders = []
            lastMessage = "Etsy-Import fehlgeschlagen: \(error.localizedDescription)"
            showEtsyImportError = true
        }
    }

    func applyEtsyOrder(_ order: EtsyOrder) {
        guard !shippingBusy else { return }
        resetShippingDraft()
        applyRecipient(order.recipientAddress)
        packingNote = order.packingNote ?? ""
        activeCSVOrderID = order.id
        shippingImportSequence &+= 1
        selectedShipmentKind = .letter
        showEtsyImportReview = false
        pendingEtsyOrders = []
    }

    func requestLabelImport() { requestFileImport(.label) }

    func chooseDHLLabelImport() { requestFileImport(.dhl) }

    func reportDHLImportError(_ error: Error) {
        parcelImportError = error.localizedDescription
    }

    func importDHLLabel(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard url.pathExtension.lowercased() == "pdf",
                  let info = ParcelLabelParser.recognizeShippingLabel(data: data) else {
                parcelImportError = "DHL-Paketlabel nicht erkannt. Wähle die gekaufte Versandmarke als PDF."
                return
            }
            let fingerprint = FileFingerprint.fingerprint(for: data)
            let directory = applicationDataLocation.rootURL.appendingPathComponent("Paketlabel", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let cachedURL = directory.appendingPathComponent("\(fingerprint).pdf")
            if !FileManager.default.fileExists(atPath: cachedURL.path) {
                try data.write(to: cachedURL, options: .atomic)
            }
            let job = try jobs.enqueue(url: cachedURL, labelFormat: .shipping100x150,
                                       displayName: url.lastPathComponent, sourceFingerprint: "dhl:\(fingerprint)")
            recordImportedLabel(job, parcelInfo: info, linksCurrentOrder: selectedShipmentKind == .parcel)
            if selectedShipmentKind != .parcel { resetShippingDraft() }
            selectedShipmentKind = .parcel
            parcelImportError = nil
            lastMessage = nil
            lastImportedLabelJobID = job.id
            labelImportSequence &+= 1
        } catch {
            reportDHLImportError(error)
        }
    }

    func presentPrintPreview(_ job: PrintJob) {
        if let id = job.letterFlowID {
            guard let flow = letterFlows.flow(id) else { lastMessage = "Der zugehörige Briefablauf wurde nicht gefunden."; return }
            letterFlowPreview = flow
            return
        }
        guard FileManager.default.fileExists(atPath: job.sourceURL.path) else {
            lastMessage = "Die Quelldatei für diese Vorschau wurde nicht gefunden."
            return
        }
        previewJob = job
    }

    func closePrintPreview() {
        previewJob = nil
    }

    func printFromPreview(_ job: PrintJob, completion: @escaping (Result<Void, Error>) -> Void) {
        printJob(job, completion: completion)
    }

    private var shippingDraftURL: URL {
        applicationDataLocation.rootURL.appendingPathComponent("Versandentwurf.json")
    }

    func shippingDraft(for journey: ShippingRoute) -> ShippingDraft? {
        guard journey.task != nil else { return nil }
        return ShippingDraft(journey: journey, recipient: recipientAddress, browserOrder: activeBrowserOrder,
                             packingNote: packingNote, csvOrderID: activeCSVOrderID, withPostage: letterWithPostage,
                             stampID: selectedLetterPostageID,
                             postageIDs: journey.task == .postage ? selectedPostageIDs : [],
                             letterFlowID: draftLetterFlowID, addressJobID: draftAddressJobID)
    }

    func loadShippingDraft() -> ShippingRoute? {
        guard FileManager.default.fileExists(atPath: shippingDraftURL.path) else { return nil }
        do {
            let draft = try JSONDecoder().decode(ShippingDraft.self, from: Data(contentsOf: shippingDraftURL))
            applyRecipient(draft.recipient)
            packingNote = draft.packingNote ?? ""
            activeBrowserOrder = draft.browserOrder
            activeCSVOrderID = draft.csvOrderID
            letterWithPostage = draft.withPostage
            selectedLetterPostageID = draft.stampID
            selectAvailablePostage(in: postage.entries)
            selectedPostageIDs = draft.postageIDs
            draftLetterFlowID = draft.letterFlowID
            draftAddressJobID = draft.addressJobID
            selectedShipmentKind = draft.journey.task == .parcel ? .parcel : .letter
            return draft.journey
        } catch {
            lastMessage = "Der gespeicherte Entwurf konnte nicht gelesen werden."
            return nil
        }
    }

    func saveShippingDraft(_ draft: ShippingDraft?) {
        do {
            if let draft {
                try JSONEncoder().encode(draft).write(to: shippingDraftURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: shippingDraftURL.path) {
                try FileManager.default.removeItem(at: shippingDraftURL)
            }
        } catch {
            lastMessage = "Der Entwurf konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }

    var shippingBusy: Bool {
        orderBatch.running || printInProgress || printingPostageBatch || letterFlowController.activeFlowID != nil
    }

    func resetShippingDraft() {
        packingNote = ""
        activeBrowserOrder = nil
        activeCSVOrderID = nil
        selectAvailablePostage(in: postage.entries)
        letterWithPostage = true
        parcelImportError = nil
        lastImportedLabelJobID = nil
        draftLetterFlowID = nil
        draftAddressJobID = nil
        applyRecipient(RecipientAddress(name: "", street1: "", postalCode: "", city: "", country: ""))
        lastMessage = nil
    }

    func showShippingHome() {
        guard !shippingBusy else { return }
        draftHomeSequence &+= 1
    }

    func returnToStart() {
        guard !shippingBusy else { return }
        closeShippingPreviews()
        resetShippingDraft()
        homeRequestSequence &+= 1
    }

    func showCompletedShipmentInHistory() {
        guard !shippingBusy else { return }
        closeShippingPreviews()
        resetShippingDraft()
        historyRequestSequence &+= 1
    }

    private func closeShippingPreviews() {
        previewJob = nil
        letterFlowPreview = nil
        postagePreview = nil
    }

    func exportHistory() {
        let panel = NSSavePanel()
        panel.title = "Verlauf exportieren"
        panel.prompt = "Exportieren"
        panel.nameFieldStringValue = ShippingHistoryExporter.defaultFilename()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ShippingHistoryExporter.csvData(flows: letterFlows.flows, records: labelHistory.records, jobs: jobs.jobs)
                .write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            historyExportError = error.localizedDescription
        }
    }

    private func applyRecipient(_ recipient: RecipientAddress) {
        recipientName = recipient.name
        recipientStreet1 = recipient.street1
        recipientStreet2 = recipient.street2
        recipientPostalCode = recipient.postalCode
        recipientCity = recipient.city
        recipientCountry = recipient.country.isEmpty ? "Deutschland" : recipient.country
    }

    var usesCombinedLetterLabel: Bool { letterWithPostage && combinedLabel.isEnabled }

    func combinedLetterPDF(stamp: PostageStamp?, stampSize: CGSize, recipient: RecipientAddress,
                           sender: SenderAddress) throws -> (data: Data, format: LabelFormat) {
        let continuous = labelStockMode == .continuous100
        return try EtsyAddressLabelWriter.makeCombinedPDF(
            recipient: recipient, sender: sender, stamp: stamp, stampSize: stampSize,
            format: continuous ? .shipping100x150 : selectedLetterLabelFormat, continuous: continuous,
            settings: combinedLabel, placement: postageStampPlacement, design: addressLabelDesign
        )
    }

    var letterReviewSettings: LetterReviewSettings {
        let stamp = letterWithPostage
            ? postage.entries.first { $0.id == selectedLetterPostageID && $0.status == .available }?.stamp
            : nil
        return letterSettings(recipient: recipientAddress, note: packingNote, needsStamp: letterWithPostage, stamp: stamp)
    }

    func letterSettings(recipient: RecipientAddress, note: String, needsStamp: Bool, stamp: PostageStamp?) -> LetterReviewSettings {
        let format = letterFormat(for: recipient)
        return LetterReviewSettings(recipient: recipient, sender: senderAddress, stamp: stamp,
                                    needsStamp: needsStamp, combined: combinedLabel,
                                    stampPlacement: postageStampPlacement, design: addressLabelDesign,
                                    addressFormat: format, stampFormat: labelStockMode == .continuous100 ? .shipping100x150 : format,
                                    continuous: labelStockMode == .continuous100, additionalFeedMM: continuousExtraFeedMM,
                                    packingNote: note.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func printReviewedLetter(_ plan: LetterPrintPlan) {
        guard !shippingBusy, plan.settings == letterReviewSettings else { return }
        let hasStamp = plan.settings.stamp != nil
        guard (!hasStamp && !canPrintSelectedMaterialOverBluetooth) || bluetooth.connectionState.isReady,
              !hasStamp || canPrintSelectedMaterialOverBluetooth else { return }
        if openExistingLetterPrint() { return }

        do {
            switch try prepareLetter(plan, id: UUID(), orderID: activeBrowserOrder?.orderID ?? activeCSVOrderID) {
            case .stamped(let flow):
                draftLetterFlowID = flow.id
                letterFlowPreview = flow
                letterFlowController.start(flow.id)
            case .address(let job):
                draftAddressJobID = job.id
                printJob(job)
            }
        } catch {
            lastMessage = "Briefversand konnte nicht vorbereitet werden: \(error.localizedDescription)"
        }
    }

    enum PreparedLetter {
        case stamped(LetterShipmentFlow)
        case address(PrintJob)
    }

    func prepareLetter(_ plan: LetterPrintPlan, id: UUID, orderID: String?) throws -> PreparedLetter {
        guard let firstPage = plan.pages.first else { throw LabelRendererError.cannotCreateBitmap }
        let hasStamp = plan.settings.stamp != nil
        let directory = hasStamp ? postage.directory : applicationDataLocation.rootURL
            .appendingPathComponent("Address Labels", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = try plan.pages.enumerated().map { index, page in
            let url = directory.appendingPathComponent("brief-\(id.uuidString)-\(index + 1).pdf")
            try page.pdf.write(to: url, options: .atomic)
            return url
        }
        let name = plan.settings.recipient.name
        if let stamp = plan.settings.stamp {
            let combined = plan.pages.count == 1
            let addressJob = try jobs.enqueue(url: urls[0], labelFormat: firstPage.format,
                displayName: combined ? "Brief mit Marke · \(name)" : "Briefadresse · \(name)",
                sourceFingerprint: "letter-address:\(id)",
                postageStampIDs: combined ? [stamp.id] : nil, letterFlowID: id)
            let stampJob: PrintJob
            if combined {
                stampJob = addressJob
            } else {
                stampJob = try jobs.enqueue(url: urls[1], labelFormat: plan.pages[1].format,
                    displayName: "Briefmarke · \(name)", sourceFingerprint: "letter-stamp:\(id)",
                    postageStampIDs: [stamp.id], letterFlowID: id)
            }
            let flow = LetterShipmentFlow(id: id, recipientName: name, orderID: orderID, stamp: stamp,
                addressJob: addressJob, stampJob: stampJob, stage: combined ? .addressPrinted : .ready,
                isCombined: combined)
            try letterFlows.add(flow)
            return .stamped(flow)
        } else {
            let job = try jobs.enqueue(url: urls[0], labelFormat: firstPage.format, displayName: "Brief · \(name)",
                sourceFingerprint: "manual-address:\(id)")
            if let record = LabelHistoryRecord(job: job, parcelInfo: nil, recipient: plan.settings.recipient,
                                               orderID: orderID) {
                labelHistory.add(record)
            }
            return .address(job)
        }
    }

    @discardableResult
    func openExistingLetterPrint() -> Bool {
        if let id = draftLetterFlowID, let flow = letterFlows.flow(id) {
            letterFlowPreview = flow
            return true
        }
        if let id = draftAddressJobID, let job = jobs.jobs.first(where: { $0.id == id }) {
            presentPrintPreview(job)
            return true
        }
        draftLetterFlowID = nil
        draftAddressJobID = nil
        return false
    }

}
