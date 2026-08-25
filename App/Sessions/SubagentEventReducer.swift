import Foundation
import OmpKit

struct SubagentEventReducer {
    private(set) var presentations: [SubagentPresentation] = []

    mutating func consume(type: String, payload: JSONValue) {
        let body = payload["payload"] ?? payload
        switch type {
        case "subagent_lifecycle":
            consumeLifecycle(body)
        case "subagent_progress":
            consumeProgress(body)
        default:
            break
        }
    }

    mutating func attachResult(parentToolCallID: String, result: JSONValue) {
        for index in presentations.indices where
            presentations[index].parentToolCallID == parentToolCallID {
            presentations[index].result = result
        }
    }

    private mutating func consumeLifecycle(_ body: JSONValue) {
        guard let id = body["id"]?.stringValue else { return }
        let status = status(body["status"]?.stringValue, fallback: .started)
        if let index = presentations.firstIndex(where: { $0.id == id }) {
            presentations[index].agent = body["agent"]?.stringValue ?? presentations[index].agent
            presentations[index].description = body["description"]?.stringValue
                ?? presentations[index].description
            presentations[index].task = body["description"]?.stringValue
                ?? presentations[index].task
            presentations[index].status = status
            presentations[index].sessionFile = body["sessionFile"]?.stringValue
                ?? presentations[index].sessionFile
            presentations[index].parentToolCallID = body["parentToolCallId"]?.stringValue
                ?? presentations[index].parentToolCallID
            return
        }
        presentations.append(SubagentPresentation(
            id: id,
            index: body["index"]?.intValue ?? presentations.count,
            agent: body["agent"]?.stringValue ?? "subagent",
            task: body["description"]?.stringValue ?? "Delegated task",
            assignment: nil,
            description: body["description"]?.stringValue,
            status: status,
            sessionFile: body["sessionFile"]?.stringValue,
            parentToolCallID: body["parentToolCallId"]?.stringValue,
            actualModel: nil,
            thinkingLevel: nil,
            modelRole: nil,
            isFallback: false,
            currentTool: nil,
            recentTools: [],
            recentOutput: [],
            toolCount: 0,
            requests: nil,
            tokens: nil,
            cost: nil,
            durationMilliseconds: 0,
            result: nil))
    }

    private mutating func consumeProgress(_ body: JSONValue) {
        guard let progress = body["progress"] else { return }
        let indexValue = body["index"]?.intValue ?? progress["index"]?.intValue ?? 0
        let id = progress["id"]?.stringValue
            ?? presentations.first(where: { $0.index == indexValue })?.id
            ?? "subagent-\(indexValue)"
        let duration = progress["durationMs"]?.doubleValue ?? 0
        let index: Int
        if let existing = presentations.firstIndex(where: { $0.id == id }) {
            guard duration >= presentations[existing].durationMilliseconds else { return }
            index = existing
        } else {
            presentations.append(SubagentPresentation(
                id: id,
                index: indexValue,
                agent: body["agent"]?.stringValue ?? progress["agent"]?.stringValue ?? "subagent",
                task: body["task"]?.stringValue ?? progress["task"]?.stringValue ?? "Delegated task",
                assignment: nil,
                description: nil,
                status: .pending,
                sessionFile: nil,
                parentToolCallID: nil,
                actualModel: nil,
                thinkingLevel: nil,
                modelRole: nil,
                isFallback: false,
                currentTool: nil,
                recentTools: [],
                recentOutput: [],
                toolCount: 0,
                requests: nil,
                tokens: nil,
                cost: nil,
                durationMilliseconds: 0,
                result: nil))
            index = presentations.index(before: presentations.endIndex)
        }

        presentations[index].index = indexValue
        presentations[index].agent = body["agent"]?.stringValue
            ?? progress["agent"]?.stringValue
            ?? presentations[index].agent
        presentations[index].task = body["task"]?.stringValue
            ?? progress["task"]?.stringValue
            ?? presentations[index].task
        presentations[index].assignment = body["assignment"]?.stringValue
            ?? progress["assignment"]?.stringValue
            ?? presentations[index].assignment
        presentations[index].description = progress["description"]?.stringValue
            ?? presentations[index].description
        presentations[index].status = status(
            progress["status"]?.stringValue,
            fallback: presentations[index].status)
        presentations[index].sessionFile = body["sessionFile"]?.stringValue
            ?? presentations[index].sessionFile
        presentations[index].parentToolCallID = body["parentToolCallId"]?.stringValue
            ?? presentations[index].parentToolCallID
        let model = Self.model(progress["resolvedModel"]?.stringValue)
        presentations[index].actualModel = model.id ?? presentations[index].actualModel
        presentations[index].thinkingLevel = model.thinking ?? presentations[index].thinkingLevel
        presentations[index].modelRole = progress["modelRole"]?.stringValue
            ?? presentations[index].modelRole
        presentations[index].isFallback = progress["resolvedModelIsFallback"]?.boolValue
            ?? presentations[index].isFallback
        presentations[index].currentTool = progress["currentTool"]?.stringValue
        presentations[index].recentTools = Array((progress["recentTools"]?.arrayValue ?? [])
            .compactMap(Self.recentTool).suffix(3))
        presentations[index].recentOutput = Array((progress["recentOutput"]?.arrayValue ?? [])
            .compactMap(\.stringValue).suffix(3))
        presentations[index].toolCount = progress["toolCount"]?.intValue
            ?? presentations[index].toolCount
        presentations[index].requests = progress["requests"]?.intValue
            ?? presentations[index].requests
        presentations[index].tokens = progress["tokens"]?.intValue
            ?? presentations[index].tokens
        presentations[index].cost = progress["cost"]?.doubleValue
            ?? presentations[index].cost
        presentations[index].durationMilliseconds = duration
    }

    private func status(_ value: String?, fallback: SubagentStatus) -> SubagentStatus {
        value.flatMap(SubagentStatus.init(rawValue:)) ?? fallback
    }

    private static func recentTool(_ value: JSONValue) -> SubagentRecentTool? {
        guard let name = value["tool"]?.stringValue else { return nil }
        return SubagentRecentTool(
            name: name,
            arguments: value["args"],
            endMilliseconds: value["endMs"]?.doubleValue)
    }

    private static func model(_ resolved: String?) -> (id: String?, thinking: String?) {
        guard let resolved else { return (nil, nil) }
        let providerStripped = resolved.split(separator: "/").last.map(String.init) ?? resolved
        guard let colon = providerStripped.lastIndex(of: ":") else {
            return (providerStripped, nil)
        }
        return (
            String(providerStripped[..<colon]),
            String(providerStripped[providerStripped.index(after: colon)...]))
    }
}
