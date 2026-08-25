import SwiftUI

struct BashToolCardView: View {
    let presentation: ToolPresentation

    var body: some View {
        if let content = ToolContentExtractor.bash(presentation) {
            ToolCardScaffold(presentation: presentation, title: "Bash") {
                Text(content.command)
                    .font(TenXTypography.mono(size: 10, weight: .semibold))
                    .textSelection(.enabled)
                if !content.output.isEmpty {
                    Text(content.output)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(presentation.isError
                            ? TenXPalette.color(TenXPalette.signalRedHex)
                            : TenXPalette.color(TenXPalette.nearBlackHex))
                        .lineLimit(12)
                        .textSelection(.enabled)
                }
            }
        } else {
            GenericToolCardView(presentation: presentation)
        }
    }
}
