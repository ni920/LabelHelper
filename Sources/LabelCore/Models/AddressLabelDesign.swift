import Foundation

/// How address labels are laid out. `.standard` is the built-in look; sizes are
/// relative so that one design works on every label format.
public struct AddressLabelDesign: Codable, Equatable, Sendable {
    public enum SenderPlacement: String, Codable, CaseIterable, Identifiable, Sendable {
        case top, bottom, hidden
        public var id: Self { self }
        public var title: String {
            switch self { case .top: "Oben"; case .bottom: "Unten"; case .hidden: "Aus" }
        }
    }

    public enum HorizontalPlacement: String, Codable, CaseIterable, Identifiable, Sendable {
        case leading, center, trailing
        public var id: Self { self }
        public var title: String {
            switch self { case .leading: "Links"; case .center: "Mitte"; case .trailing: "Rechts" }
        }
    }

    public enum VerticalPlacement: String, Codable, CaseIterable, Identifiable, Sendable {
        case top, center, bottom
        public var id: Self { self }
        public var title: String {
            switch self { case .top: "Oben"; case .center: "Mitte"; case .bottom: "Unten" }
        }
    }

    public enum Typeface: String, Codable, CaseIterable, Identifiable, Sendable {
        case system, rounded, serif, monospaced
        public var id: Self { self }
        public var title: String {
            switch self {
            case .system: "Standard"
            case .rounded: "Abgerundet"
            case .serif: "Serifen"
            case .monospaced: "Monospace"
            }
        }
    }

    public enum Weight: String, Codable, CaseIterable, Identifiable, Sendable {
        case regular, medium, semibold, bold
        public var id: Self { self }
        public var title: String {
            switch self {
            case .regular: "Normal"
            case .medium: "Mittel"
            case .semibold: "Halbfett"
            case .bold: "Fett"
            }
        }
    }

    public static let standard = AddressLabelDesign()
    public static let scaleRange = 0.7...1.5
    public static let extraMarginRangeMM = 0.0...8.0

    public var senderPlacement = SenderPlacement.top
    public var senderAlignment = HorizontalPlacement.leading
    public var senderScale = 1.0
    public var showsSeparator = false
    public var recipientAlignment = HorizontalPlacement.leading
    public var recipientVerticalPlacement = VerticalPlacement.center
    public var recipientScale = 1.0
    public var recipientWeight = Weight.medium
    public var emphasizesName = true
    public var typeface = Typeface.system
    /// Added to the format's own margin, which keeps ink clear of the cut edge.
    public var extraMarginMM = 0.0

    public init() {}
}
