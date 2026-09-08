import Foundation
import OmpKit

struct SessionContextUsage: Equatable, Sendable {
    let tokens: Int
    let contextWindow: Int
    let percent: Double
    let updatedAt: Date

    var remainingTokens: Int {
        tokens >= contextWindow ? 0 : contextWindow - tokens
    }

    var fillFraction: Double {
        min(1, max(0, percent / 100))
    }

    init?(value: JSONValue?, updatedAt: Date = Date()) {
        guard let tokens = value?["tokens"]?.intValue,
              let contextWindow = value?["contextWindow"]?.intValue,
              let reportedPercent = value?["percent"]?.doubleValue,
              tokens >= 0,
              contextWindow > 0,
              reportedPercent.isFinite,
              reportedPercent >= 0
        else { return nil }

        let percent = Double(tokens) / Double(contextWindow) * 100
        guard percent.isFinite else { return nil }
        self.tokens = tokens
        self.contextWindow = contextWindow
        self.percent = percent
        self.updatedAt = updatedAt
    }
}

struct SessionContextBreakdown: Equatable, Sendable {
    struct Category: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        let tokens: Int
    }

    let categories: [Category]
    let contextWindow: Int
    let usedTokens: Int
    let updatedAt: Date
    let autoCompactBufferTokens: Int

    init?(report: String, updatedAt: Date = Date()) {
        let lines = Self.strippingANSI(from: report).split(whereSeparator: \.isNewline).map(String.init)
        guard let header = lines.first,
              let contextWindow = Self.parseHeader(header),
              contextWindow > 0
        else { return nil }

        var values: [String: Int] = [:]
        var autoCompactBufferTokens = 0
        var sawAutoCompactBuffer = false
        var sawFree = false
        var sawRow = false

        for line in lines.dropFirst() {
            if line.hasPrefix("Snapcompact:") || line.hasPrefix("Snapcompact (") { break }
            guard let row = Self.parseRow(line) else { return nil }
            sawRow = true
            switch row.label {
            case "Auto-compact buf":
                guard !sawAutoCompactBuffer else { return nil }
                sawAutoCompactBuffer = true
                autoCompactBufferTokens = row.tokens
            case "Free":
                guard !sawFree else { return nil }
                sawFree = true
            default:
                guard values.updateValue(row.tokens, forKey: row.label) == nil else { return nil }
            }
        }
        guard sawRow else { return nil }

        let definitions = [
            (source: "Messages", id: "messages", label: "Conversation"),
            (source: "System prompt", id: "systemPrompt", label: "System instructions"),
            (source: "System tools", id: "systemTools", label: "Tool definitions"),
            (source: "System context", id: "systemContext", label: "Project context"),
            (source: "Skills", id: "skills", label: "Skills"),
        ]
        var usedTokens = 0
        var categories: [Category] = []
        for definition in definitions {
            let tokens = values[definition.source] ?? 0
            let sum = usedTokens.addingReportingOverflow(tokens)
            guard !sum.overflow else { return nil }
            usedTokens = sum.partialValue
            categories.append(Category(id: definition.id, label: definition.label, tokens: tokens))
        }

        self.categories = categories
        self.contextWindow = contextWindow
        self.usedTokens = usedTokens
        self.updatedAt = updatedAt
        self.autoCompactBufferTokens = autoCompactBufferTokens
    }

    private static let rowLabels = [
        "Auto-compact buf", "System context", "System prompt", "System tools", "Messages", "Skills", "Free",
    ]

    private static func strippingANSI(from text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var output = ""
        var index = 0
        while index < scalars.count {
            guard scalars[index].value == 0x1B,
                  index + 1 < scalars.count,
                  scalars[index + 1].value == 0x5B
            else {
                output.unicodeScalars.append(scalars[index])
                index += 1
                continue
            }
            index += 2
            while index < scalars.count {
                let value = scalars[index].value
                index += 1
                if (0x40...0x7E).contains(value) { break }
            }
        }
        return output
    }

    private static func parseHeader(_ line: String) -> Int? {
        let prefix = "Context window: "
        let tokenMarker = " tokens ("
        let suffix = "% used)"
        guard line.hasPrefix(prefix), line.hasSuffix(suffix),
              let marker = line.range(of: tokenMarker)
        else { return nil }

        let windowText = line[line.index(line.startIndex, offsetBy: prefix.count)..<marker.lowerBound]
        let percentStart = marker.upperBound
        let percentEnd = line.index(line.endIndex, offsetBy: -suffix.count)
        guard let contextWindow = Int(windowText),
              let percent = Double(line[percentStart..<percentEnd]),
              percent.isFinite,
              percent >= 0
        else { return nil }
        return contextWindow
    }

    // ponytail: This intentionally follows OMP's current text report grammar; replace it when OMP exposes structured categories.
    private static func parseRow(_ line: String) -> (label: String, tokens: Int)? {
        guard line.hasPrefix("  ") else { return nil }
        let content = line.dropFirst(2)
        guard let label = rowLabels.first(where: { candidate in
            content.hasPrefix(candidate)
                && content.index(content.startIndex, offsetBy: candidate.count) < content.endIndex
                && content[content.index(content.startIndex, offsetBy: candidate.count)].isWhitespace
        }) else { return nil }

        var remainder = content.dropFirst(label.count).drop(while: \.isWhitespace)
        guard remainder.first == "[", let close = remainder.firstIndex(of: "]") else { return nil }
        let bar = remainder[remainder.index(after: remainder.startIndex)..<close]
        guard !bar.isEmpty, bar.allSatisfy({ $0 == "█" || $0 == "░" || $0 == "·" }) else { return nil }

        remainder = remainder[remainder.index(after: close)...].drop(while: \.isWhitespace)
        guard let percentEnd = remainder.firstIndex(of: "%"),
              let barPercent = Int(remainder[..<percentEnd]),
              (0...100).contains(barPercent)
        else { return nil }

        remainder = remainder[remainder.index(after: percentEnd)...].drop(while: \.isWhitespace)
        let suffix = " tokens"
        guard remainder.hasSuffix(suffix),
              let tokens = Int(remainder.dropLast(suffix.count)),
              tokens >= 0
        else { return nil }
        return (label, tokens)
    }
}
