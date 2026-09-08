import Foundation

enum UnifiedDiffParser {
    static func parse(_ raw: String, fallbackPath: String? = nil) -> UnifiedDiff? {
        let source = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var files: [UnifiedDiffFile] = []
        var file: FileBuilder?
        var hunk: HunkBuilder?

        func finishedFile(_ builder: FileBuilder?) -> UnifiedDiffFile? {
            guard let builder, !builder.hunks.isEmpty else { return nil }
            return UnifiedDiffFile(
                oldPath: builder.oldPath,
                newPath: builder.newPath,
                hunks: builder.hunks)
        }

        func finishedHunk(_ builder: HunkBuilder?) -> UnifiedDiffHunk? {
            guard let builder else { return nil }
            return UnifiedDiffHunk(
                header: builder.header,
                oldStart: builder.oldStart,
                oldCount: builder.oldCount,
                newStart: builder.newStart,
                newCount: builder.newCount,
                lines: builder.lines)
        }

        for line in source {
            if line.hasPrefix("diff --git ") {
                if let completed = finishedHunk(hunk) { file?.hunks.append(completed) }
                hunk = nil
                if let completed = finishedFile(file) { files.append(completed) }
                let paths = diffPaths(line)
                file = FileBuilder(oldPath: paths.old, newPath: paths.new, hunks: [])
                continue
            }
            if line.hasPrefix("--- ") {
                if hunk != nil || file?.hunks.isEmpty == false {
                    if let completed = finishedHunk(hunk) { file?.hunks.append(completed) }
                    hunk = nil
                    if let completed = finishedFile(file) { files.append(completed) }
                    file = nil
                }
                if file == nil { file = FileBuilder(oldPath: nil, newPath: nil, hunks: []) }
                file?.oldPath = path(String(line.dropFirst(4)))
                continue
            }
            if line.hasPrefix("+++ ") {
                if file == nil { file = FileBuilder(oldPath: nil, newPath: nil, hunks: []) }
                file?.newPath = path(String(line.dropFirst(4)))
                continue
            }
            if line.hasPrefix("@@"), let range = hunkRange(line) {
                if file == nil {
                    file = FileBuilder(oldPath: fallbackPath, newPath: fallbackPath, hunks: [])
                }
                if let completed = finishedHunk(hunk) { file?.hunks.append(completed) }
                hunk = HunkBuilder(
                    header: line,
                    oldStart: range.oldStart,
                    oldCount: range.oldCount,
                    newStart: range.newStart,
                    newCount: range.newCount,
                    oldLine: range.oldStart,
                    newLine: range.newStart,
                    lines: [])
                continue
            }
            guard var current = hunk else { continue }
            let parsed: UnifiedDiffLine?
            if line.hasPrefix("+") {
                parsed = UnifiedDiffLine(
                    kind: .addition,
                    text: String(line.dropFirst()),
                    oldLine: nil,
                    newLine: current.newLine)
                current.newLine += 1
            } else if line.hasPrefix("-") {
                parsed = UnifiedDiffLine(
                    kind: .removal,
                    text: String(line.dropFirst()),
                    oldLine: current.oldLine,
                    newLine: nil)
                current.oldLine += 1
            } else if line.hasPrefix(" ") {
                parsed = UnifiedDiffLine(
                    kind: .context,
                    text: String(line.dropFirst()),
                    oldLine: current.oldLine,
                    newLine: current.newLine)
                current.oldLine += 1
                current.newLine += 1
            } else if line.hasPrefix("\\ No newline") {
                parsed = UnifiedDiffLine(
                    kind: .noNewline,
                    text: line,
                    oldLine: nil,
                    newLine: nil)
            } else {
                parsed = nil
            }
            if let parsed { current.lines.append(parsed) }
            hunk = current
        }

        if let completed = finishedHunk(hunk) { file?.hunks.append(completed) }
        if let completed = finishedFile(file) { files.append(completed) }
        guard !files.isEmpty else {
            return parseCursorNumbered(raw, fallbackPath: fallbackPath)
        }
        return UnifiedDiff(raw: raw, files: files)
    }

    private static func parseCursorNumbered(
        _ raw: String,
        fallbackPath: String?
    ) -> UnifiedDiff? {
        let source = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var hunks: [UnifiedDiffHunk] = []
        var lines: [UnifiedDiffLine] = []
        var hasChanges = false

        func finishHunk() {
            guard !lines.isEmpty else { return }
            let oldLines = lines.compactMap(\.oldLine)
            let newLines = lines.compactMap(\.newLine)
            let oldStart = oldLines.min() ?? newLines.min() ?? 1
            let newStart = newLines.min() ?? oldLines.min() ?? 1
            let oldCount = oldLines.count
            let newCount = newLines.count
            hunks.append(UnifiedDiffHunk(
                header: "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@",
                oldStart: oldStart,
                oldCount: oldCount,
                newStart: newStart,
                newCount: newCount,
                lines: lines))
            lines.removeAll(keepingCapacity: true)
        }

        for line in source {
            if line.isEmpty {
                finishHunk()
                continue
            }
            guard let parsed = cursorNumberedLine(line) else { return nil }
            lines.append(parsed)
            hasChanges = hasChanges || parsed.kind == .addition || parsed.kind == .removal
        }
        finishHunk()

        guard hasChanges, !hunks.isEmpty else { return nil }
        return UnifiedDiff(
            raw: raw,
            files: [UnifiedDiffFile(
                oldPath: fallbackPath,
                newPath: fallbackPath,
                hunks: hunks)])
    }

    private static func cursorNumberedLine(_ line: String) -> UnifiedDiffLine? {
        guard let marker = line.first,
              marker == " " || marker == "+" || marker == "-",
              let separator = line.firstIndex(of: "|")
        else { return nil }
        let numberStart = line.index(after: line.startIndex)
        guard numberStart < separator else { return nil }
        let numberText = line[numberStart..<separator]
        guard numberText.allSatisfy(\.isNumber), let number = Int(numberText) else { return nil }
        let text = String(line[line.index(after: separator)...])
        return switch marker {
        case "+": UnifiedDiffLine(kind: .addition, text: text, oldLine: nil, newLine: number)
        case "-": UnifiedDiffLine(kind: .removal, text: text, oldLine: number, newLine: nil)
        default: UnifiedDiffLine(kind: .context, text: text, oldLine: number, newLine: number)
        }
    }

    private struct FileBuilder {
        var oldPath: String?
        var newPath: String?
        var hunks: [UnifiedDiffHunk]
    }

    private struct HunkBuilder {
        let header: String
        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
        var oldLine: Int
        var newLine: Int
        var lines: [UnifiedDiffLine]
    }

    private static func diffPaths(_ line: String) -> (old: String?, new: String?) {
        let parts = line.split(separator: " ")
        guard parts.count >= 4 else { return (nil, nil) }
        return (path(String(parts[2])), path(String(parts[3])))
    }

    private static func path(_ source: String) -> String? {
        let value = source.split(separator: "\t", maxSplits: 1).first.map(String.init) ?? source
        guard value != "/dev/null" else { return nil }
        if value.hasPrefix("a/") || value.hasPrefix("b/") { return String(value.dropFirst(2)) }
        return value
    }

    private static func hunkRange(
        _ line: String
    ) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)? {
        let parts = line.split(separator: " ")
        guard parts.count >= 3,
              let old = range(String(parts[1]), prefix: "-"),
              let new = range(String(parts[2]), prefix: "+")
        else { return nil }
        return (old.start, old.count, new.start, new.count)
    }

    private static func range(_ source: String, prefix: Character) -> (start: Int, count: Int)? {
        guard source.first == prefix else { return nil }
        let parts = source.dropFirst().split(separator: ",", maxSplits: 1)
        guard let start = parts.first.flatMap({ Int($0) }) else { return nil }
        return (start, parts.count == 2 ? (Int(parts[1]) ?? 1) : 1)
    }
}
