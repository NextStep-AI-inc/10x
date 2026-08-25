import Foundation
import OmpKit

enum ToolPhase: Equatable {
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

struct ToolPresentation: Identifiable, Equatable {
    let id: String
    var name: String
    var arguments: JSONValue
    var result: JSONValue?
    var phase: ToolPhase
    let startDate: Date
    var endDate: Date?

    var isError: Bool { phase == .failed }

    var durationLabel: String {
        let end = endDate ?? Date()
        return String(format: "%.1fs", max(0, end.timeIntervalSince(startDate)))
    }
}
