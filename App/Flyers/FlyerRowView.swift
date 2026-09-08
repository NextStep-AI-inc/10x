import SwiftUI

struct FlyerRowView: View {
    let flyer: Flyer
    let onAction: (String) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.flyerReduceTransparencyOverride) private var reduceTransparencyOverride

    private var reduceTransparency: Bool {
        reduceTransparencyOverride ?? systemReduceTransparency
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            rowContent(title: flyer.title, detailMinimumWidth: 96)
            rowContent(title: shortTitle, detailMinimumWidth: 0)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 32)
        .background {
            rowBackground
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    TenXPalette.color(TenXPalette.separatorHex),
                    lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func rowContent(
        title displayedTitle: String,
        detailMinimumWidth: CGFloat
    ) -> some View {
        HStack(spacing: 8) {
            toneMark
            title(displayedTitle)
            descriptionViewport
                .frame(
                    minWidth: detailMinimumWidth,
                    maxWidth: .infinity,
                    alignment: .leading)
            actions
            dismissButton
        }
    }

    private var toneMark: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(toneColor)
                .frame(width: 6, height: 6)
            Image(systemName: toneIconName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(toneColor)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(toneLabel)
    }

    private func title(_ displayedTitle: String) -> some View {
        Text(displayedTitle)
            .font(TenXTypography.body(size: 13, weight: .semibold))
            .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(flyer.title)
    }

    private var descriptionViewport: some View {
        MarqueeTextView(
            text: flyer.detail,
            isVisible: true,
            isPaused: false)
            .font(TenXTypography.body(size: 13))
    }

    private var actions: some View {
        HStack(spacing: 0) {
            ForEach(flyer.actions) { action in
                Button(action.title) {
                    onAction(action.id)
                }
                .buttonStyle(GhostActionStyle())
                .fixedSize()
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private var dismissButton: some View {
        if flyer.isDismissible {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(minWidth: 12)
            }
            .buttonStyle(GhostActionStyle(horizontalPadding: 5))
            .accessibilityLabel("Dismiss")
            .help("Dismiss")
            .fixedSize()
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 6)
                .fill(TenXPalette.surfaceElevated)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.ultraThinMaterial)
        }
    }

    private var shortTitle: String {
        let suffix = " while you were away"
        guard flyer.title.hasSuffix(suffix) else { return flyer.title }
        return String(flyer.title.dropLast(suffix.count))
    }

    private var toneColor: Color {
        switch flyer.tone {
        case .information:
            TenXPalette.color(TenXPalette.cyanHex)
        case .attention:
            TenXPalette.color(TenXPalette.yellowHex)
        case .error:
            TenXPalette.color(TenXPalette.signalRedHex)
        }
    }

    private var toneIconName: String {
        switch flyer.tone {
        case .information: "info.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .error: "exclamationmark.octagon.fill"
        }
    }

    private var toneLabel: String {
        switch flyer.tone {
        case .information: "Information"
        case .attention: "Attention"
        case .error: "Error"
        }
    }
}
