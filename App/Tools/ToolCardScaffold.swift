import SwiftUI

struct ToolCardScaffold<Content: View>: View {
    let presentation: ToolPresentation
    let title: String
    let subtitle: String?
    let content: Content

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
                HStack(alignment: .firstTextBaseline, spacing: 8) {
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
                        .accessibilityLabel("Tool status")
                        .accessibilityValue(presentation.phase.label)
                    Text(presentation.durationLabel)
                        .font(TenXTypography.mono(size: 9))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(presentation.phase.label)")
    }

    private var accentColor: Color {
        TenXPalette.color(presentation.isError
            ? TenXPalette.signalRedHex
            : TenXPalette.cyanHex)
    }
}
