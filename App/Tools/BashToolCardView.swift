import SwiftUI

struct BashToolCardView: View {
    let presentation: ToolPresentation

    var body: some View {
        if let content = ToolContentExtractor.bash(presentation) {
            ToolCardScaffold(presentation: presentation, title: "Bash") {
                Text(content.command)
                    .font(TenXTypography.mono(size: 10, weight: .semibold))
                    .textSelection(.enabled)
                BoundedToolOutputView(
                    text: content.output,
                    lineLimit: 12,
                    emptyText: presentation.phase == .complete ? "No output" : nil,
                    font: TenXTypography.mono(size: 10),
                    color: TenXPalette.color(presentation.isError
                        ? TenXPalette.signalRedHex
                        : TenXPalette.nearBlackHex))
            }
        } else {
            GenericToolCardView(presentation: presentation)
        }
    }
}
