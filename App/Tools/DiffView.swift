import AppKit
import SwiftUI

struct DiffView: View {
    let diff: UnifiedDiff
    let fallbackPath: String?
    @State private var revealedRuns: Set<String> = []
    @State private var isWrapped = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("+\(additions)")
                    .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                Text("−\(removals)")
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                Spacer()
                Button(isWrapped ? "Scroll" : "Wrap") {
                    isWrapped.toggle()
                }
                .buttonStyle(GhostActionStyle())
                .accessibilityLabel(isWrapped
                    ? "Use horizontal scrolling for diff"
                    : "Wrap diff lines")
                Button("Copy patch") { copy(diff.raw) }
                    .buttonStyle(GhostActionStyle())
            }
            .font(TenXTypography.mono(size: 10, weight: .semibold))

            ForEach(Array(diff.files.enumerated()), id: \.offset) { fileIndex, file in
                if fileIndex > 0 { Divider() }
                fileView(file, fileIndex: fileIndex)
            }
        }
    }

    private func fileView(_ file: UnifiedDiffFile, fileIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(file.path)
                    .font(TenXTypography.mono(size: 10, weight: .semibold))
                    .lineLimit(1)
                Text("+\(file.additions) −\(file.removals)")
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                Spacer()
                if let path = resolvedPath(for: file), FileManager.default.fileExists(atPath: path) {
                    Button("Open file") { NSWorkspace.shared.open(URL(filePath: path)) }
                        .buttonStyle(GhostActionStyle())
                }
            }
            ForEach(Array(file.hunks.enumerated()), id: \.offset) { hunkIndex, hunk in
                hunkView(
                    hunk,
                    idPrefix: "\(fileIndex)-\(hunkIndex)",
                    language: SourceTokenizer.languageIdentifier(forPath: file.path))
            }
        }
    }

    private func hunkView(
        _ hunk: UnifiedDiffHunk,
        idPrefix: String,
        language: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hunk.header)
                .font(TenXTypography.mono(size: 10, weight: .medium))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            if isWrapped {
                hunkRows(hunk, idPrefix: idPrefix, language: language)
            } else {
                ScrollView(.horizontal) {
                    hunkRows(hunk, idPrefix: idPrefix, language: language)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    private func hunkRows(
        _ hunk: UnifiedDiffHunk,
        idPrefix: String,
        language: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(hunk.displayRows()) { displayRow in
                switch displayRow {
                case .line(let index):
                    lineView(hunk.lines[index], language: language)
                case .collapsed(let id, let count, let indices):
                    let runID = "\(idPrefix)-\(id)"
                    if revealedRuns.contains(runID) {
                        ForEach(indices, id: \.self) { index in
                            lineView(hunk.lines[index], language: language)
                        }
                    } else {
                        Button("Show \(count) unchanged lines") {
                            revealedRuns.insert(runID)
                        }
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
                        .buttonStyle(.plain)
                        .frame(minHeight: 24)
                    }
                }
            }
        }
        .frame(maxWidth: isWrapped ? .infinity : nil, alignment: .leading)
    }

    private func lineView(_ line: UnifiedDiffLine, language: String?) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(line.oldLine.map(String.init) ?? "")
                .frame(width: 30, alignment: .trailing)
            Text(line.newLine.map(String.init) ?? "")
                .frame(width: 30, alignment: .trailing)
            Text(marker(for: line.kind))
                .frame(width: 10)
                .foregroundStyle(color(for: line.kind))
            SourceTextView(
                spans: SourceTokenizer.spans(line.text, language: language),
                isWrapped: isWrapped)
                .frame(maxWidth: isWrapped ? .infinity : nil, alignment: .leading)
        }
        .font(TenXTypography.mono(size: 10))
        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        .padding(.vertical, 2)
        .background(backgroundColor(for: line.kind))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label(for: line.kind)), \(line.text)")
    }

    private var additions: Int { diff.files.reduce(0) { $0 + $1.additions } }
    private var removals: Int { diff.files.reduce(0) { $0 + $1.removals } }

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
        case .addition:
            TenXPalette.color(TenXPalette.cyanHex).opacity(0.08)
        case .removal:
            TenXPalette.color(TenXPalette.signalRedHex).opacity(0.07)
        case .context, .noNewline:
            .clear
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

    private func resolvedPath(for file: UnifiedDiffFile) -> String? {
        if file.path.hasPrefix("/") { return file.path }
        guard diff.files.count == 1 else { return nil }
        return fallbackPath
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
