import Foundation

struct UnifiedDiff: Equatable {
    let raw: String
    let files: [UnifiedDiffFile]
}

struct UnifiedDiffFile: Equatable, Identifiable {
    let oldPath: String?
    let newPath: String?
    let hunks: [UnifiedDiffHunk]

    var path: String { newPath ?? oldPath ?? "Changed file" }
    var id: String { "\(oldPath ?? "")→\(newPath ?? "")" }
    var additions: Int { hunks.flatMap(\.lines).filter { $0.kind == .addition }.count }
    var removals: Int { hunks.flatMap(\.lines).filter { $0.kind == .removal }.count }
}

struct UnifiedDiffHunk: Equatable, Identifiable {
    let header: String
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [UnifiedDiffLine]

    var id: String { "\(oldStart)-\(newStart)-\(header)" }

    func displayRows(context: Int = 3) -> [UnifiedDiffDisplayRow] {
        guard context > 0 else { return lines.indices.map(UnifiedDiffDisplayRow.line) }
        var rows: [UnifiedDiffDisplayRow] = []
        var index = 0
        while index < lines.count {
            guard lines[index].kind == .context else {
                rows.append(.line(index))
                index += 1
                continue
            }
            let start = index
            while index < lines.count, lines[index].kind == .context { index += 1 }
            let end = index
            let count = end - start
            if count > context * 2 + 1 {
                rows.append(contentsOf: (start..<(start + context)).map(UnifiedDiffDisplayRow.line))
                let hidden = Array((start + context)..<(end - context))
                rows.append(.collapsed(
                    id: "context-\(start)-\(end)",
                    count: hidden.count,
                    lineIndices: hidden))
                rows.append(contentsOf: ((end - context)..<end).map(UnifiedDiffDisplayRow.line))
            } else {
                rows.append(contentsOf: (start..<end).map(UnifiedDiffDisplayRow.line))
            }
        }
        return rows
    }
}

struct UnifiedDiffLine: Equatable {
    enum Kind: Equatable {
        case context
        case addition
        case removal
        case noNewline
    }

    let kind: Kind
    let text: String
    let oldLine: Int?
    let newLine: Int?
}

enum UnifiedDiffDisplayRow: Equatable, Identifiable {
    case line(Int)
    case collapsed(id: String, count: Int, lineIndices: [Int])

    var id: String {
        switch self {
        case .line(let index): "line-\(index)"
        case .collapsed(let id, _, _): id
        }
    }

    var lineIndex: Int? {
        guard case .line(let index) = self else { return nil }
        return index
    }
}
