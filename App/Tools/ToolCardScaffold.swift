import SwiftUI

struct ToolCardScaffold<Content: View>: View {
    let presentation: ToolPresentation
    let title: String
    let subtitle: String?
    let content: Content
    @Environment(\.toolDisclosureState) private var disclosureState
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled
    @State private var localChoice: Bool?

    init(
        presentation: ToolPresentation,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.presentation = presentation
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        CornerCard(color: accentColor) {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: toggle) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .frame(width: 10)
                        Text(title)
                            .font(TenXTypography.body(size: 12, weight: .semibold))
                        if let subtitle {
                            Text(subtitle)
                                .font(TenXTypography.mono(size: 9))
                                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(presentation.phase.label)
                            .font(TenXTypography.body(size: 10, weight: .medium))
                            .foregroundStyle(accentColor)
                        Text(presentation.durationLabel)
                            .font(TenXTypography.mono(size: 9))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    }
                    .contentShape(Rectangle())
                    .frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title), \(presentation.phase.label)")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint(isExpanded ? "Collapses tool details" : "Expands tool details")

                if isExpanded {
                    content
                        .transition(isReduceMotionEnabled ? .identity : .opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(presentation.phase.label)")
    }

    private var isExpanded: Bool {
        disclosureState?.isExpanded(for: presentation)
            ?? localChoice
            ?? ToolDisclosureState.defaultExpanded(for: presentation)
    }

    private func toggle() {
        let update = {
            if let disclosureState {
                disclosureState.setExpanded(!isExpanded, for: presentation)
            } else {
                localChoice = !isExpanded
            }
        }
        if isReduceMotionEnabled { update() }
        else { withAnimation(.easeInOut(duration: 0.14), update) }
    }

    private var accentColor: Color {
        TenXPalette.color(presentation.isError
            ? TenXPalette.signalRedHex
            : TenXPalette.cyanHex)
    }
}
