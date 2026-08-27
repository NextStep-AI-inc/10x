import SwiftUI

/// The onboarding list row: a title over an optional detail line, a trailing
/// accessory, and the 1pt rule that separates rows. Shared by the provider and
/// project steps so the two lists cannot drift apart.
struct OnboardingRowView<Accessory: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TenXTypography.body(size: 14, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                if let detail {
                    Text(detail)
                        .font(TenXTypography.body(size: 12))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer(minLength: 12)
            accessory()
        }
        .frame(height: 42)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TenXPalette.color(TenXPalette.separatorHex))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Placeholder rows shown while a step's list is loading.
struct OnboardingSkeletonRows: View {
    var count = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(TenXPalette.color(TenXPalette.separatorHex))
                            .frame(width: 128, height: 12)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(TenXPalette.color(TenXPalette.separatorHex))
                            .frame(width: 96, height: 10)
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: 3)
                        .fill(TenXPalette.color(TenXPalette.separatorHex))
                        .frame(width: 60, height: 12)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(TenXPalette.color(TenXPalette.separatorHex))
                        .frame(height: 1)
                }
                .accessibilityHidden(true)
            }
        }
    }
}
