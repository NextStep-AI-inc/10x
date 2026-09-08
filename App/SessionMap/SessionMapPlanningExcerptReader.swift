import Foundation
import CryptoKit

struct SessionMapPlanningExcerpt: Equatable, Sendable {
    let file: String
    let ref: String
    let text: String
    let hash: String
}

struct SessionMapPlanningExcerptResult: Equatable, Sendable {
    let excerpts: [SessionMapPlanningExcerpt]
    let diagnostics: [SessionMapDiagnostic]
}

enum SessionMapPlanningExcerptReader {
    static let maxFileBytes = 2 * 1024
    static let maxTotalBytes = 4 * 1024

    static func read(
        items: [TranscriptItem],
        projectURL: URL
    ) -> SessionMapPlanningExcerptResult {
        let observations = observedMarkdownTools(items)
        var excerpts: [SessionMapPlanningExcerpt] = []
        var diagnostics: [SessionMapDiagnostic] = []
        var usedBytes = 0

        for observation in observations {
            let remaining = maxTotalBytes - usedBytes
            guard remaining > 0 else {
                diagnostics.append(diagnostic(
                    "planningExcerptTotalLimit",
                    ref: observation.ref,
                    detail: "Planning excerpt total reached \(maxTotalBytes) bytes."))
                break
            }
            let source: String
            var wasReadTruncated = false
            if let captured = observation.captured {
                source = captured
            } else {
                guard let url = containedURL(path: observation.path, projectURL: projectURL) else {
                    diagnostics.append(diagnostic(
                        "planningExcerptOutsideProject",
                        ref: observation.ref,
                        detail: "Observed Markdown path is outside the session project."))
                    continue
                }
                do {
                    guard let fileSource = try boundedUTF8(at: url) else {
                        diagnostics.append(diagnostic(
                            "planningExcerptInvalidUTF8",
                            ref: observation.ref,
                            detail: "Observed Markdown file is not valid UTF-8."))
                        continue
                    }
                    source = fileSource.text
                    wasReadTruncated = fileSource.wasTruncated
                } catch {
                    diagnostics.append(diagnostic(
                        "planningExcerptUnreadable",
                        ref: observation.ref,
                        detail: "Observed Markdown file could not be read."))
                    continue
                }
            }

            let limit = min(maxFileBytes, remaining)
            let text = SessionMapDigestBuilder.utf8Prefix(source, maxBytes: limit)
            guard !text.isEmpty else { continue }
            if wasReadTruncated || text.utf8.count < source.utf8.count {
                diagnostics.append(diagnostic(
                    "planningExcerptTruncated",
                    ref: observation.ref,
                    detail: "Planning excerpt was truncated to its byte limit."))
            }
            excerpts.append(SessionMapPlanningExcerpt(
                file: observation.path,
                ref: observation.ref,
                text: text,
                hash: sha256(text)))
            usedBytes += text.utf8.count
        }
        return SessionMapPlanningExcerptResult(excerpts: excerpts, diagnostics: diagnostics)
    }

    private struct Observation {
        let path: String
        let ref: String
        let captured: String?
    }

    private static func observedMarkdownTools(_ items: [TranscriptItem]) -> [Observation] {
        var order: [String] = []
        var byPath: [String: Observation] = [:]
        for item in items {
            guard case .tool(let tool) = item, tool.phase == .complete else { continue }
            let name = tool.name.lowercased()
            let file = ToolContentExtractor.file(tool)
            let path = file?.path ?? ToolContentExtractor.edit(tool)?.path
            guard let path, URL(fileURLWithPath: path).pathExtension.lowercased() == "md" else {
                continue
            }
            let captured: String? = if name == "write" {
                tool.arguments["content"]?.stringValue ?? tool.arguments["text"]?.stringValue
            } else if name == "read" {
                file?.preview
            } else {
                nil
            }
            if byPath[path] == nil { order.append(path) }
            byPath[path] = Observation(
                path: path,
                ref: tool.id,
                captured: captured.flatMap { $0.isEmpty ? nil : $0 })
        }
        return order.compactMap { byPath[$0] }
    }

    private static func containedURL(path: String, projectURL: URL) -> URL? {
        let root = projectURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = (path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : root.appending(path: path))
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
    }

    private struct BoundedText {
        let text: String
        let wasTruncated: Bool
    }

    private static func boundedUTF8(at url: URL) throws -> BoundedText? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxFileBytes + 4) ?? Data()
        if data.count <= maxFileBytes {
            return String(data: data, encoding: .utf8).map {
                BoundedText(text: $0, wasTruncated: false)
            }
        }
        var end = maxFileBytes
        while end > max(0, maxFileBytes - 4) {
            if let source = String(data: data.prefix(end), encoding: .utf8) {
                return BoundedText(
                    text: source,
                    wasTruncated: true)
            }
            end -= 1
        }
        return nil
    }

    private static func diagnostic(
        _ code: String,
        ref: String,
        detail: String
    ) -> SessionMapDiagnostic {
        SessionMapDiagnostic(code: code, elementID: ref, detail: detail)
    }

    private static func sha256(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
