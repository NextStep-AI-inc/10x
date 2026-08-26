import Foundation

enum MessageContentParser {
    static func parse(_ source: String) -> ContentDocument {
        var parser = Parser(source: source)
        return ContentDocument(source: source, blocks: parser.blocks())
    }

    static func inline(_ source: String) -> InlineContent {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        let attributed = (try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source)
        return InlineContent(source: source, attributed: attributed)
    }

    private struct Parser {
        let lines: [String]
        var index = 0

        init(source: String) {
            lines = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
        }

        mutating func blocks() -> [ContentBlock] {
            var result: [ContentBlock] = []
            while index < lines.count {
                if trimmed(lines[index]).isEmpty {
                    index += 1
                    continue
                }
                if let block = codeBlock() {
                    result.append(block)
                    continue
                }
                if let block = heading(lines[index]) {
                    result.append(block)
                    index += 1
                    continue
                }
                if let block = tableBlock() {
                    result.append(block)
                    continue
                }
                if isDivider(lines[index]) {
                    result.append(.divider)
                    index += 1
                    continue
                }
                if quoteLine(lines[index]) != nil {
                    result.append(quoteBlock())
                    continue
                }
                if let marker = listMarker(lines[index]) {
                    result.append(.list(list(indent: marker.indent, isOrdered: marker.order != nil)))
                    continue
                }
                result.append(paragraph())
            }
            return result
        }

        private mutating func codeBlock() -> ContentBlock? {
            let opening = trimmed(lines[index])
            guard opening.hasPrefix("```") else { return nil }
            var closingIndex = index + 1
            while closingIndex < lines.count,
                  !trimmed(lines[closingIndex]).hasPrefix("```") {
                closingIndex += 1
            }
            guard closingIndex < lines.count else { return nil }
            let language = String(opening.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            let text = lines[(index + 1)..<closingIndex].joined(separator: "\n")
            index = closingIndex + 1
            return .source(SourcePresentation(
                language: language.isEmpty ? nil : language,
                text: text))
        }

        private mutating func tableBlock() -> ContentBlock? {
            guard index + 1 < lines.count,
                  let headers = tableCells(lines[index]),
                  let delimiter = tableCells(lines[index + 1]),
                  headers.count == delimiter.count,
                  !headers.isEmpty,
                  delimiter.allSatisfy(isTableDelimiter)
            else { return nil }

            index += 2
            var rows: [[InlineContent]] = []
            while index < lines.count, let cells = tableCells(lines[index]) {
                if cells.isEmpty { break }
                let padded = cells + Array(
                    repeating: "",
                    count: max(0, headers.count - cells.count))
                rows.append(Array(padded.prefix(headers.count)).map(MessageContentParser.inline))
                index += 1
            }
            return .table(ContentTable(
                headers: headers.map(MessageContentParser.inline),
                rows: rows))
        }

        private mutating func quoteBlock() -> ContentBlock {
            var quoted: [String] = []
            while index < lines.count, let line = quoteLine(lines[index]) {
                quoted.append(line)
                index += 1
            }
            return .quote(MessageContentParser.parse(quoted.joined(separator: "\n")).blocks)
        }

        private mutating func list(indent: Int, isOrdered: Bool) -> ContentList {
            var items: [ContentListItem] = []
            var firstOrder: Int?

            while index < lines.count,
                  var marker = listMarker(lines[index]),
                  marker.indent == indent,
                  (marker.order != nil) == isOrdered {
                if firstOrder == nil { firstOrder = marker.order }
                index += 1
                var children: [ContentList] = []

                while index < lines.count {
                    if trimmed(lines[index]).isEmpty { break }
                    if let child = listMarker(lines[index]) {
                        if child.indent > indent {
                            children.append(list(
                                indent: child.indent,
                                isOrdered: child.order != nil))
                            continue
                        }
                        break
                    }
                    let continuationIndent = leadingIndent(lines[index])
                    guard continuationIndent > indent else { break }
                    marker.text += "\n" + trimmed(lines[index])
                    index += 1
                }

                items.append(ContentListItem(
                    content: MessageContentParser.inline(marker.text),
                    isChecked: marker.isChecked,
                    children: children))
            }

            let style: ContentList.Style
            if isOrdered {
                style = .ordered(start: firstOrder ?? 1)
            } else if !items.isEmpty, items.allSatisfy({ $0.isChecked != nil }) {
                style = .task
            } else {
                style = .unordered
            }
            return ContentList(style: style, items: items)
        }

        private mutating func paragraph() -> ContentBlock {
            var paragraphLines: [String] = []
            repeat {
                paragraphLines.append(lines[index])
                index += 1
            } while index < lines.count
                && !trimmed(lines[index]).isEmpty
                && !startsBlock(at: index)
            return .paragraph(MessageContentParser.inline(paragraphLines.joined(separator: "\n")))
        }

        private func startsBlock(at lineIndex: Int) -> Bool {
            let line = lines[lineIndex]
            return trimmed(line).hasPrefix("```")
                || heading(line) != nil
                || isTable(at: lineIndex)
                || isDivider(line)
                || quoteLine(line) != nil
                || listMarker(line) != nil
        }

        private func isTable(at lineIndex: Int) -> Bool {
            guard lineIndex + 1 < lines.count,
                  let headers = tableCells(lines[lineIndex]),
                  let delimiter = tableCells(lines[lineIndex + 1])
            else { return false }
            return !headers.isEmpty
                && headers.count == delimiter.count
                && delimiter.allSatisfy(isTableDelimiter)
        }
    }

    private struct ListMarker {
        let indent: Int
        let order: Int?
        var text: String
        let isChecked: Bool?
    }

    private static func heading(_ line: String) -> ContentBlock? {
        let value = trimmed(line)
        let marks = value.prefix(while: { $0 == "#" })
        guard (1...6).contains(marks.count),
              value.dropFirst(marks.count).first == " "
        else { return nil }
        return .heading(
            level: marks.count,
            content: inline(String(value.dropFirst(marks.count + 1))))
    }

    private static func listMarker(_ line: String) -> ListMarker? {
        let indent = leadingIndent(line)
        let value = trimmed(line)

        if ["- ", "* ", "+ "].contains(where: value.hasPrefix) {
            var text = String(value.dropFirst(2))
            var isChecked: Bool?
            let lowered = text.lowercased()
            if lowered.hasPrefix("[ ] ") {
                isChecked = false
                text = String(text.dropFirst(4))
            } else if lowered.hasPrefix("[x] ") {
                isChecked = true
                text = String(text.dropFirst(4))
            }
            return ListMarker(indent: indent, order: nil, text: text, isChecked: isChecked)
        }

        guard let period = value.firstIndex(of: "."),
              period != value.startIndex,
              value[..<period].allSatisfy(\.isNumber),
              let order = Int(value[..<period])
        else { return nil }
        let afterPeriod = value.index(after: period)
        guard afterPeriod < value.endIndex, value[afterPeriod] == " " else { return nil }
        return ListMarker(
            indent: indent,
            order: order,
            text: String(value[value.index(after: afterPeriod)...]),
            isChecked: nil)
    }

    private static func quoteLine(_ line: String) -> String? {
        let value = trimmed(line)
        guard value.hasPrefix(">") else { return nil }
        return String(value.dropFirst().drop(while: { $0 == " " }))
    }

    private static func tableCells(_ line: String) -> [String]? {
        let value = trimmed(line)
        guard value.contains("|") else { return nil }
        var cells = value
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if cells.first?.isEmpty == true { cells.removeFirst() }
        if cells.last?.isEmpty == true { cells.removeLast() }
        return cells
    }

    private static func isTableDelimiter(_ cell: String) -> Bool {
        let value = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return value.count >= 3 && value.allSatisfy { $0 == "-" }
    }

    private static func isDivider(_ line: String) -> Bool {
        let value = trimmed(line).filter { !$0.isWhitespace }
        guard value.count >= 3,
              let marker = value.first,
              ["-", "*", "_"].contains(marker)
        else { return false }
        return value.allSatisfy { $0 == marker }
    }

    private static func leadingIndent(_ line: String) -> Int {
        line.prefix(while: { $0 == " " || $0 == "\t" }).reduce(into: 0) { count, character in
            count += character == "\t" ? 4 : 1
        }
    }

    private static func trimmed(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespaces)
    }
}
