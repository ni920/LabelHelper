import AppKit
import SwiftUI

/// White is the physical label, independent of the surrounding macOS appearance.
struct LabelPaperCanvas: View {
    var image: NSImage?
    var placeholder: String? = nil
    var raster = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.45))
            if let image {
                Image(nsImage: image)
                    .interpolation(raster ? .none : .high)
                    .resizable().scaledToFit()
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .padding(24)
                    .accessibilityLabel("Etikettenvorschau")
            } else if let placeholder {
                VStack(spacing: 10) {
                    Image(systemName: "envelope").font(.title2).accessibilityHidden(true)
                    Text(placeholder).font(.callout)
                }.padding(24)
            } else {
                ProgressView("Vorschau wird erstellt …")
            }
        }
    }
}
