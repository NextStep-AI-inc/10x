import AppKit
import SwiftUI

struct FileTypeIcon: View {
    let path: String
    let isAvailable: Bool

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
            } else {
                Image(systemName: "doc")
                    .resizable()
            }
        }
        .scaledToFit()
        .frame(width: 12, height: 12)
        .foregroundStyle(TenXPalette.color(isAvailable
            ? descriptor.colorHex
            : TenXPalette.mutedTextHex))
        .accessibilityHidden(true)
    }

    private var descriptor: FileTypeIconDescriptor {
        FileTypeIconDescriptor.make(path: path)
    }

    private var image: NSImage? {
        guard let assetName = descriptor.assetName,
              let url = Bundle.main.url(
                  forResource: assetName,
                  withExtension: "svg",
                  subdirectory: "FileTypeIcons")
        else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
