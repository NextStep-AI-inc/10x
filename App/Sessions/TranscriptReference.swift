import Foundation

enum TranscriptReference: Equatable, Hashable {
    case file(path: String, line: Int?)
    case web(url: String, label: String?)

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
                result.append(LocatedReference(offset: start, reference: reference))
            }
        }
        return result
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
        return URL(filePath: path).lastPathComponent.contains(".")
    }

    private static func lineSuffix(in path: String) -> (path: String, line: Int?) {
        guard let colon = path.lastIndex(of: ":") else { return (path, nil) }
        let digits = path[path.index(after: colon)...]
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let line = Int(digits) else {
            return (path, nil)
        }
        return (String(path[..<colon]), line)
    }
}
