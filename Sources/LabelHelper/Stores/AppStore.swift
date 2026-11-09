import AppKit
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

    @Published var guidedMode: Bool {
        didSet { defaults.set(guidedMode, forKey: "guidedMode") }
    }
    @Published var showPrinterConnection = false
    @Published var homeRequestSequence = 0
    @Published private(set) var shippingImportSequence = 0
    @Published private(set) var labelImportSequence = 0
    @Published private(set) var lastImportedLabelJobID: UUID?
    @Published private(set) var postageImportSucceeded = false
    @Published var showImporter = false
    @Published var showPostageImporter = false
    @Published var postagePreview: PostagePrintBatch?
    @Published var letterFlowPreview: LetterShipmentFlow?
    @Published var selectedLetterPostageID: String {
        didSet { defaults.set(selectedLetterPostageID, forKey: "selectedLetterPostageID") }
    }
    @Published var letterWithPostage: Bool {
        didSet { defaults.set(letterWithPostage, forKey: "letterWithPostage") }
    }
    @Published var selectedPostageIDs: Set<String> = []
    @Published private(set) var postageImportSequence = 0
    @Published private(set) var printInProgress = false
    @Published private(set) var printingPostageBatch = false
    @Published private(set) var postageBatchProgress = ""
    private var postageBatchRemaining: [PrintJob] = []
    private var postageBatchTotal = 0
    private var postageBatchCompleted = 0
    private var stopPostageBatch = false
    @Published var showEtsyImporter = false
    @Published var showEtsyImportReview = false
    @Published var showEtsyImportError = false
    @Published var showBrowserOrderReview = false
    @Published var lastMessage: String?
    @Published var historyExportError: String?
    @Published var selectedJobID: UUID?
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
    @Published private(set) var activeBrowserOrder: BrowserOrderPayload?
    @Published private(set) var activeCSVOrderID: String?
    @Published private(set) var browserImportSequence = 0

    let bluetooth = BluetoothPrinterService()
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
        jobs = PrintJobStore(directory: root)
        postage = PostageStampStore(directory: root.appendingPathComponent("Briefmarken", isDirectory: true))
        letterFlows = LetterFlowStore(directory: root.appendingPathComponent("Briefversand", isDirectory: true))
        let history = LabelHistoryStore(directory: root.appendingPathComponent("Labelverlauf", isDirectory: true))
        history.adopt(jobs.jobs)
        jobs.onStatusChange = { [weak history] id, status, errorMessage in
            history?.updateStatus(id, status: status, errorMessage: errorMessage)
        }
        labelHistory = history
        guidedMode = defaults.object(forKey: "guidedMode") as? Bool ?? true
        letterWithPostage = defaults.bool(forKey: "letterWithPostage")
        selectedLetterPostageID = defaults.string(forKey: "selectedLetterPostageID") ?? ""
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
    }

    var canManageApplicationData: Bool {
        !printInProgress && !printingPostageBatch && letterFlowController.activeFlowID == nil
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
        labelStockMode == .continuous100
            ? ContinuousLabelCutGuide.printFormat(for: contentFormat, additionalFeedMM: continuousExtraFeedMM)
            : contentFormat
    }

    func applyingMaterialCutGuide(to raster: LabelRaster) -> LabelRaster {
        labelStockMode == .continuous100
            ? ContinuousLabelCutGuide.applying(to: raster, additionalFeedMM: continuousExtraFeedMM)
            : raster
    }

    func renderLabel(_ job: PrintJob) throws -> LabelRaster {
        applyingMaterialCutGuide(to: try LabelRenderer.render(url: job.sourceURL, format: job.resolvedLabelFormat))
    }

    var selectedLetterLabelFormat: LabelFormat {
        if labelStockMode == .continuous100 {
            return EtsyAddressLabelWriter.continuousFormat(recipient: recipientAddress, sender: senderAddress, design: addressLabelDesign)
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

    func importFiles(_ urls: [URL], presentPreview: Bool = true) {
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
                selectedJobID = job.id
                lastImportedJob = job
                lastMessage = job.status == .printed
                    ? "Dieses Etikett wurde bereits gedruckt."
                    : "\(url.lastPathComponent) ist druckbereit."
            } catch {
                lastMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
            }
        }

        if let lastImportedJob {
            lastImportedLabelJobID = lastImportedJob.id
            labelImportSequence &+= 1
        }
        if presentPreview, let lastImportedJob {
            // The file importer must finish dismissing before another sheet can open.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.presentPrintPreview(lastImportedJob)
            }
        }
    }

    private func recordImportedLabel(_ job: PrintJob) {
        guard !labelHistory.records.contains(where: { $0.id == job.id }) else { return }
        let info = ParcelLabelParser.parse(url: job.sourceURL)
        // An order left over from an earlier shipment must not attach to this label.
        let sameRecipient = info?.recipientName.map { Self.normalizedName($0) == Self.normalizedName(recipientName) } ?? false
        let orderID = sameRecipient ? activeBrowserOrder?.orderID ?? activeCSVOrderID : nil
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
            let order = try BrowserOrderLink.decode(url)
            incomingBrowserOrder = order
            showBrowserOrderReview = true
            browserImportSequence &+= 1
            lastMessage = "Etsy-Bestellung #\(order.orderID) wurde aus dem Browser empfangen."
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            incomingBrowserOrder = nil
            showBrowserOrderReview = false
            lastMessage = "Browser-Import fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func acceptIncomingBrowserOrder(as shipmentKind: ShipmentKind) {
        guard let order = incomingBrowserOrder else { return }
        applyRecipient(order.recipient)
        activeBrowserOrder = order
        activeCSVOrderID = nil
        selectedShipmentKind = shipmentKind
        shippingImportSequence &+= 1
        incomingBrowserOrder = nil
        showBrowserOrderReview = false
        browserImportSequence &+= 1
        lastMessage = shipmentKind == .letter
            ? "Etsy-Bestellung #\(order.orderID) wurde ins Briefformular übernommen."
            : "Etsy-Bestellung #\(order.orderID) wurde übernommen. Jetzt das DHL-Paketlabel auswählen."
    }

    func dismissIncomingBrowserOrder() {
        incomingBrowserOrder = nil
        showBrowserOrderReview = false
    }

    func printTestLabel() {
        guard !printInProgress, !printingPostageBatch, letterFlowController.activeFlowID == nil else { return }
        // Keep a continuous-stock test short even if the current task is a parcel.
        let testFormat = labelStockMode == .continuous100 ? LabelFormat.continuousLetter100x55 : selectedLabelFormat
        if labelStockMode == .continuous100 && !canPrintSelectedMaterialOverBluetooth {
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
        guard !printInProgress else {
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
        guard !printInProgress, !printingPostageBatch, letterFlowController.activeFlowID == nil else { return }
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
        guard !printInProgress, !printingPostageBatch, bluetooth.connectionState.isReady,
              letterFlowController.activeFlowID == nil,
              canPrintSelectedMaterialOverBluetooth, postage.canPrint(batch.jobs.flatMap { $0.postageStampIDs ?? [] }) else {
            lastMessage = "Drucker verbinden und die Markenauswahl prüfen. Für Endlosrollen ist Firmware ab 1.1.49 erforderlich."
            return
        }
        postagePreview = nil
        printingPostageBatch = true
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
            showEtsyImporter = false

            // A file importer is itself a modal presentation. Opening the review
            // sheet from its completion handler can otherwise be ignored by macOS
            // while the file importer is still being dismissed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, !self.pendingEtsyOrders.isEmpty else { return }
                self.showEtsyImportReview = true
            }
        } catch {
            pendingEtsyOrders = []
            let message = error.localizedDescription
            lastMessage = "Etsy-Import fehlgeschlagen: \(message)"
            showEtsyImporter = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showEtsyImportError = true
            }
        }
    }

    func applyEtsyOrder(_ order: EtsyOrder) {
        applyRecipient(order.recipientAddress)
        activeBrowserOrder = nil
        activeCSVOrderID = order.id
        shippingImportSequence &+= 1
        selectedShipmentKind = .letter
        showEtsyImportReview = false
        pendingEtsyOrders = []
        lastMessage = "Die Adresse von \(order.recipientName) wurde ins Formular übernommen."
    }

    func createManualAddressLabel() {
        guard !printInProgress, !printingPostageBatch, letterFlowController.activeFlowID == nil else { return }
        guard recipientAddress.isComplete else {
            lastMessage = "Bitte die vollständige Empfängeradresse eingeben."
            return
        }
        guard senderAddress.isComplete else {
            lastMessage = "Bitte den vollständigen Absender eingeben."
            return
        }

        if letterWithPostage {
            createLetterFlow()
            return
        }

        do {
            let url = try EtsyAddressLabelWriter.write(
                recipient: recipientAddress,
                sender: senderAddress,
                format: selectedLabelFormat,
                design: addressLabelDesign
            )
            let job = try jobs.enqueue(
                url: url,
                labelFormat: selectedLabelFormat,
                displayName: "Brief · \(recipientAddress.name)",
                sourceFingerprint: "manual-address:\(UUID().uuidString)"
            )
            if let record = LabelHistoryRecord(job: job, parcelInfo: nil, recipient: recipientAddress,
                                               orderID: activeBrowserOrder?.orderID ?? activeCSVOrderID) {
                labelHistory.add(record)
            }
            selectedJobID = job.id
            lastMessage = "Das Adressetikett für \(recipientAddress.name) ist druckbereit."
            presentPrintPreview(job)
        } catch {
            lastMessage = "Adressetikett konnte nicht erstellt werden: \(error.localizedDescription)"
        }
    }

    func requestLabelImport() {
        if guidedMode { selectedShipmentKind = .parcel }
        showImporter = true
    }

    func chooseDHLLabelImport() {
        showEtsyImportReview = false
        selectedShipmentKind = .parcel
        lastMessage = "Das bei DHL gekaufte Versandlabel jetzt als PDF auswählen."
        showImporter = true
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
        selectedJobID = job.id
        previewJob = job
    }

    func closePrintPreview() {
        previewJob = nil
    }

    func printFromPreview(_ job: PrintJob, completion: @escaping (Result<Void, Error>) -> Void) {
        printJob(job, completion: completion)
    }

    /// Ends the finished shipment: the next one must not start with the old address.
    func returnToStart() {
        guard !printInProgress, !printingPostageBatch, letterFlowController.activeFlowID == nil else { return }
        previewJob = nil
        letterFlowPreview = nil
        activeBrowserOrder = nil
        activeCSVOrderID = nil
        applyRecipient(RecipientAddress(name: "", street1: "", postalCode: "", city: "", country: ""))
        homeRequestSequence &+= 1
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

    private func createCombinedLetterFlow(_ entry: PostageStampStore.Entry) throws {
        let id = UUID()
        let label = try combinedLetterPDF(stamp: entry.stamp, stampSize: entry.stamp.sourceRect.size,
                                          recipient: recipientAddress, sender: senderAddress)
        let url = postage.directory.appendingPathComponent("brief-kombiniert-\(id.uuidString).pdf")
        try label.data.write(to: url, options: .atomic)
        let job = try jobs.enqueue(url: url, labelFormat: label.format, displayName: "Brief mit Marke · \(recipientAddress.name)",
                                   sourceFingerprint: "letter-combined:\(id)", postageStampIDs: [entry.id], letterFlowID: id)
        // Starts at the stamp stage: the one label carries the paid stamp.
        let flow = LetterShipmentFlow(id: id, recipientName: recipientAddress.name, orderID: activeBrowserOrder?.orderID ?? activeCSVOrderID,
                                      stamp: entry.stamp, addressJob: job, stampJob: job, stage: .addressPrinted, isCombined: true)
        try letterFlows.add(flow)
        letterFlowPreview = flow
        lastMessage = "Briefversand für \(recipientAddress.name) ist vorbereitet."
    }

    private func createLetterFlow() {
        guard let entry = postage.entries.first(where: { $0.id == selectedLetterPostageID && $0.status == .available }) else {
            lastMessage = "Bitte eine verfügbare Briefmarke mit passendem Portowert wählen."
            return
        }
        if combinedLabel.isEnabled {
            do { try createCombinedLetterFlow(entry) }
            catch { lastMessage = "Briefversand konnte nicht vorbereitet werden: \(error.localizedDescription)" }
            return
        }
        let format = selectedLetterLabelFormat
        let stampFormat = selectedLetterPostageFormat
        guard PostageSheetLayout(stampSizes: [entry.stamp.sourceRect.size], format: stampFormat).capacity > 0 else {
            lastMessage = "Die Briefmarke passt nicht in Originalgröße. Bitte ein größeres Etikettenformat wählen."
            return
        }
        do {
            let id = UUID()
            let addressURL = try EtsyAddressLabelWriter.write(recipient: recipientAddress, sender: senderAddress, format: format, design: addressLabelDesign)
            let sheets = try PostagePDFService.writeSheets(stamps: [entry.stamp], format: stampFormat, cutGuides: false,
                                                          directory: postage.directory, fitHeightToContent: labelStockMode == .continuous100,
                                                          placement: postageStampPlacement)
            guard let sheet = sheets.first else { throw PostagePDFError.cannotWrite }
            let addressJob = try jobs.enqueue(url: addressURL, labelFormat: format, displayName: "Briefadresse · \(recipientAddress.name)",
                                              sourceFingerprint: "letter-address:\(id)", letterFlowID: id)
            let stampJob = try jobs.enqueue(url: sheet.url, labelFormat: sheet.format, displayName: "Briefmarke · \(recipientAddress.name)",
                                            sourceFingerprint: "letter-stamp:\(id)", postageStampIDs: [entry.id], letterFlowID: id)
            let flow = LetterShipmentFlow(id: id, recipientName: recipientAddress.name, orderID: activeBrowserOrder?.orderID ?? activeCSVOrderID,
                                          stamp: entry.stamp, addressJob: addressJob, stampJob: stampJob)
            try letterFlows.add(flow)
            letterFlowPreview = flow
            lastMessage = "Briefversand für \(recipientAddress.name) ist vorbereitet."
        } catch { lastMessage = "Briefversand konnte nicht vorbereitet werden: \(error.localizedDescription)" }
    }

}
