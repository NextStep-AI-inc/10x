import Foundation
import OmpKit

enum ToolPhase: Equatable {
    case running
    case complete
    case failed
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
}
