import Foundation
import SwiftUI

struct ResponseMetadataView: View {
    let message: TranscriptMessage

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(Self.labels(
                attribution: message.attribution,
                timestamp: message.timestamp,
                isFinal: message.isFinal,
                stopReason: message.stopReason).enumerated()), id: \.offset) { index, label in
                if index > 0 { Text("·") }
                Text(label)
                    .foregroundStyle(stateColor(label))
            }
        }
        .font(TenXTypography.mono(size: 10))
        .accessibilityElement(children: .combine)
    }

    nonisolated static func labels(
        attribution: TranscriptResponseAttribution,
        timestamp: Date?,
        isFinal: Bool,
        stopReason: String?
    ) -> [String] {
        var labels: [String] = []
        if let model = attribution.model { labels.append(modelLabel(model)) }
        if let mode = attribution.mode { labels.append(mode.capitalized) }
        if let agent = attribution.agent { labels.append(agent.capitalized) }
        if let timestamp { labels.append(timestamp.formatted(date: .omitted, time: .shortened)) }
        if !isFinal {
            labels.append("Streaming")
        } else if let stopReason, ["error", "aborted"].contains(stopReason.lowercased()) {
            labels.append(stopReason.capitalized)
        }
        return labels
    }

    nonisolated private static func modelLabel(_ fullModel: String) -> String {
        let model = fullModel.split(separator: "/").last.map(String.init) ?? fullModel
        return model.split(separator: "-").map { component in
            component.lowercased() == "gpt" ? "GPT" : component.capitalized
        }.joined(separator: "-")
        .replacingOccurrences(of: "-Sol", with: " Sol")
    }

    private func stateColor(_ label: String) -> Color {
        if ["Error", "Aborted"].contains(label) {
            return TenXPalette.color(TenXPalette.signalRedHex)
        }
        if label == "Streaming" {
            return TenXPalette.color(TenXPalette.cyanHex)
        }
        return TenXPalette.color(TenXPalette.mutedTextHex)
    }
}
