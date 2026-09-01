import AppKit
import SwiftUI

struct BrandWordmark: View {
    var width: CGFloat = 34

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Text("10x")
                    .font(TenXTypography.accent(size: 18))
            }
        }
        .frame(width: width)
        .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
        .accessibilityLabel("10x")
    }

    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "10x-wordmark", withExtension: "svg") else {
            return nil
        }
        let image = NSImage(contentsOf: url)
        // The asset is a single-color mark. Drawn as a template it takes the
        // foreground style instead of staying near-black on a dark canvas.
        image?.isTemplate = true
        return image
    }()
}
