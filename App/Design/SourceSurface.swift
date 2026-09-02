import AppKit
import SwiftUI

struct SourcePresentation: Equatable, Sendable {
    let language: String?
    let text: String
    let lines: [SourceLine]
    let contentID: UUID

    init(language: String?, text: String) {
        self.language = language
        self.text = text
        contentID = UUID()
        lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { offset, line in
                SourceLine(number: offset + 1, text: String(line))
            }
    }

    init(language: String?, text: String, lines: [SourceLine], contentID: UUID = UUID()) {
        self.language = language
        self.text = text
        self.lines = lines
        self.contentID = contentID
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.language == rhs.language && lhs.text == rhs.text && lhs.lines == rhs.lines
    }
}

struct SourceLine: Equatable, Sendable, Identifiable {
    let number: Int
    let spans: [SourceSpan]
    let rawText: String

    init(number: Int, spans: [SourceSpan]) {
        self.number = number
        self.spans = spans
        rawText = spans.count == 1 ? spans[0].text : spans.map(\.text).joined()
    }

    init(number: Int, text: String) {
        self.number = number
        rawText = text
        spans = [SourceSpan(text: text, role: .plain)]
    }

    var id: Int { number }
    var plainText: String { rawText }

    func characterCount(cappedAt limit: Int) -> Int {
        var count = 0
        var index = rawText.startIndex
        while index < rawText.endIndex, count < limit {
            rawText.formIndex(after: &index)
            count += 1
        }
        return count
    }
}

struct SourceSpan: Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case plain
        case keyword
        case type
        case string
        case number
        case comment
    }

    let text: String
    let role: Role
}

enum SourceTokenizer {
    private struct Profile {
        let keywords: Set<String>
        let types: Set<String>
        let lineCommentMarkers: [String]
        let stringDelimiters: Set<Character>
        let recognizesCapitalizedTypes: Bool
    }

    static func lines(_ text: String, language: String?) -> [SourceLine] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { offset, line in
                SourceLine(
                    number: offset + 1,
                    spans: spans(String(line), language: language))
            }
    }

    static func spans(_ line: String, language: String?) -> [SourceSpan] {
        guard let profile = profile(for: language) else {
            return [SourceSpan(text: line, role: .plain)]
        }

        var result: [SourceSpan] = []
        var index = line.startIndex
        while index < line.endIndex {
            if profile.lineCommentMarkers.contains(where: {
                line[index...].hasPrefix($0)
            }) {
                append(String(line[index...]), role: .comment, to: &result)
                index = line.endIndex
                continue
            }

            let character = line[index]
            if profile.stringDelimiters.contains(character) {
                let start = index
                let delimiter = character
                index = line.index(after: index)
                var isEscaped = false
                while index < line.endIndex {
                    let current = line[index]
                    index = line.index(after: index)
                    if current == delimiter, !isEscaped { break }
                    if current == "\\" {
                        isEscaped.toggle()
                    } else {
                        isEscaped = false
                    }
                }
                append(String(line[start..<index]), role: .string, to: &result)
                continue
            }

            if character.isNumber, isTokenBoundary(before: index, in: line) {
                let start = index
                index = endOfNumber(startingAt: index, in: line)
                append(String(line[start..<index]), role: .number, to: &result)
                continue
            }

            if isIdentifierStart(character) {
                let start = index
                index = line.index(after: index)
                while index < line.endIndex, isIdentifierContinuation(line[index]) {
                    index = line.index(after: index)
                }
                let word = String(line[start..<index])
                let role: SourceSpan.Role
                if profile.keywords.contains(word) {
                    role = .keyword
                } else if profile.types.contains(word)
                    || (profile.recognizesCapitalizedTypes && word.first?.isUppercase == true) {
                    role = .type
                } else {
                    role = .plain
                }
                append(word, role: role, to: &result)
                continue
            }

            let start = index
            index = line.index(after: index)
            append(String(line[start..<index]), role: .plain, to: &result)
        }

        return result.isEmpty ? [SourceSpan(text: "", role: .plain)] : result
    }

    static func languageIdentifier(forPath path: String) -> String? {
        let fileExtension = URL(filePath: path).pathExtension.lowercased()
        return fileExtension.isEmpty ? nil : fileExtension
    }

    private static func profile(for language: String?) -> Profile? {
        guard let language else { return nil }
        let normalized = language
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return switch normalized {
        case "swift":
            Profile(
                keywords: words("actor any as async await break case catch class continue default defer deinit do else enum extension fallthrough false fileprivate for func guard if import in init inout internal is let nil nonisolated open operator private protocol public repeat rethrows return self Self some static struct subscript super switch throw throws true try typealias var where while"),
                types: words("Any Bool Character Data Date Dictionary Double Error Float Int Never Optional Result Set String UInt URL Void"),
                lineCommentMarkers: ["//", "/*"],
                stringDelimiters: ["\"", "'"],
                recognizesCapitalizedTypes: true)
        case "js", "javascript", "jsx", "ts", "typescript", "tsx":
            Profile(
                keywords: words("as async await break case catch class const continue debugger default delete do else enum export extends false finally for from function get if implements import in instanceof interface let new null of package private protected public return set static super switch this throw true try typeof undefined var void while with yield"),
                types: words("Array BigInt Boolean Date Error Map Number Object Promise Record Set String Symbol Unknown"),
                lineCommentMarkers: ["//", "/*"],
                stringDelimiters: ["\"", "'", "`"],
                recognizesCapitalizedTypes: normalized.contains("ts"))
        case "py", "python":
            Profile(
                keywords: words("and as assert async await break class continue def del elif else except False finally for from global if import in is lambda None nonlocal not or pass raise return True try while with yield"),
                types: words("bool bytes dict float int list object set str tuple"),
                lineCommentMarkers: ["#"],
                stringDelimiters: ["\"", "'"],
                recognizesCapitalizedTypes: true)
        case "sh", "bash", "zsh", "shell":
            Profile(
                keywords: words("case do done elif else esac export fi for function if in local readonly return set then unset while"),
                types: [],
                lineCommentMarkers: ["#"],
                stringDelimiters: ["\"", "'", "`"],
                recognizesCapitalizedTypes: false)
        case "c", "h", "cc", "cpp", "cxx", "hpp", "m", "mm", "java", "kt", "kotlin":
            Profile(
                keywords: words("abstract auto boolean break byte case catch char class const continue default do double else enum extends false final finally float for goto if implements import instanceof int interface long native new null package private protected public register return short signed static strictfp struct super switch synchronized this throw throws transient true try typedef union unsigned virtual void volatile while"),
                types: words("Array Boolean Double Float Integer List Long Map Object Set String Vector"),
                lineCommentMarkers: ["//", "/*"],
                stringDelimiters: ["\"", "'"],
                recognizesCapitalizedTypes: true)
        case "go":
            Profile(
                keywords: words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var"),
                types: words("bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr"),
                lineCommentMarkers: ["//", "/*"],
                stringDelimiters: ["\"", "'", "`"],
                recognizesCapitalizedTypes: true)
        case "rs", "rust":
            Profile(
                keywords: words("as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while"),
                types: words("bool char f32 f64 i8 i16 i32 i64 i128 isize str u8 u16 u32 u64 u128 usize Option Result String Vec"),
                lineCommentMarkers: ["//", "/*"],
                stringDelimiters: ["\"", "'"],
                recognizesCapitalizedTypes: true)
        case "rb", "ruby":
            Profile(
                keywords: words("alias and begin break case class def defined do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield"),
                types: words("Array FalseClass Float Hash Integer NilClass Object String Symbol TrueClass"),
                lineCommentMarkers: ["#"],
                stringDelimiters: ["\"", "'"],
                recognizesCapitalizedTypes: true)
        case "json":
            Profile(
                keywords: words("false null true"),
                types: [],
                lineCommentMarkers: [],
                stringDelimiters: ["\""],
                recognizesCapitalizedTypes: false)
        case "yaml", "yml", "toml":
            Profile(
                keywords: words("false null true yes no"),
                types: [],
                lineCommentMarkers: ["#"],
                stringDelimiters: ["\"", "'"],
                recognizesCapitalizedTypes: false)
        case "css", "scss", "less":
            Profile(
                keywords: words("important inherit initial none unset var"),
                types: [],
                lineCommentMarkers: ["/*"],
                stringDelimiters: ["\"", "'"],
                recognizesCapitalizedTypes: false)
        case "html", "xml":
            Profile(
                keywords: [],
                types: [],
                lineCommentMarkers: ["<!--"],
                stringDelimiters: ["\"", "'"],
                recognizesCapitalizedTypes: false)
        default:
            nil
        }
    }

    private static func words(_ value: String) -> Set<String> {
        Set(value.split(separator: " ").map(String.init))
    }

    private static func append(
        _ text: String,
        role: SourceSpan.Role,
        to spans: inout [SourceSpan]
    ) {
        guard !text.isEmpty else { return }
        if spans.last?.role == role {
            let previous = spans.removeLast()
            spans.append(SourceSpan(text: previous.text + text, role: role))
        } else {
            spans.append(SourceSpan(text: text, role: role))
        }
    }

    private static func isTokenBoundary(before index: String.Index, in line: String) -> Bool {
        guard index > line.startIndex else { return true }
        return !isIdentifierContinuation(line[line.index(before: index)])
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character == "$" || character.isLetter
    }

    private static func isIdentifierContinuation(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }

    private static func endOfNumber(
        startingAt start: String.Index,
        in line: String
    ) -> String.Index {
        var index = line.index(after: start)
        if line[start] == "0", index < line.endIndex {
            let prefix = line[index].lowercased()
            let radix: Int? = switch prefix {
            case "x": 16
            case "o": 8
            case "b": 2
            default: nil
            }
            if let radix {
                index = line.index(after: index)
                while index < line.endIndex,
                      line[index] == "_" || isDigit(line[index], radix: radix) {
                    index = line.index(after: index)
                }
                return index
            }
        }

        var hasDecimalPoint = false
        var hasExponent = false
        while index < line.endIndex {
            let character = line[index]
            if character.isNumber || character == "_" {
                index = line.index(after: index)
            } else if character == ".", !hasDecimalPoint, !hasExponent {
                hasDecimalPoint = true
                index = line.index(after: index)
            } else if (character == "e" || character == "E"), !hasExponent {
                hasExponent = true
                index = line.index(after: index)
                if index < line.endIndex, line[index] == "+" || line[index] == "-" {
                    index = line.index(after: index)
                }
            } else {
                break
            }
        }
        return index
    }

    private static func isDigit(_ character: Character, radix: Int) -> Bool {
        guard let value = character.hexDigitValue else { return false }
        return value < radix
    }
}

struct SourceRenderState: Equatable {
    private(set) var contentID: UUID?
    var reveal: ProgressiveReveal

    init(contentID: UUID? = nil, initialLimit: Int) {
        self.contentID = contentID
        reveal = ProgressiveReveal(initialLimit: initialLimit, pageSize: 200)
    }

    func effective(for contentID: UUID, initialLimit: Int) -> Self {
        guard self.contentID == contentID else {
            return Self(contentID: contentID, initialLimit: initialLimit)
        }
        return self
    }

    mutating func reset(contentID: UUID, initialLimit: Int) {
        guard self.contentID != contentID else { return }
        self = Self(contentID: contentID, initialLimit: initialLimit)
    }
}

struct SourceSurface: View {
    let presentation: SourcePresentation
    let previewLineLimit: Int?
    let isInitiallyWrapped: Bool
    @State private var renderState: SourceRenderState

    init(
        presentation: SourcePresentation,
        previewLineLimit: Int? = nil,
        isInitiallyWrapped: Bool = true
    ) {
        self.presentation = presentation
        self.previewLineLimit = previewLineLimit
        self.isInitiallyWrapped = isInitiallyWrapped
        _renderState = State(initialValue: SourceRenderState(
            contentID: presentation.contentID,
            initialLimit: previewLineLimit ?? 200))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SourceCard(
                presentation: presentation,
                lines: Array(visibleLines),
                isInitiallyWrapped: isInitiallyWrapped)
            ProgressiveRevealButton(
                reveal: Binding(
                    get: { effectiveRenderState.reveal },
                    set: {
                        renderState.reset(
                            contentID: presentation.contentID,
                            initialLimit: initialLimit)
                        renderState.reveal = $0
                    }),
                total: presentation.lines.count,
                noun: "lines",
                accessibilityNoun: "source lines")
        }
        .task(id: presentation.contentID) {
            renderState.reset(
                contentID: presentation.contentID,
                initialLimit: initialLimit)
        }
    }

    private var visibleLines: ArraySlice<SourceLine> {
        return presentation.lines.prefix(Self.visibleLineCount(
            total: presentation.lines.count,
            previewLineLimit: previewLineLimit,
            reveal: effectiveRenderState.reveal))
    }

    private var initialLimit: Int { previewLineLimit ?? 200 }

    private var effectiveRenderState: SourceRenderState {
        renderState.effective(
            for: presentation.contentID,
            initialLimit: initialLimit)
    }

    nonisolated static func visibleLineCount(
        total: Int,
        previewLineLimit: Int?,
        reveal: ProgressiveReveal
    ) -> Int {
        let boundedTotal = max(0, total)
        let previewCount = min(boundedTotal, previewLineLimit ?? 200)
        return max(previewCount, reveal.visibleCount(total: boundedTotal))
    }

}

struct SourceCard: View {
    let presentation: SourcePresentation
    let lines: [SourceLine]
    let isInitiallyWrapped: Bool

    @State private var isWrapped: Bool
    @StateObject private var pageLoader: SourcePageLoader

    init(
        presentation: SourcePresentation,
        lines: [SourceLine],
        isInitiallyWrapped: Bool = true
    ) {
        self.presentation = presentation
        self.lines = lines
        self.isInitiallyWrapped = isInitiallyWrapped
        _isWrapped = State(initialValue: isInitiallyWrapped)
        _pageLoader = StateObject(wrappedValue: SourcePageLoader(
            contentID: presentation.contentID,
            initialLines: lines,
            language: presentation.language))
    }

    var body: some View {
        let contentID = presentation.contentID
        VStack(alignment: .leading, spacing: 8) {
            header
            if isWrapped {
                rows(contentID: contentID)
            } else {
                ScrollView(.horizontal) {
                    rows(contentID: contentID).fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(10)
        .background(TenXPalette.color(TenXPalette.hoverNeutralHex))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: SourceLoadID(
            contentID: contentID,
            lineNumbers: lines.map(\.number))) {
            pageLoader.reset(
                contentID: contentID,
                initialLines: lines,
                language: presentation.language)
            await pageLoader.load(
                lines: lines,
                language: presentation.language,
                contentID: contentID)
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(presentation.language?.uppercased() ?? "SOURCE")
                .font(TenXTypography.mono(size: 10, weight: .medium))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            Spacer(minLength: 12)
            Button(isWrapped ? "Scroll" : "Wrap") { isWrapped.toggle() }
                .buttonStyle(GhostActionStyle())
                .accessibilityLabel(isWrapped
                    ? "Use horizontal scrolling for source"
                    : "Wrap source lines")
            Button("Copy") { copy() }
                .buttonStyle(GhostActionStyle())
                .accessibilityLabel("Copy source")
        }
    }

    private func rows(contentID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(lines) { line in
                SourceLineView(
                    line: line,
                    spans: pageLoader.spans(for: line, contentID: contentID) ?? line.spans,
                    showsNumber: presentation.lines.count > 1,
                    isWrapped: isWrapped)
                    .id(SourceLineID(contentID: contentID, number: line.number))
            }
        }
        .frame(maxWidth: isWrapped ? .infinity : nil, alignment: .leading)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(presentation.text, forType: .string)
    }
}

private struct SourceLoadID: Hashable {
    let contentID: UUID
    let lineNumbers: [Int]
}

private struct SourceLineID: Hashable {
    let contentID: UUID
    let number: Int
}

struct SourceLineRenderPresentation: Equatable, Sendable {
    static let disclosureAccessibilityNoun = "source line characters"

    let spans: [SourceSpan]
    let visibleText: String
    let accessibilityText: String
    let hasMore: Bool
    let progressiveTotal: Int

    init(line: SourceLine, spans: [SourceSpan], characterLimit: Int, pageSize: Int = 2_048) {
        let limit = max(0, characterLimit)
        self.spans = Self.prefix(spans, characterLimit: limit)
        visibleText = self.spans.map(\.text).joined()
        accessibilityText = visibleText
        let boundedCount = line.characterCount(cappedAt: limit + pageSize + 1)
        hasMore = boundedCount > limit
        progressiveTotal = hasMore ? min(boundedCount, limit + pageSize) : limit
    }

    func accessibilityLabel(lineNumber: Int) -> String {
        "Line \(lineNumber), \(accessibilityText)"
            + (hasMore ? ". Truncated. Show more characters to continue." : "")
    }

    private static func prefix(_ spans: [SourceSpan], characterLimit: Int) -> [SourceSpan] {
        var remaining = characterLimit
        var result: [SourceSpan] = []
        for span in spans where remaining > 0 {
            let text = String(span.text.prefix(remaining))
            guard !text.isEmpty else { continue }
            result.append(SourceSpan(text: text, role: span.role))
            remaining -= text.count
        }
        return result
    }
}

struct SourceLineView: View {
    let line: SourceLine
    let spans: [SourceSpan]
    let showsNumber: Bool
    let isWrapped: Bool
    @State private var reveal = ProgressiveReveal(initialLimit: 2_048, pageSize: 2_048)

    var body: some View {
        let presentation = SourceLineRenderPresentation(
            line: line,
            spans: spans,
            characterLimit: reveal.limit)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                if showsNumber {
                    Text(String(line.number))
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .frame(width: 28, alignment: .trailing)
                        .accessibilityHidden(true)
                }
                SourceTextView(spans: presentation.spans, isWrapped: isWrapped)
                    .frame(maxWidth: isWrapped ? .infinity : nil, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(presentation.accessibilityLabel(lineNumber: line.number))
            ProgressiveRevealButton(
                reveal: $reveal,
                total: presentation.progressiveTotal,
                noun: "characters",
                accessibilityNoun: SourceLineRenderPresentation.disclosureAccessibilityNoun)
        }
        .frame(minHeight: 16, alignment: .topLeading)
    }
}

struct SourceTextView: View {
    let spans: [SourceSpan]
    let isWrapped: Bool

    var body: some View {
        Text(attributedText)
            .font(TenXTypography.mono(size: 11))
            .textSelection(.enabled)
            .fixedSize(horizontal: !isWrapped, vertical: true)
    }

    private var attributedText: AttributedString {
        spans.reduce(into: AttributedString()) { result, span in
            var value = AttributedString(span.text)
            value.foregroundColor = color(for: span.role)
            result.append(value)
        }
    }

    private func color(for role: SourceSpan.Role) -> Color {
        switch role {
        case .plain, .type:
            TenXPalette.color(TenXPalette.nearBlackHex)
        case .keyword, .number:
            TenXPalette.color(TenXPalette.interactiveCyanHex)
        case .string:
            TenXPalette.color(TenXPalette.signalRedHex)
        case .comment:
            TenXPalette.color(TenXPalette.mutedTextHex)
        }
    }
}
