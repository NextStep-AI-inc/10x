import Foundation
import OmpKit

struct ToolEventReducer {
    private(set) var presentations: [ToolPresentation] = []
    private var displayErrorSettledIDs: Set<String> = []

    @discardableResult
    mutating func interruptRunning(at date: Date) -> Bool {
        var changed = false
        for index in presentations.indices where presentations[index].phase == .running {
            presentations[index].update(phase: .interrupted, endDate: .some(date))
            changed = true
        }
        return changed
    }

    mutating func consume(type: String, payload: JSONValue, at date: Date = Date()) {
        guard let id = payload["toolCallId"]?.stringValue else { return }
        let name = payload["toolName"]?.stringValue
        let arguments = payload["args"]

        if type == "tool_execution_end", Self.isMissingTerminalResult(payload) {
            if presentations.contains(where: { $0.id == id }) {
                _ = settleDisplayError(id: id, at: date)
            }
            return
        }

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

    @discardableResult
    mutating func settleDisplayError(id: String, at date: Date) -> Bool {
        guard !displayErrorSettledIDs.contains(id) else { return false }
        displayErrorSettledIDs.insert(id)
        let errorResult = JSONValue.object([
            "error": .string(EventDiagnosticDisplay.settledUpdateError),
        ])
        guard let index = presentations.firstIndex(where: { $0.id == id }) else { return false }
        presentations[index].update(
            result: .some(errorResult),
            phase: .failed,
            endDate: .some(date))
        return true
    }

    static func isMissingTerminalResult(_ payload: JSONValue) -> Bool {
        payload["result"] == nil || payload["result"] == .null
    }

    private mutating func apply(
        type: String,
        payload: JSONValue,
        date: Date,
        at index: Int
    ) {
        let id = presentations[index].id
        guard !displayErrorSettledIDs.contains(id) else { return }
        guard presentations[index].phase != .interrupted else { return }
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
            let boundedResult = result.map(ToolPayloadBudget.limit)
            let alreadyApplied = presentations[index].result == boundedResult
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
