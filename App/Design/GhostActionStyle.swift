import SwiftUI

struct GhostActionStyle: ButtonStyle {
    var color = TenXPalette.color(TenXPalette.interactiveCyanHex)
    /// Set to 0 for flush nav controls (e.g. Settings Back) that must align with titles.
    var horizontalPadding: CGFloat = 9

    func makeBody(configuration: Configuration) -> some View {
        GhostActionBody(
            configuration: configuration,
            color: color,
            horizontalPadding: horizontalPadding)
    }
}

struct GhostActionVisualState: Equatable {
    let isEnabled: Bool
    let isHovering: Bool

    var usesMutedForeground: Bool { !isEnabled }
    var foregroundOpacity: Double { 1 }

    var backgroundHex: Int? {
        isEnabled && isHovering ? TenXPalette.hoverNeutralHex : nil
    }
}

private struct GhostActionBody: View {
    let configuration: ButtonStyle.Configuration
    let color: Color
    let horizontalPadding: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        let visualState = GhostActionVisualState(
            isEnabled: isEnabled,
            isHovering: isHovering)

        configuration.label
            .font(TenXTypography.body(size: 12, weight: .medium))
            .foregroundStyle(visualState.usesMutedForeground
                ? TenXPalette.color(TenXPalette.mutedTextHex)
                : color)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: 28)
            .background(visualState.backgroundHex.map(TenXPalette.color) ?? .clear)
            .contentShape(Rectangle())
            .opacity(visualState.foregroundOpacity)
            .onHover { isHovering = isEnabled && $0 }
    }
}
