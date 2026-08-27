import AppKit
import SwiftUI

/// The staged images above the composer footer, each removable.
struct ComposerAttachmentsView: View {
    let attachments: [ComposerAttachment]
    let onRemove: (ComposerAttachment.ID) -> Void

    static let thumbnailSize: CGFloat = 44
    static let bottomInset: CGFloat = 10

    /// Pinned, because a ScrollView takes whatever height it is offered and the
    /// composer sits in a layout with vertical slack above it.
    static var stripHeight: CGFloat { thumbnailSize + bottomInset }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    thumbnail(attachment)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, Self.bottomInset)
        }
        .frame(height: Self.stripHeight)
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Attached images")
    }

    private func thumbnail(_ attachment: ComposerAttachment) -> some View {
        HStack(spacing: 8) {
            image(attachment)
                .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
                .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .font(TenXTypography.body(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                // Pixel counts are not quantities to group: 1200, never 1,200.
                Text("\(attachment.pixelWidth, format: .number.grouping(.never))×\(attachment.pixelHeight, format: .number.grouping(.never)) · \(attachment.sizeLabel)")
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .lineLimit(1)
            }
            .frame(maxWidth: 150, alignment: .leading)

            Button {
                onRemove(attachment.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove \(attachment.name)")
            .accessibilityLabel("Remove \(attachment.name)")
        }
        .padding(.trailing, 4)
        .overlay {
            Rectangle()
                .stroke(TenXPalette.color(TenXPalette.separatorHex), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(attachment.name)
    }

    @ViewBuilder
    private func image(_ attachment: ComposerAttachment) -> some View {
        if let nsImage = NSImage(data: attachment.data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // Encoding produced bytes AppKit will not read back. Say so rather
            // than showing an empty square.
            Text("No preview")
                .font(TenXTypography.mono(size: 8))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(TenXPalette.color(TenXPalette.hoverNeutralHex))
        }
    }
}
