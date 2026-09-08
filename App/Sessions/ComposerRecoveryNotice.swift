import SwiftUI

struct ComposerRecoveryNotice: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(TenXTypography.body(size: 12))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                TenXPalette.color(TenXPalette.hoverNeutralHex),
                in: RoundedRectangle(cornerRadius: 10))
            .accessibilityIdentifier("composer.recoveryNotice")
    }
}
