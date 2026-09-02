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
            Text(message)
                .font(TenXTypography.body(size: 11))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .fixedSize(horizontal: false, vertical: true)
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
    static let jsonChildren = ProgressiveReveal(initialLimit: 12, pageSize: 50)
    static let jsonScalar = ProgressiveReveal(initialLimit: 2_000, pageSize: 4_000)
}

private struct ConsoleSurfaceView: View {
    let command: String?
    let output: String
    let exitCode: Int?

    @State private var isWrapped = true
    @State private var reveal = ToolSurfacePagination.console

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let command, !command.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("COMMAND")
                        .font(TenXTypography.mono(size: 9, weight: .medium))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    Text(command)
                        .font(TenXTypography.mono(size: 11, weight: .semibold))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
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
                    Button("Copy") { copy(output) }
                        .buttonStyle(GhostActionStyle())
                }
                .font(TenXTypography.mono(size: 10, weight: .medium))

                outputText
                ProgressiveRevealButton(
                    reveal: $reveal,
                    total: lines.count,
                    noun: "lines",
                    accessibilityNoun: "output lines")
            }
        }
    }

    @ViewBuilder
    private var outputText: some View {
        let text = visibleLines.joined(separator: "\n")
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

    private var lines: [String] {
        output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private var visibleLines: ArraySlice<String> {
        lines.prefix(reveal.visibleCount(total: lines.count))
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
                            Text(item.label)
                                .font(TenXTypography.body(size: 11, weight: .semibold))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if let state = item.state {
                            Text(state.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(TenXTypography.body(size: 9, weight: .medium))
                                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                        }
                    }
                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail)
                            .font(TenXTypography.body(size: 10))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                MediaItemView(item: item)
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
                    Text(name)
                        .font(TenXTypography.body(size: 10, weight: .semibold))
                }
                if let mimeType = item.mimeType {
                    Text(mimeType)
                        .font(TenXTypography.mono(size: 9))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
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
                    Image(image, scale: 1, label: Text(item.name ?? "Tool image"))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(progress.title)
                    .font(TenXTypography.body(size: 11, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(progress.status.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(TenXTypography.body(size: 10, weight: .medium))
                    .foregroundStyle(TenXPalette.color(progress.isFailure
                        ? TenXPalette.signalRedHex
                        : TenXPalette.cyanHex))
            }
            if let completed = progress.completed, let total = progress.total {
                Text("\(completed) of \(total)")
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
            if let document = progress.document, !document.blocks.isEmpty {
                ContentDocumentView(document: document, spacing: 8)
            } else if let detail = progress.detail, !detail.isEmpty {
                Text(detail)
                    .font(TenXTypography.body(size: 11))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !progress.history.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(progress.history.enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(TenXTypography.body(size: 10))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                Text(label.uppercased())
                    .font(TenXTypography.mono(size: 9, weight: .medium))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
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
                Text(label)
                    .font(TenXTypography.mono(size: 10, weight: .semibold))
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

private struct DataScalarRow: View {
    let label: String?
    let text: String
    @State private var reveal = ToolSurfacePagination.jsonScalar

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let label {
                    Text(label)
                        .font(TenXTypography.mono(size: 10, weight: .semibold))
                }
                Text(visibleText)
                    .font(TenXTypography.mono(size: 10))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .contextMenu {
                        Button("Copy value") { copy(text) }
                    }
                    .accessibilityAction(named: "Copy value") { copy(text) }
            }
            ProgressiveRevealButton(
                reveal: $reveal,
                total: text.count,
                noun: "characters",
                accessibilityNoun: "JSON characters")
        }
    }

    private var visibleText: String {
        String(text.prefix(reveal.visibleCount(total: text.count)))
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
