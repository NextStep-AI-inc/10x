import SwiftUI

struct WebToolCardView: View {
    let presentation: ToolPresentation

    var body: some View {
        if let content = ToolContentExtractor.web(presentation) {
            ToolCardScaffold(
                presentation: presentation,
                title: presentation.name == "browser" ? "Browser" : "Web search",
                subtitle: content.queryOrURL
            ) {
                if content.results.isEmpty, let summary = content.summary {
                    BoundedToolOutputView(
                        text: summary,
                        lineLimit: 6,
                        font: TenXTypography.body(size: 11))
                } else if content.results.isEmpty, presentation.phase == .complete {
                    Text("No output")
                        .font(TenXTypography.body(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                } else {
                    ForEach(content.results) { result in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.title)
                                .font(TenXTypography.body(size: 11, weight: .semibold))
                            Text(result.url)
                                .font(TenXTypography.mono(size: 10))
                                .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                                .lineLimit(1)
                            if let summary = result.summary {
                                BoundedToolOutputView(
                                    text: summary,
                                    lineLimit: 2,
                                    font: TenXTypography.body(size: 10),
                                    color: TenXPalette.color(TenXPalette.mutedTextHex))
                            }
                        }
                    }
                }
            }
        } else {
            GenericToolCardView(presentation: presentation)
        }
    }
}
