import Foundation

struct AdvisoryContent: Equatable, Sendable {
    let severity: String
    let guidance: String
    let body: String
}

enum AdvisoryContentParser {
    struct Result: Equatable, Sendable {
        let message: String
        let advisories: [AdvisoryContent]

        var displaySource: String {
            let advisorySource = advisories.map(Self.markdown).joined(separator: "\n\n")
            guard !message.isEmpty else { return advisorySource }
            guard !advisorySource.isEmpty else { return message }
            return message + "\n\n" + advisorySource
        }

        private static func markdown(_ advisory: AdvisoryContent) -> String {
            let lines = [
                "**Advisor feedback**",
                "",
                "Severity: \(advisory.severity.capitalized)",
                "",
                advisory.body,
                "",
                "Guidance: \(advisory.guidance)",
            ]
            return lines
                .flatMap { $0.split(separator: "\n", omittingEmptySubsequences: false) }
                .map { $0.isEmpty ? ">" : "> \($0)" }
                .joined(separator: "\n")
        }
    }

    private static let advisoryPattern = try! NSRegularExpression(
        pattern: #"<advisory severity="([^"\r\n]+)" guidance="([^"\r\n]+)">\r?\n([\s\S]*?)\r?\n</advisory>"#)

    static func parseSuffix(in source: String) -> Result? {
        for candidate in advisoryCandidates(in: source) {
            if let result = parseSuffix(in: source, startingAt: candidate) {
                return result
            }
        }
        return nil
    }

    private static func parseSuffix(in source: String, startingAt start: String.Index) -> Result? {
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        var cursor = NSRange(start..<source.endIndex, in: source).location
        var advisories: [AdvisoryContent] = []

        while cursor < fullRange.length {
            let remaining = NSRange(location: cursor, length: fullRange.length - cursor)
            guard let match = advisoryPattern.firstMatch(
                in: source,
                options: .anchored,
                range: remaining),
                let severityRange = Range(match.range(at: 1), in: source),
                let guidanceRange = Range(match.range(at: 2), in: source),
                let bodyRange = Range(match.range(at: 3), in: source)
            else { return nil }

            let body = String(source[bodyRange])
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            advisories.append(AdvisoryContent(
                severity: String(source[severityRange]),
                guidance: String(source[guidanceRange]),
                body: body))
            cursor = NSMaxRange(match.range)

            while cursor < fullRange.length,
                  let scalarRange = Range(NSRange(location: cursor, length: 1), in: source),
                  source[scalarRange].allSatisfy(\.isWhitespace) {
                cursor += 1
            }
        }

        guard cursor == fullRange.length, !advisories.isEmpty else { return nil }
        return Result(
            message: String(source[..<start]).trimmingCharacters(in: .whitespacesAndNewlines),
            advisories: advisories)
    }

    private static func advisoryCandidates(in source: String) -> [String.Index] {
        var candidates: [String.Index] = []
        var isInsideFence = false
        var lineStart = source.startIndex

        while lineStart < source.endIndex {
            let lineEnd = source[lineStart...].firstIndex(of: "\n") ?? source.endIndex
            let line = source[lineStart..<lineEnd]
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                isInsideFence.toggle()
            } else if !isInsideFence {
                var searchStart = lineStart
                while searchStart < lineEnd,
                      let range = source.range(
                        of: "<advisory ",
                        range: searchStart..<lineEnd) {
                    candidates.append(range.lowerBound)
                    searchStart = range.upperBound
                }
            }
            guard lineEnd < source.endIndex else { break }
            lineStart = source.index(after: lineEnd)
        }
        return candidates
    }
}
