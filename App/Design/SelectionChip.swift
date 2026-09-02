import SwiftUI

/// A compact one-of-many choice: solid when selected, muted when not.
struct SelectionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(TenXTypography.body(size: 11))
                .foregroundStyle(isSelected
                    ? Color.white
                    : TenXPalette.color(TenXPalette.mutedTextHex))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(isSelected
                    ? TenXPalette.color(TenXPalette.nearBlackHex)
                    : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}
