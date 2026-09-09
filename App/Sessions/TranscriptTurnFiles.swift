import Foundation

struct TranscriptTurnFile: Equatable, Identifiable, Sendable {
    let path: String
    let toolID: String

    var id: String { path }
}

enum TranscriptTurnFiles {
    static func files(in section: TranscriptTurnSection) -> [TranscriptTurnFile] {
        var orderedPaths: [String] = []
        var latestToolIDByPath: [String: String] = [:]

        for item in section.items {
            guard case .tool(let tool) = item,
                  tool.phase == .complete,
                  isSupportedTool(tool)
            else { continue }

            for path in paths(from: tool) {
                guard let normalizedPath = normalize(path) else { continue }
                if latestToolIDByPath[normalizedPath] == nil {
                    orderedPaths.append(normalizedPath)
                }
                latestToolIDByPath[normalizedPath] = tool.id
            }
        }

        return orderedPaths.compactMap { path in
            latestToolIDByPath[path].map { toolID in
                TranscriptTurnFile(path: path, toolID: toolID)
            }
        }
    }

    private static func isSupportedTool(_ tool: ToolPresentation) -> Bool {
        switch ToolCardRegistry.kind(for: tool.name) {
        case .edit, .astEdit, .write:
            true
        default:
            false
        }
    }

    private static func paths(from tool: ToolPresentation) -> [String] {
        let diffPaths = diffPaths(in: tool.content.body)
        if !diffPaths.isEmpty { return diffPaths }

        let collectionPaths = collectionPaths(in: tool.content.body)
        if !collectionPaths.isEmpty { return collectionPaths }

        guard case .file(let path, _) = tool.content.reference else { return [] }
        return [path]
    }

    private static func diffPaths(in body: ToolBody) -> [String] {
        switch body {
        case .diff(let diff, _):
            diff.files.map(\.path)
        case .stack(let bodies):
            bodies.flatMap(diffPaths)
        default:
            []
        }
    }

    private static func collectionPaths(in body: ToolBody) -> [String] {
        switch body {
        case .collection(let items):
            items.compactMap { item in
                guard case .file(let path, _) = item.reference else { return nil }
                return path
            }
        case .stack(let bodies):
            bodies.flatMap(collectionPaths)
        default:
            []
        }
    }

    private static func normalize(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let isAbsolute = trimmed.hasPrefix("/")
        var components: [String] = []
        for component in trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            switch component {
            case ".":
                continue
            case "..":
                if let last = components.last, last != ".." {
                    components.removeLast()
                } else if !isAbsolute {
                    components.append(component)
                }
            default:
                components.append(component)
            }
        }

        let normalized = components.joined(separator: "/")
        if isAbsolute { return "/" + normalized }
        return normalized.isEmpty ? nil : normalized
    }
}
