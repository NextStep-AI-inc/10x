import AppKit
import SwiftUI

enum DiffViewLayout {
    static func shouldHideFileHeader(
        fileCount: Int,
        diffPath: String?,
        topHeaderPath: String?
    ) -> Bool {
        guard fileCount == 1,
              let diffPath = normalizedPath(diffPath),
              let topHeaderPath = normalizedPath(topHeaderPath)
        else { return false }
        return diffPath == topHeaderPath
    }

    private static func normalizedPath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let standardized = NSString(string: path).standardizingPath
        guard !standardized.isEmpty,
              path.hasPrefix("/") == standardized.hasPrefix("/")
        else { return nil }
        return standardized
    }
}

struct DiffView: View {
    let diff: UnifiedDiff
    private let topHeaderPath: String?
    private let presentation: DiffRenderPresentation
    @State private var isWrapped = true
    @State private var renderState = DiffRenderState()
    @StateObject private var pageLoader: DiffPageLoader

    init(
        diff: UnifiedDiff,
        fallbackPath _: String?,
        topHeaderPath: String? = nil
    ) {
        self.diff = diff
        self.topHeaderPath = topHeaderPath
        let presentation = DiffRenderPresentation(diff: diff)
        self.presentation = presentation
        _pageLoader = StateObject(wrappedValue: DiffPageLoader(
            contentID: presentation.contentID,
            initialRows: presentation.slice(limit: 200).rows))
    }

    private var visibleRows: [DiffRenderRow] {
        presentation.slice(using: renderState).rows
    }

    private var effectiveRenderState: DiffRenderState {
        renderState.effective(for: presentation.contentID)
    }

    private var visibleLineIDs: [DiffRenderRow.ID] {
        visibleRows.filter(\.isLine).map(\.id)
    }

    private var fileSections: [DiffRenderFileSection] {
        var files: [DiffRenderFileSection] = []
        for row in visibleRows {
            if let header = row.fileHeader {
                files.append(DiffRenderFileSection(header: header, hunks: []))
            } else if let header = row.hunkHeader {
                guard !files.isEmpty else { continue }
                files[files.count - 1].hunks.append(DiffRenderHunkSection(
                    id: row.id,
                    header: header,
                    rows: []))
            } else if !files.isEmpty, !files[files.count - 1].hunks.isEmpty {
                files[files.count - 1].hunks[files[files.count - 1].hunks.count - 1].rows.append(row)
            }
        }
        return files
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            fileViews
            ProgressiveRevealButton(
                reveal: Binding(
                    get: { effectiveRenderState.reveal },
                    set: {
                        renderState.reset(contentID: presentation.contentID)
                        renderState.reveal = $0
                    }),
                total: presentation.lineCount(
                    revealing: effectiveRenderState.contextReveals.mapValues(\.limit)),
                noun: "lines",
                accessibilityNoun: "diff lines")
        }
        .task(id: DiffRenderLoadID(contentID: presentation.contentID, lineIDs: visibleLineIDs)) {
            renderState.reset(contentID: presentation.contentID)
            let rows = presentation.slice(using: renderState).rows
            pageLoader.reset(contentID: presentation.contentID, initialRows: presentation.slice(limit: 200).rows)
            await pageLoader.load(rows: rows, contentID: presentation.contentID)
        }
    }

    private var fileViews: some View {
        ForEach(fileSections) { file in
            if file.header.fileID > 0 { Divider() }
            fileView(
                file,
                showsHeader: showsFileHeader,
                showsActions: file.header.fileID == fileSections.first?.header.fileID)
        }
    }

    private func fileView(
        _ file: DiffRenderFileSection,
        showsHeader: Bool,
        showsActions: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                fileHeader(file, showsActions: showsActions)
            } else if showsActions {
                trailingActionRow
            }
            ForEach(file.hunks) { hunk in
                hunkView(hunk)
            }
        }
    }

    private func fileHeader(
        _ file: DiffRenderFileSection,
        showsActions: Bool
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                fileReference(file)
                Spacer(minLength: 8)
                if showsActions { actionRow }
            }
            VStack(alignment: .leading, spacing: 4) {
                fileReference(file)
                if showsActions { trailingActionRow }
            }
        }
    }

    private func fileReference(_ file: DiffRenderFileSection) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            TranscriptReferenceView(reference: file.header.reference)
            Text("+\(file.header.additions) −\(file.header.removals)")
                .font(TenXTypography.mono(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
    }

    private var actionRow: some View {
        HStack(spacing: 2) {
            Button(isWrapped ? "Scroll" : "Wrap") { isWrapped.toggle() }
                .buttonStyle(GhostActionStyle())
                .accessibilityLabel(isWrapped ? "Use horizontal scrolling for diff" : "Wrap diff lines")
            Button("Copy patch") { copy(diff.raw) }
                .buttonStyle(GhostActionStyle())
        }
        .font(TenXTypography.mono(size: 10, weight: .semibold))
    }

    private var trailingActionRow: some View {
        HStack {
            Spacer(minLength: 0)
            actionRow
        }
    }

    private func hunkView(_ hunk: DiffRenderHunkSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressiveTextView(
                text: hunk.header.header,
                accessibilityNoun: "diff hunk characters"
            ) { text in
                Text(text)
                    .font(TenXTypography.mono(size: 10, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
            if isWrapped {
                hunkRows(hunk)
            } else {
                ScrollView(.horizontal) {
                    hunkRows(hunk).fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    private func hunkRows(_ hunk: DiffRenderHunkSection) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(hunk.rows) { row in
                if let line = row.line {
                    lineView(line, rowID: row.id)
                } else if let context = row.collapsedContext {
                    collapsedContextView(context, rowID: row.id)
                }
            }
        }
        .frame(maxWidth: isWrapped ? .infinity : nil, alignment: .leading)
    }

    private func collapsedContextView(_ context: DiffRenderCollapsedContext, rowID: DiffRenderRow.ID) -> some View {
        Button("Show \(min(200, context.count)) more unchanged lines") {
            if let nextState = presentation.revealingNextContext(rowID, from: renderState) {
                renderState = nextState
            }
        }
        .font(TenXTypography.mono(size: 10))
        .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
        .buttonStyle(.plain)
        .frame(minHeight: 24)
    }

    private func lineView(_ renderLine: DiffRenderLine, rowID: DiffRenderRow.ID) -> some View {
        DiffLineView(
            renderLine: renderLine,
            spans: pageLoader.spans(for: rowID, contentID: presentation.contentID)
                ?? [SourceSpan(text: renderLine.line.text, role: .plain)],
            isWrapped: isWrapped,
            marker: marker(for: renderLine.line.kind),
            markerColor: color(for: renderLine.line.kind),
            backgroundColor: backgroundColor(for: renderLine.line.kind),
            accessibilityPrefix: label(for: renderLine.line.kind))
    }

    private var showsFileHeader: Bool {
        !DiffViewLayout.shouldHideFileHeader(
            fileCount: diff.files.count,
            diffPath: diff.files.first?.path,
            topHeaderPath: topHeaderPath)
    }

    private func marker(for kind: UnifiedDiffLine.Kind) -> String {
        switch kind {
        case .addition: "+"
        case .removal: "−"
        case .context: " "
        case .noNewline: "↳"
        }
    }

    private func color(for kind: UnifiedDiffLine.Kind) -> Color {
        switch kind {
        case .addition: TenXPalette.color(TenXPalette.cyanHex)
        case .removal: TenXPalette.color(TenXPalette.signalRedHex)
        case .context: TenXPalette.color(TenXPalette.nearBlackHex)
        case .noNewline: TenXPalette.color(TenXPalette.mutedTextHex)
        }
    }

    private func backgroundColor(for kind: UnifiedDiffLine.Kind) -> Color {
        switch kind {
        case .addition: TenXPalette.color(TenXPalette.cyanHex).opacity(0.08)
        case .removal: TenXPalette.color(TenXPalette.signalRedHex).opacity(0.07)
        case .context, .noNewline: .clear
        }
    }

    private func label(for kind: UnifiedDiffLine.Kind) -> String {
        switch kind {
        case .addition: "Added line"
        case .removal: "Removed line"
        case .context: "Unchanged line"
        case .noNewline: "No newline marker"
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

extension DiffRenderFileHeader {
    var reference: TranscriptReference {
        .file(path: path, line: nil)
    }
}

private struct DiffRenderFileSection: Identifiable {
    let header: DiffRenderFileHeader
    var hunks: [DiffRenderHunkSection]

    var id: Int { header.fileID }
}

private struct DiffRenderHunkSection: Identifiable {
    let id: DiffRenderRow.ID
    let header: DiffRenderHunkHeader
    var rows: [DiffRenderRow]
}

private struct DiffRenderLoadID: Equatable {
    let contentID: UUID
    let lineIDs: [DiffRenderRow.ID]
}

private struct DiffLineView: View {
    let renderLine: DiffRenderLine
    let spans: [SourceSpan]
    let isWrapped: Bool
    let marker: String
    let markerColor: Color
    let backgroundColor: Color
    let accessibilityPrefix: String
    @State private var reveal = ProgressiveTextPresentation.initialReveal

    var body: some View {
        let line = renderLine.line
        let text = ProgressiveTextPresentation(
            text: line.text,
            spans: spans,
            characterLimit: reveal.limit)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Text(line.oldLine.map(String.init) ?? "")
                    .frame(width: 30, alignment: .trailing)
                Text(line.newLine.map(String.init) ?? "")
                    .frame(width: 30, alignment: .trailing)
                Text(marker)
                    .frame(width: 10)
                    .foregroundStyle(markerColor)
                SourceTextView(spans: text.spans, isWrapped: isWrapped)
                    .frame(maxWidth: isWrapped ? .infinity : nil, alignment: .leading)
            }
            .font(TenXTypography.mono(size: 10))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            .padding(.vertical, 2)
            .background(backgroundColor)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(accessibilityPrefix), \(text.accessibilityText)")
            ProgressiveRevealButton(
                reveal: $reveal,
                total: text.progressiveTotal,
                noun: "characters",
                accessibilityNoun: "diff line characters")
        }
    }
}
