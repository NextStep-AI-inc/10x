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
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                    BoundedToolOutputView(
                        text: content.matches.joined(separator: "\n"),
                        lineLimit: 12,
                        font: TenXTypography.mono(size: 10),
                        isDisclosureAlwaysAvailable: content.matches.count > 1
                            || (content.matches.first?.count ?? 0) > 80)
                }
            }
        } else {
            GenericToolCardView(presentation: presentation)
        }
    }
}
