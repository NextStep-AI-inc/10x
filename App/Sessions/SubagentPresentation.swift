import Foundation
import OmpKit

enum SubagentStatus: String, Equatable, Sendable {
    case pending
    case started
    case running
    case completed
    case failed
    case aborted

    var label: String {
        switch self {
        case .pending: "Pending"
        case .started, .running: "Running"
        case .completed: "Complete"
        case .failed: "Failed"
        case .aborted: "Aborted"
        }
    }

    var isActive: Bool { self == .pending || self == .started || self == .running }
    var isError: Bool { self == .failed || self == .aborted }
}

struct SubagentRecentTool: Equatable, Identifiable, Sendable {
    let name: String
    let arguments: JSONValue?
    let endMilliseconds: Double?

    var id: String { "\(name)-\(endMilliseconds ?? 0)" }
}

struct SubagentPresentation: Identifiable, Equatable, Sendable {
    let id: String
    var index: Int
    var agent: String
    var task: String
    var assignment: String?
    var description: String?
    var status: SubagentStatus
    var sessionFile: String?
    var parentToolCallID: String?
    var actualModel: String?
    var thinkingLevel: String?
    var modelRole: String?
    var isFallback: Bool
    var currentTool: String?
    var recentTools: [SubagentRecentTool]
    var recentOutput: [String]
    var toolCount: Int
    var requests: Int?
    var tokens: Int?
    var cost: Double?
    var durationMilliseconds: Double
    var result: JSONValue?

    var reportedSessionPath: String? {
        guard let sessionFile, !sessionFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return sessionFile
    }

    var recentToolSummaries: [String] {
        recentTools.suffix(3).map { tool in
            guard let argument = Self.usefulArgument(tool.arguments) else { return tool.name }
            return "\(tool.name) · \(argument.key): \(argument.value)"
        }
    }

    var resultText: String? {
        guard let result else { return nil }
        if let text = result.stringValue { return text }
        if let output = result["output"]?.stringValue, !output.isEmpty { return output }
        if let error = result["error"]?.stringValue, !error.isEmpty { return error }
        if let stderr = result["stderr"]?.stringValue, !stderr.isEmpty { return stderr }
        let text = result["content"]?.arrayValue?.compactMap { block in
            block["text"]?.stringValue
        }.joined(separator: "\n")
        return text.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func usefulArgument(_ arguments: JSONValue?) -> (key: String, value: String)? {
        for key in ["path", "file", "command", "query"] {
            guard let rawValue = arguments?[key]?.stringValue else { continue }
            let compact = rawValue
                .split(whereSeparator: \Character.isWhitespace)
                .joined(separator: " ")
            guard !compact.isEmpty else { continue }
            let limit = 120
            let value = compact.count > limit
                ? String(compact.prefix(limit - 1)) + "…"
                : compact
            return (key, value)
        }
        return nil
    }
}
