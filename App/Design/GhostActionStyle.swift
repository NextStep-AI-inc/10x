import SwiftUI

struct GhostActionStyle: ButtonStyle {
    var color = TenXPalette.color(TenXPalette.cyanHex)

    func makeBody(configuration: Configuration) -> some View {
        GhostActionBody(configuration: configuration, color: color)
    }
}

private struct GhostActionBody: View {
    let configuration: ButtonStyle.Configuration
    let color: Color

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(TenXTypography.body(size: 12, weight: .medium))
            .foregroundStyle(isEnabled
                ? color
                : TenXPalette.color(TenXPalette.mutedTextHex))
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .background(isEnabled && isHovering
                ? TenXPalette.color(TenXPalette.hoverNeutralHex)
                : .clear)
            .contentShape(Rectangle())
            .opacity(isEnabled && configuration.isPressed ? 0.68 : 1)
            .onHover { isHovering = isEnabled && $0 }
    }
}
