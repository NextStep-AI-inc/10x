import Foundation
import OmpKit

struct ToolEventReducer {
    private(set) var presentations: [ToolPresentation] = []

    mutating func consume(type: String, payload: JSONValue, at date: Date = Date()) {
        guard let id = payload["toolCallId"]?.stringValue else { return }
        let name = payload["toolName"]?.stringValue
        let arguments = payload["args"]

        if let index = presentations.firstIndex(where: { $0.id == id }) {
            apply(type: type, payload: payload, date: date, at: index)
            return
        }

        let result: JSONValue?
        let phase: ToolPhase
        let endDate: Date?
        switch type {
        case "tool_execution_update":
            result = payload["partialResult"]
            phase = .running
            endDate = nil
        case "tool_execution_end":
            result = payload["result"]
            phase = payload["isError"]?.boolValue == true ? .failed : .complete
            endDate = date
        default:
            result = nil
            phase = .running
            endDate = nil
        }
        presentations.append(ToolPresentation(
            id: id,
            name: name ?? "Unknown tool",
            arguments: arguments ?? .object([:]),
            result: result,
            phase: phase,
            startDate: date,
            endDate: endDate))
    }

    private mutating func apply(
        type: String,
        payload: JSONValue,
        date: Date,
        at index: Int
    ) {
        let name = payload["toolName"]?.stringValue
        let arguments = payload["args"]
        switch type {
        case "tool_execution_update":
            presentations[index].update(
                name: name,
                arguments: arguments,
                result: .some(payload["partialResult"]),
                phase: .running)
        case "tool_execution_end":
            let result = payload["result"]
            let phase: ToolPhase = payload["isError"]?.boolValue == true ? .failed : .complete
            let alreadyApplied = presentations[index].result == result
                && presentations[index].phase == phase
            presentations[index].update(
                name: name,
                arguments: arguments,
                result: .some(result),
                phase: phase,
                endDate: alreadyApplied ? nil : .some(date))
        default:
            presentations[index].update(name: name, arguments: arguments)
        }
    }
}
