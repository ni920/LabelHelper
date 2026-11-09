import CoreGraphics
import Foundation

/// Address and stamp printed together, so the stamp needs no cutting out.
public struct CombinedLabelSettings: Codable, Equatable, Sendable {
    public enum Arrangement: String, Codable, CaseIterable, Identifiable, Sendable {
        case stampRight, stampLeft, stampTop, stampBottom
        public var id: Self { self }
        public var title: String {
            switch self {
            case .stampRight: "Rechts"
            case .stampLeft: "Links"
            case .stampTop: "Oben"
            case .stampBottom: "Unten"
            }
        }
        var isBeside: Bool { self == .stampRight || self == .stampLeft }
    }

    public static let standard = CombinedLabelSettings()

    public var isEnabled = false
    public var arrangement = Arrangement.stampRight

    public init() {}
}

/// Splits one label into an address area and a stamp at its original size.
public struct CombinedLabelLayout: Sendable {
    private static let pointsPerMM = 72.0 / 25.4
    private static let minimumAddressWidthMM = 30.0
    private static let minimumAddressHeightMM = 15.0

    public let format: LabelFormat
    public let addressFormat: LabelFormat
    public let addressOrigin: CGPoint
    public let stampRect: CGRect

    /// `continuousAddressFormat` measures the address for a given width; with
    /// it the label grows to its content, without it `format` is the fixed size.
    public init?(
        format: LabelFormat,
        stampSize: CGSize,
        settings: CombinedLabelSettings,
        placement: PostageStampPlacement,
        continuousAddressFormat: ((Double) -> LabelFormat)? = nil
    ) {
        guard stampSize.width > 0, stampSize.height > 0 else { return nil }
        let unit = Self.pointsPerMM
        let margin = unit
        let arrangement = settings.arrangement
        let width = format.widthMM * unit
        let stampBlock = (arrangement.isBeside ? stampSize.width : stampSize.height) + 2 * margin
        let addressWidth = arrangement.isBeside ? width - stampBlock : width
        guard addressWidth >= Self.minimumAddressWidthMM * unit else { return nil }

        let area: LabelFormat
        let height: Double
        if let continuousAddressFormat {
            area = continuousAddressFormat(addressWidth / unit)
            let content = area.heightMM * unit
            let needed = arrangement.isBeside ? max(content, stampSize.height + 2 * margin) : content + stampBlock
            self.format = .continuous(widthMM: format.widthMM, heightMM: needed / unit)
            height = self.format.heightMM * unit
        } else {
            let fixedHeight = format.heightMM * unit
            let addressHeight = arrangement.isBeside ? fixedHeight : fixedHeight - stampBlock
            guard addressHeight >= Self.minimumAddressHeightMM * unit,
                  !arrangement.isBeside || stampBlock <= width, stampSize.height + 2 * margin <= fixedHeight else { return nil }
            area = LabelFormat(id: "combined-address", name: "Adressbereich",
                               widthMM: addressWidth / unit, heightMM: addressHeight / unit)
            self.format = format
            height = fixedHeight
        }
        addressFormat = area

        let areaHeight = area.heightMM * unit
        switch arrangement {
        case .stampRight: addressOrigin = CGPoint(x: 0, y: height - areaHeight)
        case .stampLeft: addressOrigin = CGPoint(x: stampBlock, y: height - areaHeight)
        case .stampTop: addressOrigin = .zero
        case .stampBottom: addressOrigin = CGPoint(x: 0, y: height - areaHeight)
        }

        let x: Double
        let y: Double
        if arrangement.isBeside {
            x = arrangement == .stampRight ? width - margin - stampSize.width : margin
            switch placement.vertical {
            case .top: y = height - margin - stampSize.height
            case .center: y = (height - stampSize.height) / 2
            case .bottom: y = margin
            }
        } else {
            y = arrangement == .stampTop ? height - margin - stampSize.height : margin
            switch placement.horizontal {
            case .leading: x = margin
            case .center: x = (width - stampSize.width) / 2
            case .automatic, .trailing: x = width - margin - stampSize.width
            }
        }
        stampRect = CGRect(x: x, y: y, width: stampSize.width, height: stampSize.height)
    }
}
