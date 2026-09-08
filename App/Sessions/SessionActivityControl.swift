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
                .foregroundStyle(state.color)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.rawValue)
    }
}
