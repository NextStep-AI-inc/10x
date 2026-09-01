struct DiffRenderPresentation: Equatable, Sendable {
    let rows: [DiffRenderRow]
    private let fileHeaders: [Int: DiffRenderFileHeader]
    private let hunkHeaders: [DiffRenderRow.HunkID: DiffRenderHunkHeader]

    init(diff: UnifiedDiff) {
        var rows: [DiffRenderRow] = []
        var fileHeaders: [Int: DiffRenderFileHeader] = [:]
        var hunkHeaders: [DiffRenderRow.HunkID: DiffRenderHunkHeader] = [:]
        for (fileIndex, file) in diff.files.enumerated() {
            let language = SourceTokenizer.languageIdentifier(forPath: file.path)
            fileHeaders[fileIndex] = DiffRenderFileHeader(fileID: fileIndex, path: file.path, additions: file.additions, removals: file.removals)
            for (hunkIndex, hunk) in file.hunks.enumerated() {
                hunkHeaders[DiffRenderRow.HunkID(fileIndex: fileIndex, hunkIndex: hunkIndex)] = DiffRenderHunkHeader(header: hunk.header)
                for displayRow in hunk.displayRows() {
                    switch displayRow {
                    case .line(let lineIndex):
                        rows.append(.line(fileIndex: fileIndex, hunkIndex: hunkIndex, lineIndex: lineIndex, line: hunk.lines[lineIndex], language: language))
                    case .collapsed(let id, _, let lineIndices):
                        rows.append(.collapsed(fileIndex: fileIndex, hunkIndex: hunkIndex, id: id, lineIndices: lineIndices, lines: lineIndices.map { hunk.lines[$0] }, language: language))
                    }
                }
            }
        }
        self.rows = rows
        self.fileHeaders = fileHeaders
        self.hunkHeaders = hunkHeaders
    }

    func rows(revealing limits: [DiffRenderRow.ID: Int]) -> [DiffRenderRow] {
        rows.flatMap { row in
            guard let context = row.collapsedContext else { return [row] }
            let visibleCount = min(max(0, limits[row.id] ?? 0), context.totalCount)
            let visibleLines = context.lines.prefix(visibleCount).enumerated().map { offset, line in
                DiffRenderRow.line(fileIndex: context.fileID, hunkIndex: context.hunkID, lineIndex: context.lineIndices[offset], line: line, language: context.language)
            }
            guard visibleCount < context.totalCount else { return visibleLines }
            return visibleLines + [row.replacingCollapsedContext(context.revealing(visibleCount))]
        }
    }

    func slice(limit: Int) -> DiffRenderSlice {
        slice(rows: rows, limit: limit)
    }

    func slice(rows: [DiffRenderRow], limit: Int) -> DiffRenderSlice {
        let lineRows = rows.filter(\.isLine)
        let visibleLineCount = min(max(0, limit), lineRows.count)
        guard visibleLineCount > 0,
              let finalLine = lineRows.indices.dropFirst(visibleLineCount - 1).first,
              let finalIndex = rows.firstIndex(where: { $0.id == lineRows[finalLine].id })
        else {
            return DiffRenderSlice(rows: [], hasMore: !lineRows.isEmpty)
        }
        return DiffRenderSlice(
            rows: sectionedRows(Array(rows[...finalIndex])), 
            hasMore: visibleLineCount < lineRows.count)
    }

    private func sectionedRows(_ rows: [DiffRenderRow]) -> [DiffRenderRow] {
        var result: [DiffRenderRow] = []
        var previousFileID: Int?
        var previousHunkID: DiffRenderRow.HunkID?
        for row in rows {
            let fileID = row.id.fileIndex
            let hunkID = row.id.hunkIndex.map { DiffRenderRow.HunkID(fileIndex: fileID, hunkIndex: $0) }
            if previousFileID != fileID, let file = fileHeaders[fileID] {
                result.append(.fileHeader(fileIndex: file.fileID, path: file.path, additions: file.additions, removals: file.removals))
            }
            if previousHunkID != hunkID,
               let hunkID,
               let hunk = hunkHeaders[hunkID] {
                result.append(.hunkHeader(fileIndex: hunkID.fileIndex, hunkIndex: hunkID.hunkIndex, header: hunk.header))
            }
            result.append(row)
            previousFileID = fileID
            previousHunkID = hunkID
        }
        return result
    }
}

struct DiffRenderSlice: Equatable, Sendable {
    let rows: [DiffRenderRow]
    let hasMore: Bool

    var lines: [DiffRenderLine] { rows.compactMap(\.line) }
}

struct DiffRenderRow: Equatable, Identifiable, Sendable {
    struct HunkID: Hashable, Sendable {
        let fileIndex: Int
        let hunkIndex: Int
    }

    struct ID: Hashable, Sendable {
        enum Kind: Hashable, Sendable { case fileHeader, hunkHeader, line, collapsedContext }
        let fileIndex: Int
        let hunkIndex: Int?
        let sourceLineIndex: Int?
        let kind: Kind
    }

    enum Content: Equatable, Sendable {
        case fileHeader(DiffRenderFileHeader)
        case hunkHeader(DiffRenderHunkHeader)
        case line(DiffRenderLine)
        case collapsedContext(DiffRenderCollapsedContext)
    }

    let id: ID
    let content: Content

    var fileHeader: DiffRenderFileHeader? {
        guard case .fileHeader(let header) = content else { return nil }
        return header
    }

    var hunkHeader: DiffRenderHunkHeader? {
        guard case .hunkHeader(let header) = content else { return nil }
        return header
    }

    var line: DiffRenderLine? {
        guard case .line(let line) = content else { return nil }
        return line
    }

    var collapsedContext: DiffRenderCollapsedContext? {
        guard case .collapsedContext(let context) = content else { return nil }
        return context
    }

    var isLine: Bool { line != nil }

    static func fileHeader(fileIndex: Int, path: String, additions: Int, removals: Int) -> Self {
        Self(id: ID(fileIndex: fileIndex, hunkIndex: nil, sourceLineIndex: nil, kind: .fileHeader), content: .fileHeader(DiffRenderFileHeader(fileID: fileIndex, path: path, additions: additions, removals: removals)))
    }

    static func hunkHeader(fileIndex: Int, hunkIndex: Int, header: String) -> Self {
        Self(id: ID(fileIndex: fileIndex, hunkIndex: hunkIndex, sourceLineIndex: nil, kind: .hunkHeader), content: .hunkHeader(DiffRenderHunkHeader(header: header)))
    }

    static func line(fileIndex: Int, hunkIndex: Int, lineIndex: Int, line: UnifiedDiffLine, language: String?) -> Self {
        Self(id: ID(fileIndex: fileIndex, hunkIndex: hunkIndex, sourceLineIndex: lineIndex, kind: .line), content: .line(DiffRenderLine(fileID: fileIndex, hunkID: hunkIndex, sourceLineIndex: lineIndex, line: line, language: language)))
    }

    static func collapsed(fileIndex: Int, hunkIndex: Int, id: String, lineIndices: [Int], lines: [UnifiedDiffLine], language: String?) -> Self {
        Self(id: ID(fileIndex: fileIndex, hunkIndex: hunkIndex, sourceLineIndex: lineIndices.first, kind: .collapsedContext), content: .collapsedContext(DiffRenderCollapsedContext(id: id, fileID: fileIndex, hunkID: hunkIndex, lineIndices: lineIndices, lines: lines, language: language, visibleCount: 0)))
    }

    func replacingCollapsedContext(_ context: DiffRenderCollapsedContext) -> Self {
        Self(id: id, content: .collapsedContext(context))
    }
}

struct DiffRenderFileHeader: Equatable, Sendable {
    let fileID: Int
    let path: String
    let additions: Int
    let removals: Int
}

struct DiffRenderHunkHeader: Equatable, Sendable { let header: String }

struct DiffRenderLine: Equatable, Sendable {
    let fileID: Int
    let hunkID: Int
    let sourceLineIndex: Int
    let line: UnifiedDiffLine
    let language: String?
}

struct DiffRenderCollapsedContext: Equatable, Sendable {
    let id: String
    let fileID: Int
    let hunkID: Int
    let lineIndices: [Int]
    let lines: [UnifiedDiffLine]
    let language: String?
    let visibleCount: Int

    var totalCount: Int { lineIndices.count }
    var count: Int { totalCount - visibleCount }

    func revealing(_ visibleCount: Int) -> Self {
        Self(id: id, fileID: fileID, hunkID: hunkID, lineIndices: lineIndices, lines: lines, language: language, visibleCount: visibleCount)
    }
}
