import Foundation
import OmpKit

enum SubagentStatus: String, Equatable {
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

struct SubagentRecentTool: Equatable, Identifiable {
    let name: String
    let arguments: JSONValue?
    let endMilliseconds: Double?

    var id: String { "\(name)-\(endMilliseconds ?? 0)" }
}

struct SubagentPresentation: Identifiable, Equatable {
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

    var resultText: String? {
        guard let result else { return nil }
        if let text = result.stringValue { return text }
        let text = result["content"]?.arrayValue?.compactMap { block in
            block["text"]?.stringValue
        }.joined(separator: "\n")
        return text.flatMap { $0.isEmpty ? nil : $0 }
    }
}
