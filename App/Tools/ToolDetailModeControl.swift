import SwiftUI

struct ToolDetailModeControl: View {
    let mode: ToolDetailMode
    var showsLegend: Bool = true
    let onSelect: (ToolDetailMode) -> Void

    var body: some View {
        HStack(spacing: 2) {
            if showsLegend {
                Text("DETAIL")
                    .font(TenXTypography.mono(size: 9, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    // The container carries the spoken label, so the glyphs would
                    // otherwise be read twice.
                    .accessibilityHidden(true)
            }
            ForEach(ToolDetailMode.allCases) { option in
                SelectionChip(title: option.title, isSelected: option == mode) {
                    onSelect(option)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Model expansion")
        .accessibilityValue(mode.accessibilityTitle)
    }
}
