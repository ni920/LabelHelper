import CoreGraphics
import Foundation

public struct PostageStamp: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let sourceURL: URL
    public let pageNumber: Int
    public let number: Int
    public let amount: String
    public let sourceRect: CGRect

    public init(id: String, sourceURL: URL, pageNumber: Int, number: Int, amount: String, sourceRect: CGRect) {
        self.id = id
        self.sourceURL = sourceURL
        self.pageNumber = pageNumber
        self.number = number
        self.amount = amount
        self.sourceRect = sourceRect
    }

    /// The complete printed Internetmarke identifier, including leading zeros
    /// and its check digit. Use the PDF's identifier rather than deriving one
    /// from an excerpt of the binary matrix payload.
    public var trackingNumber: String? { Self.trackingNumber(forID: id) }

    public static func trackingNumber(forID id: String) -> String? {
        let value = id.filter { !$0.isWhitespace }.uppercased()
        guard value.count == 20, value.allSatisfy({ "0123456789ABCDEF".contains($0) }) else { return nil }
        return value
    }

    public static func trackingNumbersText(for stamps: [PostageStamp]) -> String {
        stamps.compactMap(\.trackingNumber).joined(separator: "\n")
    }
}

/// Where the stamps sit on their label. Their size never changes.
public struct PostageStampPlacement: Codable, Equatable, Sendable {
    public enum Horizontal: String, Codable, CaseIterable, Identifiable, Sendable {
        /// Centers the label's full column grid, so a lone stamp sits left of the middle.
        case automatic
        case leading, center, trailing
        public var id: Self { self }
        public var title: String {
            switch self {
            case .automatic: "Auto"
            case .leading: "Links"
            case .center: "Mitte"
            case .trailing: "Rechts"
            }
        }
    }

    public static let standard = PostageStampPlacement()

    public var horizontal = Horizontal.automatic
    public var vertical = AddressLabelDesign.VerticalPlacement.top

    public init() {}
}

/// Packs complete stamps at their PDF size, in points. No scaling is applied.
public struct PostageSheetLayout: Sendable {
    public struct Placement: Sendable {
        public let stampIndex: Int
        public let rect: CGRect
    }

    /// Top-left corner and width of a sheet's stamp grid, for its cut guides.
    public struct Grid: Sendable {
        public let left: Double
        public let top: Double
        public let columns: Int
    }

    public let capacity: Int
    public let columns: Int
    public let sheets: [[Placement]]
    public let cellSize: CGSize
    /// Maximum packing area; emitted pages use their individual sheetFormats.
    public let paperSize: CGSize
    public let sheetFormats: [LabelFormat]
    public let grids: [Grid]

    public init(stampSizes: [CGSize], format: LabelFormat, fitHeightToContent: Bool = false,
                placement stampPlacement: PostageStampPlacement = .standard) {
        let pointsPerMM = 72.0 / 25.4
        let margin = pointsPerMM
        paperSize = CGSize(width: format.widthMM * pointsPerMM, height: format.heightMM * pointsPerMM)
        cellSize = CGSize(width: stampSizes.map(\.width).max() ?? 0, height: stampSizes.map(\.height).max() ?? 0)
        guard cellSize.width.isFinite, cellSize.height.isFinite, cellSize.width > 0, cellSize.height > 0 else {
            columns = 0; capacity = 0; sheets = []; sheetFormats = []; grids = []; return
        }
        columns = max(0, Int(floor((paperSize.width - 2 * margin) / cellSize.width)))
        let rows = max(0, Int(floor((paperSize.height - 2 * margin) / cellSize.height)))
        capacity = columns * rows
        guard capacity > 0 else { sheets = []; sheetFormats = []; grids = []; return }
        var result: [[Placement]] = []
        var formats: [LabelFormat] = []
        var sheetGrids: [Grid] = []
        for start in stride(from: 0, to: stampSizes.count, by: capacity) {
            let count = min(capacity, stampSizes.count - start)
            let occupiedRows = (count + columns - 1) / columns
            let sheetFormat = fitHeightToContent
                ? LabelFormat.continuous(widthMM: format.widthMM, heightMM: Double(occupiedRows) * cellSize.height / pointsPerMM + 2)
                : format
            formats.append(sheetFormat)
            let usedColumns = stampPlacement.horizontal == .automatic ? columns : min(count, columns)
            let gridWidth = Double(usedColumns) * cellSize.width
            let originX: Double
            switch stampPlacement.horizontal {
            case .automatic, .center: originX = (paperSize.width - gridWidth) / 2
            case .leading: originX = margin
            case .trailing: originX = paperSize.width - margin - gridWidth
            }
            let sheetHeight = sheetFormat.heightMM * pointsPerMM
            let freeHeight = max(0, sheetHeight - 2 * margin - Double(occupiedRows) * cellSize.height)
            let verticalOffset: Double
            switch stampPlacement.vertical {
            case .top: verticalOffset = 0
            case .center: verticalOffset = freeHeight / 2
            case .bottom: verticalOffset = freeHeight
            }
            let top = sheetHeight - margin - verticalOffset
            sheetGrids.append(Grid(left: originX, top: top, columns: usedColumns))
            var sheet: [Placement] = []
            for index in start..<min(start + capacity, stampSizes.count) {
                let slot = index - start
                let size = stampSizes[index]
                let rect = CGRect(
                    x: originX + Double(slot % columns) * cellSize.width + (cellSize.width - size.width) / 2,
                    y: top - Double(slot / columns + 1) * cellSize.height + (cellSize.height - size.height) / 2,
                    width: size.width, height: size.height
                )
                sheet.append(Placement(stampIndex: index, rect: rect))
            }
            result.append(sheet)
        }
        sheets = result
        sheetFormats = formats
        grids = sheetGrids
    }
}
