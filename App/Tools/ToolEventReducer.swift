import Foundation
import OmpKit

struct ToolEventReducer {
    private(set) var presentations: [ToolPresentation] = []

    mutating func consume(type: String, payload: JSONValue, at date: Date = Date()) {
        guard let id = payload["toolCallId"]?.stringValue else { return }
        let name = payload["toolName"]?.stringValue
        let arguments = payload["args"]

        if let index = presentations.firstIndex(where: { $0.id == id }) {
            if let name { presentations[index].name = name }
            if let arguments { presentations[index].arguments = arguments }
            apply(type: type, payload: payload, date: date, at: index)
            return
        }

        var presentation = ToolPresentation(
            id: id,
            name: name ?? "Unknown tool",
            arguments: arguments ?? .object([:]),
            result: nil,
            phase: .running,
            startDate: date,
            endDate: nil)
        switch type {
        case "tool_execution_update":
            presentation.result = payload["partialResult"]
        case "tool_execution_end":
            presentation.result = payload["result"]
            presentation.phase = payload["isError"]?.boolValue == true ? .failed : .complete
            presentation.endDate = date
        default:
            break
        }
        presentations.append(presentation)
    }

    private mutating func apply(
        type: String,
        payload: JSONValue,
        date: Date,
        at index: Int
    ) {
        switch type {
        case "tool_execution_update":
            presentations[index].result = payload["partialResult"]
            presentations[index].phase = .running
        case "tool_execution_end":
            let result = payload["result"]
            let phase: ToolPhase = payload["isError"]?.boolValue == true ? .failed : .complete
            let alreadyApplied = presentations[index].result == result
                && presentations[index].phase == phase
            presentations[index].result = result
            presentations[index].phase = phase
            if !alreadyApplied {
                presentations[index].endDate = date
            }
        default:
            break
        }
    }
}
