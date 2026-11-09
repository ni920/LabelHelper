import CoreGraphics
import Foundation
import LabelCore

func runCutGuideTests() throws {
    for format in [LabelFormat.continuousLetter100x55, .shipping100x150, .continuous(heightMM: 26), .continuous(heightMM: 32.875)] {
        // Ink touches every source edge; a cut guide must never overwrite it.
        let stride = (format.widthDots + 7) / 8
        let original = Data((0..<(stride * format.heightDots)).map { UInt8(truncatingIfNeeded: $0 * 37) })
        let source = LabelRaster(width: format.widthDots, height: format.heightDots, bytesPerRow: stride, bitmap: original)
        let result = ContinuousLabelCutGuide.applying(to: source)
        try require(result.width == source.width && result.height == source.height + 16,
                    "Continuous cut strip must add exactly 2 mm without resizing content")
        try require(result.bitmap.prefix(original.count) == original,
                    "Cut guide changed label ink or barcode pixels")
        try require(result.bitmap.count == stride * result.height, "Cut strip produced incomplete raster rows")
        for y in source.height..<result.height {
            for x in 0..<result.width {
                let black = result.bitmap[y * stride + x / 8] & (0x80 >> UInt8(x % 8)) != 0
                let expected = (source.height + 8..<(source.height + 10)).contains(y) &&
                    x >= 16 && x < source.width - 16 && (x - 16) % 24 < 16
                try require(black == expected, "Cut line dash, gap or blank margin is incorrect")
            }
        }
        let printFormat = ContinuousLabelCutGuide.printFormat(for: format)
        try require(printFormat.widthDots == result.width && printFormat.heightDots == result.height,
                    "System print paper size differs from the Bluetooth raster")
    }
    let empty = LabelRaster(width: 0, height: 0, bytesPerRow: 0, bitmap: Data())
    try require(ContinuousLabelCutGuide.applying(to: empty) == empty, "Malformed raster must not be extended")
    print("Cut guide tests passed: 2 mm strip, unchanged content, dash placement and print-size agreement")
}

func runCombinedLabelTests() throws {
    let stamp = CGSize(width: 116, height: 68)
    let unit = 72.0 / 25.4
    func settings(_ arrangement: CombinedLabelSettings.Arrangement) -> CombinedLabelSettings {
        var value = CombinedLabelSettings.standard
        value.isEnabled = true
        value.arrangement = arrangement
        return value
    }
    let format = LabelFormat.product100x50
    let bounds = CGRect(x: 0, y: 0, width: format.widthMM * unit, height: format.heightMM * unit)
    for arrangement in CombinedLabelSettings.Arrangement.allCases where arrangement == .stampRight || arrangement == .stampLeft {
        guard let layout = CombinedLabelLayout(format: format, stampSize: stamp, settings: settings(arrangement), placement: .standard) else {
            throw SelfTestFailure.assertion("Stamp beside the address must fit 100 × 50 mm")
        }
        let area = CGRect(origin: layout.addressOrigin, size: CGSize(width: layout.addressFormat.widthMM * unit, height: layout.addressFormat.heightMM * unit))
        try require(bounds.contains(layout.stampRect) && layout.stampRect.size == stamp, "Combined stamp left the label or changed size")
        try require(!area.insetBy(dx: 0.01, dy: 0.01).intersects(layout.stampRect), "Stamp overlaps the address area")
        try require(area.maxX <= bounds.width + 0.01, "Address area left the label")
    }
    let right = CombinedLabelLayout(format: format, stampSize: stamp, settings: settings(.stampRight), placement: .standard)!
    try require(abs(right.stampRect.maxX - (bounds.width - unit)) < 0.01 && abs(right.stampRect.maxY - (bounds.height - unit)) < 0.01,
                "The default stamp must sit in the top right corner")
    let tall = LabelFormat.shipping100x150
    guard let top = CombinedLabelLayout(format: tall, stampSize: stamp, settings: settings(.stampTop), placement: .standard),
          let bottom = CombinedLabelLayout(format: tall, stampSize: stamp, settings: settings(.stampBottom), placement: .standard) else {
        throw SelfTestFailure.assertion("Stacked layout must fit 100 × 150 mm")
    }
    try require(top.stampRect.minY > top.addressFormat.heightMM * unit - 0.01, "Stamp on top overlaps the address")
    try require(bottom.stampRect.maxY <= bottom.addressOrigin.y + 0.01, "Stamp below overlaps the address")
    try require(CombinedLabelLayout(format: .custom(widthMM: 50, heightMM: 30), stampSize: stamp, settings: settings(.stampRight), placement: .standard) == nil,
                "A label too small for both must be refused")

    let short = CombinedLabelLayout(format: tall, stampSize: stamp, settings: settings(.stampRight), placement: .standard,
                                    continuousAddressFormat: { .continuous(widthMM: $0, heightMM: 15) })!
    try require(short.format.usesAutomaticHeight && short.format.heightMM * unit >= stamp.height + 2 * unit - 0.01,
                "A short address must still leave room for the stamp")
    let long = CombinedLabelLayout(format: tall, stampSize: stamp, settings: settings(.stampRight), placement: .standard,
                                   continuousAddressFormat: { .continuous(widthMM: $0, heightMM: 60) })!
    try require(abs(long.format.heightMM - 60) < 0.2 && abs(long.addressOrigin.y) < 0.5, "A long address must set the label length")

    let raster = LabelRaster(width: 800, height: 100, bytesPerRow: 100, bitmap: Data(count: 10_000))
    let extended = ContinuousLabelCutGuide.applying(to: raster, additionalFeedMM: 10)
    let standard = ContinuousLabelCutGuide.applying(to: raster)
    try require(extended.height == standard.height + 80, "Additional feed must add exactly its length")
    try require(extended.bitmap.prefix(standard.bitmap.count) == standard.bitmap, "Additional feed moved the cut line")
    try require(extended.bitmap.dropFirst(standard.bitmap.count).allSatisfy { $0 == 0 }, "Additional feed must stay blank")
    let paper = ContinuousLabelCutGuide.printFormat(for: .continuous(heightMM: 30), additionalFeedMM: 10)
    try require(paper.heightMM == 42, "Print format ignores the additional feed")
    print("Combined label tests passed: arrangements, stamp size, refusal, continuous length and additional paper feed")
}
