import AppKit
import OmpKit
import os
import SwiftUI

struct ToolSurfaceView: View {
    let surface: ToolBody

    init(body: ToolBody) {
        surface = body
    }

    @ViewBuilder
    var bodyView: some View {
        switch surface {
        case .document(let document):
            ContentDocumentView(document: document)
        case .source(let source, let previewLines):
            SourceSurface(presentation: source, previewLineLimit: previewLines)
        case .diff(let diff, let fallbackPath):
            DiffView(diff: diff, fallbackPath: fallbackPath)
        case .console(let command, let output, let exitCode):
            ConsoleSurfaceView(command: command, output: output, exitCode: exitCode)
        case .collection(let items):
            CollectionSurfaceView(items: items)
        case .media(let items, let caption):
            MediaSurfaceView(items: items, caption: caption)
        case .progress(let progress):
            ProgressSurfaceView(progress: progress)
        case .data(let label, let value):
            DataTreeSurfaceView(label: label, value: value)
        case .stack(let bodies):
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(bodies.enumerated()), id: \.offset) { _, body in
                    ToolSurfaceView(body: body)
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
        bodyView
            .frame(maxWidth: .infinity, alignment: .leading)
    }
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

    init(output: String, lineLimit: Int, characterLimit: Int) {
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
        let characterProbe = output.prefix(characterProbeLimit)
        var observedLineCount = 1
        var visibleLineEnd: String.Index?

        if lineLimit == 0 {
            visibleLineEnd = characterProbe.startIndex
        } else {
            for index in characterProbe.indices where characterProbe[index] == "\n" {
                if observedLineCount == lineLimit {
                    visibleLineEnd = index
                }
                observedLineCount += 1
                if observedLineCount >= lineProbeLimit {
                    break
                }
            }
        }

        let boundedLineText = String(characterProbe[..<(visibleLineEnd ?? characterProbe.endIndex)])
        let textPresentation = ProgressiveTextPresentation(
            text: boundedLineText,
            characterLimit: characterLimit)
        let maximumNextLinePage = lineLimit + ToolSurfacePagination.console.pageSize

        visibleText = textPresentation.visibleText
        accessibilityText = textPresentation.accessibilityText
        lineProgressiveTotal = min(observedLineCount, maximumNextLinePage)
        characterProgressiveTotal = textPresentation.progressiveTotal
        inspectedCharacterCount = characterProbe.count
        inspectedLineCount = observedLineCount
        materializedCharacterCount = boundedLineText.count
    }
}

private struct ConsoleSurfaceView: View {
    let command: String?
    let output: String
    let exitCode: Int?

    @State private var isWrapped = true
    @State private var lineReveal = ToolSurfacePagination.console
    @State private var characterReveal = ProgressiveTextPresentation.initialReveal

    var body: some View {
        let presentation = ConsoleRenderPresentation(
            output: output,
            lineLimit: lineReveal.limit,
            characterLimit: characterReveal.limit)
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
                    if let exitCode {
                        Text("Exit \(exitCode)")
                            .foregroundStyle(exitCode == 0
                                ? TenXPalette.color(TenXPalette.cyanHex)
                                : TenXPalette.color(TenXPalette.signalRedHex))
                    } else {
                        Text("OUTPUT")
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    }
                    Spacer(minLength: 8)
                    Button(isWrapped ? "Scroll" : "Wrap") {
                        isWrapped.toggle()
                    }
                    .buttonStyle(GhostActionStyle())
                    Button("Copy") { copy(presentation.copyText) }
                        .buttonStyle(GhostActionStyle())
                }
                .font(TenXTypography.mono(size: 10, weight: .medium))

                outputText(presentation.visibleText)
                    .accessibilityLabel(presentation.accessibilityText)
                ProgressiveRevealButton(
                    reveal: $characterReveal,
                    total: presentation.characterProgressiveTotal,
                    noun: "characters",
                    accessibilityNoun: "output characters")
                ProgressiveRevealButton(
                    reveal: $lineReveal,
                    total: presentation.lineProgressiveTotal,
                    noun: "lines",
                    accessibilityNoun: "output lines")
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
                Button("Copy raw") { copy(prettyJSON(value)) }
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
                        Button("Copy value") { copy(text) }
                    }
                    .accessibilityAction(named: "Copy value") { copy(text) }
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
