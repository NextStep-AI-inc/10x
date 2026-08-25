import SwiftUI

struct SearchToolCardView: View {
    let presentation: ToolPresentation

    var body: some View {
        if let content = ToolContentExtractor.search(presentation) {
            ToolCardScaffold(
                presentation: presentation,
                title: presentation.name.capitalized,
                subtitle: content.query
            ) {
                if content.matches.isEmpty {
                    Text("No matches")
                        .font(TenXTypography.body(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                } else {
                    Text("\(content.matches.count) matches")
                        .font(TenXTypography.mono(size: 9))
                        .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                    ForEach(Array(content.matches.enumerated()), id: \.offset) { _, match in
                        Text(match)
                            .font(TenXTypography.mono(size: 10))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
            }
        } else {
            GenericToolCardView(presentation: presentation)
        }
    }
}
