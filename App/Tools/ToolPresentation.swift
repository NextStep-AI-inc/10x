import Foundation
import OmpKit

enum ToolPhase: Equatable, Sendable {
    case running
    case complete
    case failed
}

extension ToolPhase {
    var label: String {
        switch self {
        case .running: "Running"
        case .complete: "Complete"
        case .failed: "Error"
        }
    }
}

struct ToolPresentation: Identifiable, Equatable, Sendable {
    let id: String
    var name: String { didSet { refreshContent() } }
    var arguments: JSONValue { didSet { refreshContent() } }
    var result: JSONValue? { didSet { refreshContent() } }
    var phase: ToolPhase { didSet { refreshContent() } }
    let startDate: Date
    var endDate: Date?
    private(set) var content: ToolCardContent

    init(
        id: String,
        name: String,
        arguments: JSONValue,
        result: JSONValue?,
        phase: ToolPhase,
        startDate: Date,
        endDate: Date?
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.result = result
        self.phase = phase
        self.startDate = startDate
        self.endDate = endDate
        content = ToolContentExtractor.card(
            name: name,
            arguments: arguments,
            result: result,
            phase: phase)
    }

    var isError: Bool { phase == .failed }

    var durationLabel: String {
        let end = endDate ?? Date()
        return String(format: "%.1fs", max(0, end.timeIntervalSince(startDate)))
    }

    private mutating func refreshContent() {
        content = ToolContentExtractor.card(
            name: name,
            arguments: arguments,
            result: result,
            phase: phase)
    }
}
