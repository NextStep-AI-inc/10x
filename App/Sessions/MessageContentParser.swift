import Foundation

enum MessageBlock: Equatable, Identifiable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case unorderedList([String])
    case orderedList([String])
    case quote(String)
    case code(language: String?, text: String)

    var id: String {
        switch self {
        case .paragraph(let text): "paragraph-\(text)"
        case .heading(let level, let text): "heading-\(level)-\(text)"
        case .unorderedList(let items): "unordered-\(items.joined(separator: "|"))"
        case .orderedList(let items): "ordered-\(items.joined(separator: "|"))"
        case .quote(let text): "quote-\(text)"
        case .code(let language, let text): "code-\(language ?? "")-\(text)"
        }
    }
}

enum MessageContentParser {
    static func parse(_ source: String) -> [MessageBlock] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MessageBlock] = []
        var index = 0

        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }
            if let block = codeBlock(lines: lines, index: &index) {
                blocks.append(block)
                continue
            }
            if let heading = heading(lines[index]) {
                blocks.append(heading)
                index += 1
                continue
            }
            if unorderedItem(lines[index]) != nil {
                var items: [String] = []
                while index < lines.count, let item = unorderedItem(lines[index]) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.unorderedList(items))
                continue
            }
            if orderedItem(lines[index]) != nil {
                var items: [String] = []
                while index < lines.count, let item = orderedItem(lines[index]) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.orderedList(items))
                continue
            }
            if quoteLine(lines[index]) != nil {
                var quote: [String] = []
                while index < lines.count, let line = quoteLine(lines[index]) {
                    quote.append(line)
                    index += 1
                }
                blocks.append(.quote(quote.joined(separator: "\n")))
                continue
            }

            var paragraph: [String] = []
            repeat {
                paragraph.append(lines[index])
                index += 1
            } while index < lines.count
                && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty
                && !startsBlock(lines[index])
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        }
        return blocks
    }

    private static func codeBlock(lines: [String], index: inout Int) -> MessageBlock? {
        let opening = lines[index].trimmingCharacters(in: .whitespaces)
        guard opening.hasPrefix("```") else { return nil }
        var close = index + 1
        while close < lines.count,
              !lines[close].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            close += 1
        }
        guard close < lines.count else { return nil }
        let language = String(opening.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        let text = lines[(index + 1)..<close].joined(separator: "\n")
        index = close + 1
        return .code(language: language.isEmpty ? nil : language, text: text)
    }

    private static func startsBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```")
            || heading(line) != nil
            || unorderedItem(line) != nil
            || orderedItem(line) != nil
            || quoteLine(line) != nil
    }

    private static func heading(_ line: String) -> MessageBlock? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let marks = trimmed.prefix(while: { $0 == "#" })
        guard (1...6).contains(marks.count),
              trimmed.dropFirst(marks.count).first == " "
        else { return nil }
        return .heading(
            level: marks.count,
            text: String(trimmed.dropFirst(marks.count + 1)))
    }

    private static func unorderedItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 2,
              ["- ", "* ", "+ "].contains(where: trimmed.hasPrefix)
        else { return nil }
        return String(trimmed.dropFirst(2))
    }

    private static func orderedItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let period = trimmed.firstIndex(of: "."),
              period != trimmed.startIndex,
              trimmed[..<period].allSatisfy(\.isNumber)
        else { return nil }
        let after = trimmed.index(after: period)
        guard after < trimmed.endIndex, trimmed[after] == " " else { return nil }
        return String(trimmed[trimmed.index(after: after)...])
    }

    private static func quoteLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return nil }
        return String(trimmed.dropFirst().drop(while: { $0 == " " }))
    }
}
