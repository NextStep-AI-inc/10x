import Foundation
import OmpKit
import SwiftUI

struct GenericToolCardView: View {
    let presentation: ToolPresentation

    var body: some View {
        CornerCard(color: accentColor) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(presentation.name)
                        .font(TenXTypography.body(size: 12, weight: .semibold))
                    Spacer()
                    Text(phaseLabel)
                        .font(TenXTypography.body(size: 10, weight: .medium))
                        .foregroundStyle(accentColor)
                        .accessibilityLabel("Tool status")
                        .accessibilityValue(phaseLabel)
                    Text(durationLabel)
                        .font(TenXTypography.mono(size: 9))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }

                Text(formatted(presentation.arguments))
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .textSelection(.enabled)

                if let result = presentation.result {
                    Text(outputText(result))
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(presentation.isError
                            ? TenXPalette.color(TenXPalette.signalRedHex)
                            : TenXPalette.color(TenXPalette.nearBlackHex))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var phaseLabel: String {
        switch presentation.phase {
        case .running: return "Running"
        case .complete: return "Complete"
        case .failed: return "Error"
        }
    }

    private var accentColor: Color {
        TenXPalette.color(presentation.isError ? TenXPalette.signalRedHex : TenXPalette.cyanHex)
    }

    private var durationLabel: String {
        let end = presentation.endDate ?? Date()
        return String(format: "%.1fs", max(0, end.timeIntervalSince(presentation.startDate)))
    }

    private func outputText(_ value: JSONValue) -> String {
        let text = value["content"]?.arrayValue?
            .compactMap { block in
                guard block["type"]?.stringValue == "text" else { return nil }
                return block["text"]?.stringValue
            }
            .joined(separator: "\n")
        if let text, !text.isEmpty { return text }
        return formatted(value)
    }

    private func formatted(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return "Unavailable" }
        return String(decoding: data, as: UTF8.self)
    }
}
