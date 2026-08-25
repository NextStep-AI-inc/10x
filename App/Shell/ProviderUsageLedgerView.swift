import SwiftUI

struct ProviderUsageLedgerView: View {
    let providers: [ProviderUsageProvider]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Usage")
                    .font(TenXTypography.body(size: 9, weight: .semibold))
                    .tracking(1.1)
                    .textCase(.uppercase)

                ForEach(providers) { provider in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(provider.name)
                            .font(TenXTypography.body(size: 10, weight: .semibold))
                            .lineLimit(1)

                        ForEach(provider.limits) { limit in
                            ProviderUsageLimitView(providerName: provider.name, limit: limit)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

private struct ProviderUsageLimitView: View {
    let providerName: String
    let limit: ProviderUsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(limit.label)
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(min(max(limit.percentage, 0), 100))%")
                    .fontWeight(.semibold)

                Text(limit.resetWindow)
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .frame(minWidth: 40, alignment: .trailing)
            }
            .font(TenXTypography.body(size: 9))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(TenXPalette.color(TenXPalette.separatorHex))
                    Rectangle()
                        .fill(toneColor)
                        .frame(width: proxy.size.width * limit.normalizedFraction)
                }
            }
            .frame(height: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(providerName), \(limit.label), \(min(max(limit.percentage, 0), 100)) percent, resets \(limit.resetWindow)"
        )
    }

    private var toneColor: Color {
        switch limit.tone {
        case .standard:
            TenXPalette.color(TenXPalette.cyanHex)
        case .warning:
            TenXPalette.color(TenXPalette.yellowHex)
        case .exhausted:
            TenXPalette.color(TenXPalette.signalRedHex)
        }
    }
}
