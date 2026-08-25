import SwiftUI

struct WebToolCardView: View {
    let presentation: ToolPresentation
    @State private var isShowingAllResults = false

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
                    ForEach(visibleResults(content.results)) { result in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.title)
                                .font(TenXTypography.body(size: 11, weight: .semibold))
                            BoundedToolOutputView(
                                text: result.url,
                                lineLimit: 1,
                                font: TenXTypography.mono(size: 10),
                                color: TenXPalette.color(TenXPalette.cyanHex),
                                isDisclosureAlwaysAvailable: true)
                            if let summary = result.summary {
                                BoundedToolOutputView(
                                    text: summary,
                                    lineLimit: 2,
                                    font: TenXTypography.body(size: 10),
                                    color: TenXPalette.color(TenXPalette.mutedTextHex))
                            }
                        }
                    }
                    if content.results.count > Self.compactResultLimit {
                        Button(
                            isShowingAllResults
                                ? "Show fewer"
                                : "Show \(content.results.count - Self.compactResultLimit) more"
                        ) {
                            isShowingAllResults.toggle()
                        }
                        .buttonStyle(GhostActionStyle())
                    }
                }
            }
        } else {
            GenericToolCardView(presentation: presentation)
        }
    }

    nonisolated static let compactResultLimit = 4

    private func visibleResults(_ results: [WebToolResult]) -> [WebToolResult] {
        isShowingAllResults ? results : Array(results.prefix(Self.compactResultLimit))
    }
}
