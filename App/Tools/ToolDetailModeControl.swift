import SwiftUI

struct ToolDetailModeControl: View {
    let mode: ToolDetailMode
    let onSelect: (ToolDetailMode) -> Void

    var body: some View {
        HStack(spacing: 2) {
            Text("DETAIL")
                .font(TenXTypography.mono(size: 9, weight: .semibold))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                // The container carries the spoken label, so the glyphs would
                // otherwise be read twice.
                .accessibilityHidden(true)
            ForEach(ToolDetailMode.allCases) { option in
                SelectionChip(title: option.title, isSelected: option == mode) {
                    onSelect(option)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tool detail")
        .accessibilityValue(mode.accessibilityTitle)
    }
}
