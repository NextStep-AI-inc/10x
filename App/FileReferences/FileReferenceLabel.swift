import SwiftUI

struct FileReferenceLabel: View {
    let reference: ResolvedFileReference
    let showsFullPath: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            FileTypeIcon(path: reference.originalPath, isAvailable: reference.exists)
                // A plain image's baseline is its bottom edge, which parks the
                // 12pt icon on the text baseline riding above cap height.
                // Report the baseline 2pt up so the icon optically centers.
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            Text(label)
                .font(showsFullPath
                    ? TenXTypography.mono(size: 11)
                    : TenXTypography.body(size: 12, weight: .medium))
                .foregroundStyle(TenXPalette.color(reference.exists
                    ? TenXPalette.nearBlackHex
                    : TenXPalette.mutedTextHex))
                .lineLimit(showsFullPath ? nil : 1)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 32, alignment: .leading)
    }

    private var label: String {
        guard showsFullPath else { return reference.compactLabel }
        return reference.fullPathLabel.replacingOccurrences(of: "/", with: "/\u{200B}")
    }
}
