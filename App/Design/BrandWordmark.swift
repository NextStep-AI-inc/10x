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
        .accessibilityLabel("10x")
    }

    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "10x-wordmark", withExtension: "svg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}
