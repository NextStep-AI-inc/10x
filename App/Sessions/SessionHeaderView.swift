import SwiftUI

struct SessionHeaderView: View {
    let controller: SessionController

    var body: some View {
        VStack(spacing: 4) {
            Text(controller.title)
                .font(TenXTypography.body(size: 13, weight: .semibold))
                .lineLimit(1)

            if !controller.headerMetadata.presentationItems.isEmpty {
                HStack(spacing: 14) {
                    ForEach(controller.headerMetadata.presentationItems) { item in
                        HStack(spacing: 4) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: 9, weight: .medium))
                            Text(item.value)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(item.accessibilityLabel)
                        .accessibilityValue(item.value)
                    }
                }
                .font(TenXTypography.mono(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .lineLimit(1)
            }
        }
        .frame(maxWidth: 480)
        .frame(height: 54)
        .padding(.leading, 42)
        .padding(.trailing, 92)
    }
}
