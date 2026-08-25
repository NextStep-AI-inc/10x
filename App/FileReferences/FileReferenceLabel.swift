import SwiftUI

struct FileReferenceLabel: View {
    let reference: ResolvedFileReference
    let showsFullPath: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 11, weight: .medium))
            Text(label)
                .font(showsFullPath
                    ? TenXTypography.mono(size: 11)
                    : TenXTypography.body(size: 12, weight: .medium))
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
