import SwiftUI

struct TaskToolCardView: View {
    let presentation: ToolPresentation

    var body: some View {
        if let content = ToolContentExtractor.task(presentation) {
            ToolCardScaffold(
                presentation: presentation,
                title: "Task",
                subtitle: content.title
            ) {
                HStack(spacing: 10) {
                    if let role = content.role { metadata(role) }
                    if let model = content.model { metadata(model) }
                    metadata(content.status)
                }
                if let progress = content.progress, !progress.isEmpty {
                    Text(progress)
                        .font(TenXTypography.body(size: 11))
                        .lineLimit(5)
                        .textSelection(.enabled)
                }
            }
        } else {
            GenericToolCardView(presentation: presentation)
        }
    }

    private func metadata(_ value: String) -> some View {
        Text(value)
            .font(TenXTypography.mono(size: 9))
            .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
    }
}
