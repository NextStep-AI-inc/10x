import AppKit
import OmpKit
import os
import SwiftUI

private struct ActiveSessionFilePathKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct ToolCallIDKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var activeSessionFilePath: String? {
        get { self[ActiveSessionFilePathKey.self] }
        set { self[ActiveSessionFilePathKey.self] = newValue }
    }

    var toolCallID: String? {
        get { self[ToolCallIDKey.self] }
        set { self[ToolCallIDKey.self] = newValue }
    }
}

enum ToolPayloadSurfaceCopy {
    static let previewLabel = "Copy preview"
}

enum ToolInspectionAvailability {
    static func showsFooter(sessionFilePath: String?, toolCallID: String?) -> Bool {
        sessionFilePath != nil || toolCallID != nil
    }

    static func showsOpenSessionFile(sessionFilePath: String?) -> Bool {
        sessionFilePath != nil
    }
}

enum FilePathSurfaceLayout {
    static func directoryPath(for path: String) -> String {
        let directory = URL(filePath: path).deletingLastPathComponent().path
        if directory == ".", !path.contains("/") { return "." }
        if directory.hasPrefix("/"), !path.hasPrefix("/") {
            return String(directory.dropFirst())
        }
        return directory
    }

    static func copyLabel(for target: FileSurfaceCopyTarget) -> String {
        switch target {
        case .source: "Copy"
        case .diff: "Copy patch"
        case .console: "Copy output"
        default: ToolPayloadSurfaceCopy.previewLabel
        }
    }

    static func usesPreviewCopyLabel(forBoundedPayload bounded: Bool) -> Bool {
        bounded
    }
}

enum FileSurfaceCopyTarget: Equatable {
    case source
    case diff
    case console
    case other
}

enum EditDiffFileSelection {
    static func selectedPath(in diff: UnifiedDiff, index: Int) -> String? {
        guard diff.files.indices.contains(index) else { return nil }
        return diff.files[index].path
    }

    static func diff(for diff: UnifiedDiff, selectedPath: String) -> UnifiedDiff? {
        let files = diff.files.filter { $0.path == selectedPath }
        guard let file = files.first else { return nil }
        return UnifiedDiff(raw: diff.raw, files: [file])
    }
}

struct SearchResultFileGroup: Equatable {
    let path: String
    let matches: [ToolCollectionItem]
}

enum SearchResultGrouping {
    static func groups(from items: [ToolCollectionItem]) -> [SearchResultFileGroup] {
        var order: [String] = []
        var grouped: [String: [ToolCollectionItem]] = [:]
        for item in items {
            guard case .file(let path, _) = item.reference else { continue }
            if grouped[path] == nil { order.append(path) }
            grouped[path, default: []].append(item)
        }
        guard !order.isEmpty else { return [] }
        return order.map { SearchResultFileGroup(path: $0, matches: grouped[$0] ?? []) }
    }

    static func shouldGroup(_ items: [ToolCollectionItem]) -> Bool {
        !items.isEmpty && items.allSatisfy { item in
            if case .file(_, let line) = item.reference { return line != nil }
            return false
        }
    }
}

enum ConsoleSurfaceLayout {
    static func usesCommandOutputHeading(for body: ToolBody) -> Bool {
        switch body {
        case .console, .stack:
            true
        default:
            false
        }
    }
}

enum BrowserComputerSurfaceLayout {
    static let browserPreviewState = "browser-preview"
    static let computerPreviewState = "computer-preview"

    static func isBrowserCard(_ content: ToolCardContent) -> Bool {
        content.title == "Browser" || content.verb == "Browse"
    }

    static func isComputerCard(_ content: ToolCardContent) -> Bool {
        content.title == "Computer"
    }
}

struct FileAttachedPathSurface<Content: View>: View {
    let filePath: String
    let copyText: String
    let copyLabel: String
    let usesPreviewCopyLabel: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.fileReferenceBaseURL) private var baseURL
    @Environment(\.fileOpenService) private var fileOpenService
    @Environment(\.openIDEPreferences) private var openIDEPreferences
    @Environment(\.accessibilityAnnouncer) private var accessibilityAnnouncer
    @State private var errorStatus: String?

    private var resolvedReference: ResolvedFileReference {
        FileReferenceResolver().resolve(path: filePath, line: nil, relativeTo: baseURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pathBar
            content()
        }
        .padding(10)
        .background(TenXPalette.color(TenXPalette.hoverNeutralHex))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var pathBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    Text(FilePathSurfaceLayout.directoryPath(for: filePath))
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    if resolvedReference.exists {
                        Button("Open file", action: openFile)
                            .buttonStyle(GhostActionStyle())
                    }
                    Button(copyActionLabel) { copy(copyText) }
                        .buttonStyle(GhostActionStyle())
                }
                .font(TenXTypography.mono(size: 10, weight: .medium))
            }
            if let errorStatus {
                Text(errorStatus)
                    .font(TenXTypography.body(size: 10, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
            }
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var copyActionLabel: String {
        usesPreviewCopyLabel ? ToolPayloadSurfaceCopy.previewLabel : copyLabel
    }

    private func openFile() {
        guard resolvedReference.exists, let url = resolvedReference.url else { return }
        do {
            try fileOpenService.openWithSystemDefault(url)
        } catch {
            errorStatus = "Couldn't open \(resolvedReference.compactLabel)"
            accessibilityAnnouncer.announce(errorStatus ?? "Couldn't open file")
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

enum ToolSessionFileOpening {
    @MainActor
    static func open(path: String, fileOpenService: FileOpenService) throws {
        try fileOpenService.openWithSystemDefault(URL(filePath: path))
    }

    static func failureMessage(for path: String) -> String {
        let name = URL(filePath: path).lastPathComponent
        return "Couldn't open \(name)"
    }
}

struct ToolSurfaceView: View {
    let surface: ToolBody
    let phase: ToolPhase
    let topFilePath: String?
    let showsInspectionFooter: Bool

    init(
        body: ToolBody,
        phase: ToolPhase = .complete,
        topFilePath: String? = nil,
        showsInspectionFooter: Bool = true
    ) {
        surface = body
        self.phase = phase
        self.topFilePath = topFilePath
        self.showsInspectionFooter = showsInspectionFooter
    }

    @ViewBuilder
    var bodyView: some View {
        switch surface {
        case .document(let document):
            ContentDocumentView(document: document)
        case .source(let source, let previewLines):
            if let topFilePath {
                FileAttachedPathSurface(
                    filePath: topFilePath,
                    copyText: source.text,
                    copyLabel: FilePathSurfaceLayout.copyLabel(for: .source),
                    usesPreviewCopyLabel: false
                ) {
                    SourceSurface(
                        presentation: source,
                        previewLineLimit: previewLines,
                        style: .embeddedInFileSurface)
                }
            } else {
                SourceSurface(presentation: source, previewLineLimit: previewLines)
            }
        case .diff(let diff, let fallbackPath):
            DiffView(
                diff: diff,
                fallbackPath: fallbackPath,
                topHeaderPath: topFilePath)
        case .console(let command, let output, let exitCode):
            ConsoleSurfaceView(
                command: command,
                output: output,
                exitCode: exitCode,
                window: phase == .running ? .tail : .head)
        case .collection(let items):
            if items.first?.state == BrowserComputerSurfaceLayout.browserPreviewState {
                BrowserToolSurfaceView(items: items)
            } else if SearchResultGrouping.shouldGroup(items) {
                GroupedSearchSurfaceView(items: items)
            } else {
                CollectionSurfaceView(items: items)
            }
        case .media(let items, let caption):
            MediaSurfaceView(items: items, caption: caption)
        case .progress(let progress):
            ProgressSurfaceView(progress: progress)
        case .data(let label, let value):
            DataTreeSurfaceView(label: label, value: value)
        case .stack(let bodies):
            if let browser = BrowserToolSurfacePresentation(bodies: bodies) {
                BrowserToolSurfaceView(
                    items: [ToolCollectionItem(
                        id: "browser-\(browser.url)",
                        label: browser.title,
                        detail: browser.url,
                        reference: .web(url: browser.url, label: browser.title),
                        state: BrowserComputerSurfaceLayout.browserPreviewState)])
            } else if let computer = ComputerToolSurfacePresentation(bodies: bodies) {
                ComputerToolSurfaceView(presentation: computer)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(bodies.enumerated()), id: \.offset) { _, body in
                        ToolSurfaceView(
                            body: body,
                            phase: phase,
                            topFilePath: topFilePath,
                            showsInspectionFooter: false)
                    }
                }
            }
        case .empty(let message):
            ProgressiveTextView(text: message, accessibilityNoun: "message characters") { text in
                Text(text)
                    .font(TenXTypography.body(size: 11))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .privateActivity:
            EmptyView()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            bodyView
            if showsInspectionFooter {
                ToolInspectionFooter()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ToolInspectionFooter: View {
    @Environment(\.activeSessionFilePath) private var sessionFilePath
    @Environment(\.toolCallID) private var toolCallID
    @Environment(\.fileOpenService) private var fileOpenService
    @Environment(\.accessibilityAnnouncer) private var accessibilityAnnouncer
    @State private var errorStatus: String?
    @State private var clearErrorTask: Task<Void, Never>?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tannerpham.tenx",
        category: "ToolInspection")

    var body: some View {
        if ToolInspectionAvailability.showsFooter(
            sessionFilePath: sessionFilePath,
            toolCallID: toolCallID)
        {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let sessionFilePath {
                        Button("Open session file") {
                            openSessionFile(at: sessionFilePath)
                        }
                        .buttonStyle(GhostActionStyle())
                    }
                    if let toolCallID {
                        Button("Copy call ID") { copy(toolCallID) }
                            .buttonStyle(GhostActionStyle())
                    }
                    Spacer(minLength: 8)
                }
                if let errorStatus {
                    Text(errorStatus)
                        .font(TenXTypography.body(size: 10, weight: .medium))
                        .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                        .accessibilityLabel(errorStatus)
                }
            }
            .font(TenXTypography.mono(size: 10, weight: .medium))
            .onDisappear { clearErrorTask?.cancel() }
        }
    }

    private func openSessionFile(at path: String) {
        beginInteraction()
        do {
            try ToolSessionFileOpening.open(path: path, fileOpenService: fileOpenService)
        } catch {
            Self.logger.error(
                "[ToolInspection:openSessionFile] Could not open session file — path=\(path, privacy: .private(mask: .hash)), error=\(String(describing: error), privacy: .private)")
            showError(ToolSessionFileOpening.failureMessage(for: path))
        }
    }

    private func beginInteraction() {
        clearErrorTask?.cancel()
        errorStatus = nil
    }

    private func showError(_ message: String) {
        clearErrorTask?.cancel()
        errorStatus = message
        accessibilityAnnouncer.announce(message)
        clearErrorTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            errorStatus = nil
        }
    }
}

enum ConsoleRenderWindow: Equatable, Sendable {
    case head
    case tail
}

enum ToolSurfacePagination {
    static let console = ProgressiveReveal(initialLimit: 10, pageSize: 100)
    static let collection = ProgressiveReveal(initialLimit: 8, pageSize: 50)
    static let progressHistory = ProgressiveReveal(initialLimit: 8, pageSize: 50)
    static let jsonChildren = ProgressiveReveal(initialLimit: 12, pageSize: 50)
    static let jsonScalar = ProgressiveReveal(initialLimit: 2_000, pageSize: 4_000)
}

typealias ToolMediaLoaderFactory = @MainActor (ToolMediaItem) -> ToolMediaLoader

private struct ToolMediaLoaderFactoryKey: EnvironmentKey {
    static let defaultValue: ToolMediaLoaderFactory = { _ in ToolMediaLoader() }
}

extension EnvironmentValues {
    var toolMediaLoaderFactory: ToolMediaLoaderFactory {
        get { self[ToolMediaLoaderFactoryKey.self] }
        set { self[ToolMediaLoaderFactoryKey.self] = newValue }
    }
}

struct ConsoleRenderPresentation: Equatable, Sendable {
    let copyText: String
    let visibleText: String
    let accessibilityText: String
    let lineProgressiveTotal: Int
    let characterProgressiveTotal: Int
    let inspectedCharacterCount: Int
    let inspectedLineCount: Int
    let materializedCharacterCount: Int

    init(
        output: String,
        lineLimit: Int,
        characterLimit: Int,
        window: ConsoleRenderWindow = .head
    ) {
        copyText = output
        guard !output.isEmpty else {
            visibleText = ""
            accessibilityText = ""
            lineProgressiveTotal = 0
            characterProgressiveTotal = 0
            inspectedCharacterCount = 0
            inspectedLineCount = 0
            materializedCharacterCount = 0
            return
        }

        let lineLimit = max(0, lineLimit)
        let characterLimit = max(0, characterLimit)
        let characterProbeLimit = characterLimit
            + ProgressiveTextPresentation.initialReveal.pageSize
            + 1
        let lineProbeLimit = lineLimit + ToolSurfacePagination.console.pageSize + 1
        let characterProbe = switch window {
        case .head: output.prefix(characterProbeLimit)
        case .tail: output.suffix(characterProbeLimit)
        }
        var observedLineCount = 1
        let boundedLineText: String

        switch window {
        case .head:
            var visibleLineEnd: String.Index?
            if lineLimit == 0 {
                visibleLineEnd = characterProbe.startIndex
            } else {
                for index in characterProbe.indices where characterProbe[index] == "\n" {
                    if observedLineCount == lineLimit {
                        visibleLineEnd = index
                    }
                    observedLineCount += 1
                    if observedLineCount >= lineProbeLimit { break }
                }
            }
            boundedLineText = String(characterProbe[..<(visibleLineEnd ?? characterProbe.endIndex)])
        case .tail:
            var visibleLineStart = characterProbe.startIndex
            if lineLimit == 0 {
                visibleLineStart = characterProbe.endIndex
            } else {
                for index in characterProbe.indices.reversed()
                where characterProbe[index] == "\n" {
                    if observedLineCount == lineLimit {
                        visibleLineStart = characterProbe.index(after: index)
                    }
                    observedLineCount += 1
                    if observedLineCount >= lineProbeLimit { break }
                }
            }
            boundedLineText = String(characterProbe[visibleLineStart...])
        }

        let maximumNextLinePage = lineLimit + ToolSurfacePagination.console.pageSize
        lineProgressiveTotal = min(observedLineCount, maximumNextLinePage)
        inspectedCharacterCount = characterProbe.count
        inspectedLineCount = observedLineCount
        materializedCharacterCount = boundedLineText.count
        switch window {
        case .head:
            let textPresentation = ProgressiveTextPresentation(
                text: boundedLineText,
                characterLimit: characterLimit)
            visibleText = textPresentation.visibleText
            accessibilityText = textPresentation.accessibilityText
            characterProgressiveTotal = textPresentation.progressiveTotal
        case .tail:
            let text = String(boundedLineText.suffix(characterLimit))
            visibleText = text
            accessibilityText = text
            characterProgressiveTotal = min(
                boundedLineText.count,
                characterLimit + ProgressiveTextPresentation.initialReveal.pageSize)
        }
    }
}

struct BrowserToolSurfacePresentation: Equatable {
    let title: String
    let url: String

    init?(bodies: [ToolBody]) {
        for body in bodies {
            guard case .collection(let items) = body,
                  let item = items.first,
                  item.state == BrowserComputerSurfaceLayout.browserPreviewState
            else { continue }
            title = item.label
            url = item.detail ?? item.label
            return
        }
        return nil
    }

    init(items: [ToolCollectionItem]) {
        title = items.first?.label ?? "Page"
        url = items.first?.detail ?? title
    }
}

struct ComputerToolSurfacePresentation: Equatable {
    let application: String
    let action: String?
    let media: [ToolMediaItem]

    init?(bodies: [ToolBody]) {
        var media: [ToolMediaItem] = []
        var info: ToolCollectionItem?
        for body in bodies {
            switch body {
            case .media(let items, _):
                media = items
            case .collection(let items):
                info = items.first(where: { $0.state == BrowserComputerSurfaceLayout.computerPreviewState })
            default:
                break
            }
        }
        guard let info else { return nil }
        application = info.label
        action = info.detail
        self.media = media
    }
}

private struct BrowserToolSurfaceView: View {
    let items: [ToolCollectionItem]

    var body: some View {
        let presentation = BrowserToolSurfacePresentation(items: items)
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(TenXPalette.color(TenXPalette.separatorHex), lineWidth: 1)
                .background(TenXPalette.color(TenXPalette.hoverNeutralHex))
                .frame(width: 142, height: 90)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(TenXPalette.color(TenXPalette.separatorHex))
                            .frame(height: 7)
                        Text(presentation.title)
                            .font(TenXTypography.body(size: 11, weight: .medium))
                            .lineLimit(1)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(TenXPalette.color(TenXPalette.separatorHex))
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(TenXPalette.color(TenXPalette.separatorHex))
                            .frame(width: 80, height: 5)
                    }
                    .padding(9)
                }
            VStack(alignment: .leading, spacing: 7) {
                Text(presentation.title)
                    .font(TenXTypography.body(size: 12, weight: .medium))
                Text(presentation.url)
                    .font(TenXTypography.body(size: 11))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                if let url = URL(string: presentation.url) {
                    Link("Open page", destination: url)
                        .buttonStyle(GhostActionStyle())
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ComputerToolSurfaceView: View {
    let presentation: ComputerToolSurfacePresentation
    @Environment(\.toolMediaLoaderFactory) private var makeLoader

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(TenXPalette.color(TenXPalette.separatorHex), lineWidth: 1)
                .background(TenXPalette.color(TenXPalette.hoverNeutralHex))
                .frame(width: 142, height: 90)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("● ● ●")
                            .font(TenXTypography.body(size: 9))
                            .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                        Text(presentation.application)
                            .font(TenXTypography.body(size: 11, weight: .medium))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(TenXPalette.color(TenXPalette.separatorHex))
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(TenXPalette.color(TenXPalette.separatorHex))
                            .frame(width: 80, height: 5)
                    }
                    .padding(9)
                }
            VStack(alignment: .leading, spacing: 7) {
                Text(presentation.application)
                    .font(TenXTypography.body(size: 12, weight: .medium))
                if let action = presentation.action {
                    Text(action)
                        .font(TenXTypography.body(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
                if let item = presentation.media.first {
                    Button("View capture") {
                        if let url = item.url.flatMap(URL.init(string:)) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(GhostActionStyle())
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct GroupedSearchSurfaceView: View {
    let items: [ToolCollectionItem]
    @State private var reveal = ToolSurfacePagination.collection

    var body: some View {
        let groups = SearchResultGrouping.groups(from: items)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(visibleGroups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        TranscriptReferenceView(reference: .file(path: group.path, line: nil))
                        Spacer(minLength: 8)
                        Text("\(group.matches.count) \(group.matches.count == 1 ? "match" : "matches")")
                            .font(TenXTypography.body(size: 11))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    }
                    ForEach(group.matches) { match in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            if case .file(_, let line) = match.reference, let line {
                                Text(String(line))
                                    .font(TenXTypography.mono(size: 10))
                                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                                    .frame(width: 28, alignment: .trailing)
                            }
                            if let detail = match.detail {
                                Text(detail)
                                    .font(TenXTypography.mono(size: 10))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(TenXPalette.color(TenXPalette.hoverNeutralHex))
                    }
                }
            }
            ProgressiveRevealButton(
                reveal: $reveal,
                total: groups.count,
                noun: "files",
                accessibilityNoun: "result files")
        }
    }

    private var visibleGroups: [SearchResultFileGroup] {
        let groups = SearchResultGrouping.groups(from: items)
        return Array(groups.prefix(reveal.visibleCount(total: groups.count)))
    }
}

private struct ConsoleSurfaceView: View {
    let command: String?
    let output: String
    let exitCode: Int?
    let window: ConsoleRenderWindow

    @State private var isWrapped = true
    @State private var lineReveal = ToolSurfacePagination.console
    @State private var characterReveal = ProgressiveTextPresentation.initialReveal

    var body: some View {
        let presentation = ConsoleRenderPresentation(
            output: output,
            lineLimit: lineReveal.limit,
            characterLimit: characterReveal.limit,
            window: window)
        VStack(alignment: .leading, spacing: 8) {
            if let command, !command.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("COMMAND")
                        .font(TenXTypography.mono(size: 9, weight: .medium))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    ProgressiveTextView(
                        text: command,
                        accessibilityNoun: "command characters"
                    ) { text in
                        Text(text)
                            .font(TenXTypography.mono(size: 11, weight: .semibold))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TenXPalette.color(TenXPalette.hoverNeutralHex))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if !output.isEmpty {
                HStack(spacing: 8) {
                    Text("Command output")
                        .font(TenXTypography.body(size: 11, weight: .medium))
                    Spacer(minLength: 8)
                    if let exitCode {
                        Text("Exit \(exitCode)")
                            .foregroundStyle(exitCode == 0
                                ? TenXPalette.color(TenXPalette.cyanHex)
                                : TenXPalette.color(TenXPalette.signalRedHex))
                    }
                    Button(isWrapped ? "Scroll" : "Wrap") {
                        isWrapped.toggle()
                    }
                    .buttonStyle(GhostActionStyle())
                    Button(FilePathSurfaceLayout.copyLabel(for: .console)) { copy(presentation.copyText) }
                        .buttonStyle(GhostActionStyle())
                }
                .font(TenXTypography.mono(size: 10, weight: .medium))

                outputText(presentation.visibleText)
                    .accessibilityLabel(presentation.accessibilityText)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TenXPalette.color(TenXPalette.hoverNeutralHex))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(consoleFooterSummary(presentation: presentation))
                        .font(TenXTypography.body(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    Spacer(minLength: 8)
                    ProgressiveRevealButton(
                        reveal: $lineReveal,
                        total: presentation.lineProgressiveTotal,
                        noun: "lines",
                        accessibilityNoun: "output lines")
                }
                ProgressiveRevealButton(
                    reveal: $characterReveal,
                    total: presentation.characterProgressiveTotal,
                    noun: "characters",
                    accessibilityNoun: "output characters")
            }
        }
    }

    @ViewBuilder
    private func outputText(_ text: String) -> some View {
        if isWrapped {
            consoleText(text)
        } else {
            ScrollView(.horizontal) {
                consoleText(text)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func consoleText(_ value: String) -> some View {
        Text(value)
            .font(TenXTypography.mono(size: 10))
            .textSelection(.enabled)
            .fixedSize(horizontal: !isWrapped, vertical: true)
            .frame(maxWidth: isWrapped ? .infinity : nil, alignment: .leading)
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func consoleFooterSummary(presentation: ConsoleRenderPresentation) -> String {
        let total = presentation.lineProgressiveTotal
        let visible = min(total, lineReveal.limit)
        guard total > visible else {
            return "Showing \(total) \(total == 1 ? "line" : "lines")"
        }
        return "Showing \(visible) of \(total) \(total == 1 ? "line" : "lines")"
    }
}

private struct CollectionSurfaceView: View {
    let items: [ToolCollectionItem]
    @State private var reveal = ToolSurfacePagination.collection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(visibleItems) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let reference = item.reference {
                            TranscriptReferenceView(reference: reference)
                        } else {
                            ProgressiveTextView(
                                text: item.label,
                                accessibilityNoun: "item label characters"
                            ) { text in
                                Text(text)
                                    .font(TenXTypography.body(size: 11, weight: .semibold))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 8)
                        if let state = item.state {
                            ProgressiveTextView(
                                text: state,
                                accessibilityNoun: "item state characters"
                            ) { text in
                                Text(text.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(TenXTypography.body(size: 9, weight: .medium))
                                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                            }
                        }
                    }
                    if let detail = item.detail, !detail.isEmpty {
                        ProgressiveTextView(
                            text: detail,
                            accessibilityNoun: "item detail characters"
                        ) { text in
                            Text(text)
                                .font(TenXTypography.body(size: 10))
                                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            ProgressiveRevealButton(
                reveal: $reveal,
                total: items.count,
                noun: "items",
                accessibilityNoun: "collection items")
        }
    }

    private var visibleItems: [ToolCollectionItem] {
        Array(items.prefix(reveal.visibleCount(total: items.count)))
    }
}

private struct MediaSurfaceView: View {
    let items: [ToolMediaItem]
    let caption: ContentDocument?
    @Environment(\.toolMediaLoaderFactory) private var makeLoader

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                MediaItemView(item: item, loader: makeLoader(item))
            }
            if let caption, !caption.blocks.isEmpty {
                ContentDocumentView(document: caption)
            }
        }
    }
}

struct MediaItemView: View {
    let item: ToolMediaItem
    @State private var errorMessage: String?
    @StateObject private var loader: ToolMediaLoader

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tannerpham.tenx",
        category: "ToolMedia")

    init(item: ToolMediaItem, loader: ToolMediaLoader? = nil) {
        self.item = item
        _loader = StateObject(wrappedValue: loader ?? ToolMediaLoader())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            mediaPreview

            HStack(spacing: 8) {
                if let name = item.name {
                    ProgressiveTextView(
                        text: name,
                        accessibilityNoun: "media name characters"
                    ) { text in
                        Text(text)
                            .font(TenXTypography.body(size: 10, weight: .semibold))
                    }
                }
                if let mimeType = item.mimeType {
                    ProgressiveTextView(
                        text: mimeType,
                        accessibilityNoun: "media type characters"
                    ) { text in
                        Text(text)
                            .font(TenXTypography.mono(size: 9))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    }
                }
                Spacer(minLength: 8)
                if openURL != nil {
                    Button("Open", action: open)
                        .buttonStyle(GhostActionStyle())
                }
                if item.data != nil, loader.decodedData != nil {
                    Button("Save", action: save)
                        .buttonStyle(GhostActionStyle())
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(TenXTypography.body(size: 10, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
            }
        }
        .task(id: item.contentID) {
            guard remoteURL == nil else {
                loader.cancel()
                return
            }
            await loader.load(item)
        }
    }

    @ViewBuilder
    private var mediaPreview: some View {
        if let remoteURL {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .empty:
                    ProgressView().controlSize(.small)
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    unavailablePreview
                @unknown default:
                    unavailablePreview
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200, alignment: .leading)
        } else {
            switch loader.state {
            case .loaded(let media):
                if let image = media.image {
                    Image(
                        image,
                        scale: 1,
                        label: Text(boundedAccessibilityText(item.name ?? "Tool image")))
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200, alignment: .leading)
                } else {
                    unavailablePreview
                    DataTreeSurfaceView(label: "Media data", value: fallbackValue)
                }
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200, alignment: .leading)
            case .idle, .unavailable, .failed:
                unavailablePreview
                DataTreeSurfaceView(label: "Media data", value: fallbackValue)
            }
        }
    }

    private var unavailablePreview: some View {
        Label("Preview unavailable", systemImage: "photo")
            .font(TenXTypography.body(size: 11, weight: .medium))
            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            .frame(minHeight: 72)
    }

    private var remoteURL: URL? {
        guard let url = openURL, !url.isFileURL else { return nil }
        return url.scheme == "http" || url.scheme == "https" ? url : nil
    }

    private var openURL: URL? {
        guard let value = item.url, !value.isEmpty else { return nil }
        if value.hasPrefix("/") { return URL(filePath: value) }
        return URL(string: value)
    }

    private var fallbackValue: JSONValue {
        var values: [String: JSONValue] = ["kind": .string(String(describing: item.kind))]
        if let name = item.name { values["name"] = .string(name) }
        if let mimeType = item.mimeType { values["mimeType"] = .string(mimeType) }
        if let data = item.data { values["data"] = .string(data) }
        if let url = item.url { values["url"] = .string(url) }
        return .object(values)
    }

    private func boundedAccessibilityText(_ text: String) -> String {
        ProgressiveTextPresentation(
            text: text,
            characterLimit: ProgressiveTextPresentation.initialReveal.limit).accessibilityText
    }

    private func open() {
        guard let openURL else { return }
        NSWorkspace.shared.open(openURL)
    }

    private func save() {
        guard let decodedData = loader.decodedData else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.name ?? "tool-media"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try decodedData.write(to: url, options: .atomic)
            errorMessage = nil
        } catch {
            Self.logger.error(
                "[ToolMedia:save] Could not save media — name=\(item.name ?? "unnamed", privacy: .private(mask: .hash)), error=\(String(describing: error), privacy: .private)")
            errorMessage = "Couldn’t save media"
        }
    }
}

private struct ProgressSurfaceView: View {
    let progress: ToolProgress
    @State private var historyReveal = ToolSurfacePagination.progressHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ProgressiveTextView(
                    text: progress.title,
                    accessibilityNoun: "progress title characters"
                ) { text in
                    Text(text)
                        .font(TenXTypography.body(size: 11, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ProgressiveTextView(
                    text: progress.status,
                    accessibilityNoun: "progress status characters"
                ) { text in
                    Text(text.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(TenXTypography.body(size: 10, weight: .medium))
                        .foregroundStyle(TenXPalette.color(progress.isFailure
                            ? TenXPalette.signalRedHex
                            : TenXPalette.cyanHex))
                }
            }
            if let completed = progress.completed, let total = progress.total {
                Text("\(completed) of \(total)")
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
            if let document = progress.document, !document.blocks.isEmpty {
                ContentDocumentView(document: document, spacing: 8)
            } else if let detail = progress.detail, !detail.isEmpty {
                ProgressiveTextView(
                    text: detail,
                    accessibilityNoun: "progress detail characters"
                ) { text in
                    Text(text)
                        .font(TenXTypography.body(size: 11))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !progress.history.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(
                        Array(progress.history.prefix(
                            historyReveal.visibleCount(total: progress.history.count)).enumerated()),
                        id: \.offset
                    ) { _, entry in
                        ProgressiveTextView(
                            text: entry,
                            accessibilityNoun: "progress history characters"
                        ) { text in
                            Text(text)
                                .font(TenXTypography.body(size: 10))
                                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ProgressiveRevealButton(
                        reveal: $historyReveal,
                        total: progress.history.count,
                        noun: "entries",
                        accessibilityNoun: "progress history entries")
                }
            }
        }
    }
}

private struct DataTreeSurfaceView: View {
    let label: String
    let value: JSONValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressiveTextView(
                    text: label,
                    accessibilityNoun: "data label characters"
                ) { text in
                    Text(text.uppercased())
                        .font(TenXTypography.mono(size: 9, weight: .medium))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
                Spacer(minLength: 8)
                Button(ToolPayloadSurfaceCopy.previewLabel) { copy(prettyJSON(value)) }
                    .buttonStyle(GhostActionStyle())
            }
            JSONValueNode(label: nil, value: value, depth: 0)
        }
        .padding(10)
        .background(TenXPalette.color(TenXPalette.hoverNeutralHex))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

enum DataTreeSurfaceLayout {
    static let maximumDepth = 6
}

private struct JSONValueNode: View {
    let label: String?
    let value: JSONValue
    let depth: Int

    @State private var isExpanded: Bool
    @State private var childrenReveal = ToolSurfacePagination.jsonChildren

    init(label: String?, value: JSONValue, depth: Int) {
        self.label = label
        self.value = value
        self.depth = depth
        _isExpanded = State(initialValue: depth < 2)
    }

    @ViewBuilder
    var body: some View {
        if depth >= DataTreeSurfaceLayout.maximumDepth {
            scalarRow(summary)
        } else {
            switch value {
            case .object(let object):
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 5) {
                        let keys = object.keys.sorted()
                        ForEach(
                            keys.prefix(visibleChildCount(total: keys.count)),
                            id: \.self
                        ) { key in
                            if let child = object[key] {
                                JSONValueNode(label: key, value: child, depth: depth + 1)
                            }
                        }
                        childDisclosure(total: object.count, noun: "fields")
                    }
                    .padding(.leading, 12)
                } label: {
                    nodeLabel("\(object.count) fields")
                }
            case .array(let values):
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(0..<visibleChildCount(total: values.count), id: \.self) { index in
                            JSONValueNode(
                                label: "[\(index)]",
                                value: values[index],
                                depth: depth + 1)
                        }
                        childDisclosure(total: values.count, noun: "items")
                    }
                    .padding(.leading, 12)
                } label: {
                    nodeLabel("\(values.count) items")
                }
            default:
                scalarRow(scalarText)
            }
        }
    }

    private func visibleChildCount(total: Int) -> Int {
        childrenReveal.visibleCount(total: total)
    }

    @ViewBuilder
    private func childDisclosure(total: Int, noun: String) -> some View {
        ProgressiveRevealButton(
            reveal: $childrenReveal,
            total: total,
            noun: noun,
            accessibilityNoun: "JSON \(noun)")
    }

    private func nodeLabel(_ detail: String) -> some View {
        HStack(spacing: 6) {
            if let label {
                ProgressiveTextView(
                    text: label,
                    accessibilityNoun: "JSON label characters"
                ) { text in
                    Text(text)
                        .font(TenXTypography.mono(size: 10, weight: .semibold))
                }
            }
            Text(detail)
                .font(TenXTypography.mono(size: 9))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
    }

    private func scalarRow(_ text: String) -> some View {
        DataScalarRow(label: label, text: text)
    }

    private var scalarText: String {
        switch value {
        case .null: "null"
        case .bool(let bool): bool ? "true" : "false"
        case .int(let int): String(int)
        case .double(let double): String(double)
        case .string(let string): string
        case .array, .object: summary
        }
    }

    private var summary: String {
        switch value {
        case .array(let values): "\(values.count) items"
        case .object(let object): "\(object.count) fields"
        default: scalarText
        }
    }
}

struct DataScalarRenderPresentation: Equatable, Sendable {
    let visibleText: String
    let accessibilityText: String
    let progressiveTotal: Int

    init(text: String, characterLimit: Int) {
        let textPresentation = ProgressiveTextPresentation(
            text: text,
            characterLimit: characterLimit)
        visibleText = textPresentation.visibleText
        accessibilityText = textPresentation.accessibilityText
        progressiveTotal = textPresentation.progressiveTotal
    }
}

private struct DataScalarRow: View {
    let label: String?
    let text: String
    @State private var reveal = ToolSurfacePagination.jsonScalar

    var body: some View {
        let presentation = DataScalarRenderPresentation(
            text: text,
            characterLimit: reveal.limit)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let label {
                    ProgressiveTextView(
                        text: label,
                        accessibilityNoun: "JSON label characters"
                    ) { text in
                        Text(text)
                            .font(TenXTypography.mono(size: 10, weight: .semibold))
                    }
                }
                Text(presentation.visibleText)
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .contextMenu {
                        Button(ToolPayloadSurfaceCopy.previewLabel) { copy(text) }
                    }
                    .accessibilityAction(named: ToolPayloadSurfaceCopy.previewLabel) { copy(text) }
                    .accessibilityLabel(presentation.accessibilityText)
            }
            ProgressiveRevealButton(
                reveal: $reveal,
                total: presentation.progressiveTotal,
                noun: "characters",
                accessibilityNoun: "JSON characters")
        }
    }
}

private func prettyJSON(_ value: JSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value) else { return "Unavailable" }
    return String(decoding: data, as: UTF8.self)
}

private func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
}
