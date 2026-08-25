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
                    Text(summary)
                        .font(TenXTypography.body(size: 11))
                        .lineLimit(6)
                        .textSelection(.enabled)
                } else {
                    ForEach(content.results) { result in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.title)
                                .font(TenXTypography.body(size: 11, weight: .semibold))
                            Text(result.url)
                                .font(TenXTypography.mono(size: 9))
                                .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                                .lineLimit(1)
                            if let summary = result.summary {
                                Text(summary)
                                    .font(TenXTypography.body(size: 10))
                                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                                    .lineLimit(2)
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
