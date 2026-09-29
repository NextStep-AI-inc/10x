import SwiftUI

struct GuidanceCardView: View {
    let presentation: GuidancePresentation

    var body: some View {
        CornerCard(color: TenXPalette.color(TenXPalette.mutedTextHex)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Self.title(for: presentation))
                    .font(TenXTypography.body(size: 12, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))

                if let omittedCount = presentation.omittedEarlierCount {
                    Text("\(omittedCount) earlier items omitted")
                        .font(TenXTypography.body(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                } else {
                    if !presentation.preview.isEmpty {
                        Text(presentation.preview)
                            .font(TenXTypography.body(size: 11))
                            .lineLimit(6)
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if presentation.byteCount > 0 {
                        Text(Self.sizeLabel(presentation.byteCount))
                            .font(TenXTypography.mono(size: 10))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.accessibilityLabel(for: presentation))
    }

    static func title(for presentation: GuidancePresentation) -> String {
        if presentation.omittedEarlierCount != nil {
            return "Earlier guidance omitted"
        }
        switch presentation.kind {
        case .advisor:
            return "Advisor note"
        case .agentGuidance:
            return "Agent guidance"
        case .referencedFile:
            return "Referenced file"
        }
    }

    static func sizeLabel(_ byteCount: Int) -> String {
        byteCount < 1_000
            ? "\(byteCount) bytes"
            : String(format: "%.1f KB", Double(byteCount) / 1_000)
    }

    static func accessibilityLabel(for presentation: GuidancePresentation) -> String {
        if let omittedCount = presentation.omittedEarlierCount {
            return "Earlier guidance omitted, \(omittedCount) items"
        }
        var parts = [title(for: presentation)]
        if !presentation.preview.isEmpty {
            parts.append(presentation.preview)
        }
        if presentation.byteCount > 0 {
            parts.append(sizeLabel(presentation.byteCount))
        }
        return parts.joined(separator: ", ")
    }
}
