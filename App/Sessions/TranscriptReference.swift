import Foundation

enum TranscriptReference: Equatable, Hashable, Sendable {
    case file(path: String, line: Int?)
    case web(url: String, label: String?)

    var inlineURL: URL? {
        switch self {
        case .web(let value, _):
            URL(string: value)
        case .file(let path, let line):
            Self.fileURL(path: path, line: line)
        }
    }

    init?(inlineURL: URL) {
        if inlineURL.scheme == "http" || inlineURL.scheme == "https" {
            self = .web(url: inlineURL.absoluteString, label: nil)
            return
        }
        guard inlineURL.scheme == "tenx-file",
              let components = URLComponents(
                url: inlineURL,
                resolvingAgainstBaseURL: false),
              let path = components.queryItems?
                .first(where: { $0.name == "path" })?
                .value,
              !path.isEmpty
        else { return nil }
        let line = components.queryItems?
            .first(where: { $0.name == "line" })?
            .value
            .flatMap(Int.init)
        self = .file(path: path, line: line)
    }

    static func parseInline(
        _ candidate: String,
        label: String? = nil
    ) -> TranscriptReference? {
        parse(candidate, label: label, allowsRelativeFile: true)
    }

    static func extract(from text: String) -> [TranscriptReference] {
        var located: [LocatedReference] = []
        located.append(contentsOf: markdownLinks(in: text))
        located.append(contentsOf: codeReferences(in: text))
        located.append(contentsOf: plainReferences(in: text))
        located.sort { $0.offset < $1.offset }

        var seen: Set<TranscriptReference> = []
        return located.compactMap { candidate in
            seen.insert(candidate.reference).inserted ? candidate.reference : nil
        }
    }

    private struct LocatedReference {
        let offset: String.Index
        let reference: TranscriptReference
    }

    private static func markdownLinks(in text: String) -> [LocatedReference] {
        var result: [LocatedReference] = []
        var cursor = text.startIndex
        while let openLabel = text[cursor...].firstIndex(of: "["),
              let closeLabel = text[openLabel...].firstIndex(of: "]") {
            let afterLabel = text.index(after: closeLabel)
            guard afterLabel < text.endIndex, text[afterLabel] == "(" else {
                cursor = text.index(after: closeLabel)
                continue
            }
            let destinationStart = text.index(after: afterLabel)
            guard let destinationEnd = text[destinationStart...].firstIndex(of: ")") else { break }
            let label = String(text[text.index(after: openLabel)..<closeLabel])
            let destination = String(text[destinationStart..<destinationEnd])
            if let reference = parse(destination, label: label.isEmpty ? nil : label, allowsRelativeFile: true) {
                result.append(LocatedReference(offset: openLabel, reference: reference))
            }
            cursor = text.index(after: destinationEnd)
        }
        return result
    }

    private static func codeReferences(in text: String) -> [LocatedReference] {
        var result: [LocatedReference] = []
        var cursor = text.startIndex
        while let open = text[cursor...].firstIndex(of: "`") {
            let contentStart = text.index(after: open)
            guard let close = text[contentStart...].firstIndex(of: "`") else { break }
            let content = String(text[contentStart..<close])
            if let reference = parse(content, label: nil, allowsRelativeFile: true) {
                result.append(LocatedReference(offset: open, reference: reference))
            }
            cursor = text.index(after: close)
        }
        return result
    }

    private static func plainReferences(in text: String) -> [LocatedReference] {
        var result: [LocatedReference] = []
        var cursor = text.startIndex
        while cursor < text.endIndex {
            while cursor < text.endIndex, text[cursor].isWhitespace {
                cursor = text.index(after: cursor)
            }
            guard cursor < text.endIndex else { break }
            let start = cursor
            while cursor < text.endIndex, !text[cursor].isWhitespace {
                cursor = text.index(after: cursor)
            }
            var token = String(text[start..<cursor])
            token = token.trimmingCharacters(in: CharacterSet(charactersIn: "([{\"'"))
            token = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?)]}\"'"))
            if let reference = parse(token, label: nil, allowsRelativeFile: false) {
                if case .file = reference,
                   hasWhitespacePathContinuation(after: cursor, in: text)
                {
                    continue
                }
                result.append(LocatedReference(offset: start, reference: reference))
            }
        }
        return result
    }

    private static func hasWhitespacePathContinuation(
        after index: String.Index,
        in text: String
    ) -> Bool {
        var cursor = index
        while cursor < text.endIndex, text[cursor].isWhitespace {
            cursor = text.index(after: cursor)
        }
        let start = cursor
        while cursor < text.endIndex, !text[cursor].isWhitespace {
            cursor = text.index(after: cursor)
        }
        guard start < cursor else { return false }
        let token = String(text[start..<cursor])
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?)]}\"'"))
        guard !token.hasPrefix("/") else { return false }
        return isRelativeFilePath(lineSuffix(in: token).path)
    }

    private static func parse(
        _ candidate: String,
        label: String?,
        allowsRelativeFile: Bool
    ) -> TranscriptReference? {
        let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("https://") || value.hasPrefix("http://") {
            guard let url = URL(string: value), url.host != nil else { return nil }
            return .web(url: value, label: label)
        }
        let suffix = lineSuffix(in: value)
        guard suffix.path.hasPrefix("/") || (allowsRelativeFile && isRelativeFilePath(suffix.path)) else {
            return nil
        }
        return .file(path: suffix.path, line: suffix.line)
    }

    private static func isRelativeFilePath(_ path: String) -> Bool {
        if path.hasPrefix("./") || path.hasPrefix("../") { return true }
        guard path.contains("/") else { return false }
        return !URL(filePath: path).pathExtension.isEmpty
    }

    private static func lineSuffix(in path: String) -> (path: String, line: Int?) {
        guard let colon = path.lastIndex(of: ":") else { return (path, nil) }
        let digits = path[path.index(after: colon)...]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let line = Int(digits) else {
            return (path, nil)
        }
        return (String(path[..<colon]), line)
    }

    private static func fileURL(path: String, line: Int?) -> URL? {
        var components = URLComponents()
        components.scheme = "tenx-file"
        components.host = "reference"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        if let line {
            components.queryItems?.append(URLQueryItem(
                name: "line",
                value: String(line)))
        }
        return components.url
    }
}
