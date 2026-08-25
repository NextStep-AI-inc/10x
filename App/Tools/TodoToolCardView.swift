import SwiftUI

struct TodoToolCardView: View {
    let presentation: ToolPresentation

    var body: some View {
        let items = ToolContentExtractor.todos(presentation)
        if !items.isEmpty {
            ToolCardScaffold(presentation: presentation, title: "Todo") {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(item.isComplete ? "DONE" : item.status.uppercased())
                            .font(TenXTypography.mono(size: 8, weight: .semibold))
                            .foregroundStyle(item.isComplete
                                ? TenXPalette.color(TenXPalette.cyanHex)
                                : TenXPalette.color(TenXPalette.yellowHex))
                            .frame(width: 62, alignment: .leading)
                        Text(item.text)
                            .font(TenXTypography.body(size: 11))
                    }
                }
            }
        } else {
            GenericToolCardView(presentation: presentation)
        }
    }
}
