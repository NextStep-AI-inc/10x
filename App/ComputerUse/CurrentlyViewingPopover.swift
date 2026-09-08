import SwiftUI

/// "Currently viewing" — near-live frame of the window this session controls.
struct CurrentlyViewingPopover: View {
    let framePNG: Data?
    let windowTitle: String
    let status: String?
    let onStop: () -> Void

    var body: some View {
        CornerCard {
            VStack(alignment: .leading, spacing: 8) {
                if let framePNG, let image = NSImage(data: framePNG) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 360, maxHeight: 240)
                } else {
                    Text("Waiting for first frame…")
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .frame(width: 360, height: 120)
                }
                Text(windowTitle)
                    .font(TenXTypography.body(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let status, !status.isEmpty {
                    Text(status)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .lineLimit(2)
                }
                HStack {
                    Spacer()
                    Button("Stop Computer", action: onStop)
                        .buttonStyle(GhostActionStyle(color: TenXPalette.color(TenXPalette.signalRedHex)))
                        .accessibilityLabel("Stop computer control for this session")
                }
            }
            .padding(10)
        }
        .frame(width: 380)
    }
}
