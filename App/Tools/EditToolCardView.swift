import SwiftUI

struct EditToolCardView: View {
    let presentation: ToolPresentation

    var body: some View {
        if let content = ToolContentExtractor.edit(presentation) {
            ToolCardScaffold(
                presentation: presentation,
                title: "Edit",
                subtitle: content.path
            ) {
                HStack(spacing: 10) {
                    Text("+\(content.additions)")
                        .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                    Text("−\(content.removals)")
                        .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                }
                .font(TenXTypography.mono(size: 9, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(content.diff.split(
                        separator: "\n",
                        omittingEmptySubsequences: false).prefix(60).enumerated()), id: \.offset) {
                        _, line in
                        Text(String(line))
                            .font(TenXTypography.mono(size: 10))
                            .foregroundStyle(color(for: line))
                    }
                }
                .textSelection(.enabled)
            }
        } else {
            GenericToolCardView(presentation: presentation)
        }
    }

    private func color(for line: Substring) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return TenXPalette.color(TenXPalette.cyanHex)
        }
        if line.hasPrefix("-") && !line.hasPrefix("---") {
            return TenXPalette.color(TenXPalette.signalRedHex)
        }
        return TenXPalette.color(TenXPalette.nearBlackHex)
    }
}
