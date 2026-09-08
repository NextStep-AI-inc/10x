import SwiftUI

struct SessionActivityControl: View {
    let state: SessionActivityState
    let onActivate: () -> Void

    @ViewBuilder
    var body: some View {
        switch state {
        case .ready:
            EmptyView()
        case .needsInput:
            Button(action: onActivate) {
                label
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show pending request")
            .accessibilityHint("Shows the earliest pending request")
        case .working, .failed, .stopped:
            label
        }
    }

    private var label: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(state.color)
                .frame(width: 6, height: 6)
            Text(state.rawValue)
                .font(TenXTypography.body(size: 10, weight: .medium))
                .foregroundStyle(labelColor)
                .lineLimit(1)
            if state == .needsInput {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(labelColor)
                    .accessibilityHidden(true)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.rawValue)
    }

    private var labelColor: Color {
        state == .needsInput
            ? TenXPalette.color(TenXPalette.interactiveCyanHex)
            : TenXPalette.color(TenXPalette.mutedTextHex)
    }
}
