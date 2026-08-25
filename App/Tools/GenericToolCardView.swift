import Foundation
import OmpKit
import SwiftUI

struct GenericToolCardView: View {
    let presentation: ToolPresentation

    var body: some View {
        ToolCardScaffold(presentation: presentation, title: presentation.name) {
            Text(formatted(presentation.arguments))
                .font(TenXTypography.mono(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .textSelection(.enabled)

            BoundedToolOutputView(
                text: presentation.result.map(outputText) ?? "",
                lineLimit: 12,
                emptyText: presentation.phase == .complete ? "No output" : nil,
                font: TenXTypography.mono(size: 10),
                color: TenXPalette.color(presentation.isError
                    ? TenXPalette.signalRedHex
                    : TenXPalette.nearBlackHex))
        }
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
