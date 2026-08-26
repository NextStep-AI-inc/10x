import Testing
import Foundation
@testable import OmpKit

private func json(_ data: Data) throws -> [String: Any] {
    // dropLast strips the trailing newline the wire format requires.
    try JSONSerialization.jsonObject(with: data.dropLast()) as! [String: Any]
}

@Test func encodesPromptWithBehavior() throws {
    let line = try RpcCommand.prompt(message: "hi", streamingBehavior: .followUp)
        .encodedLine(id: "req_1")
    let obj = try json(line)
    #expect(obj["id"] as? String == "req_1")
    #expect(obj["type"] as? String == "prompt")
    #expect(obj["message"] as? String == "hi")
    #expect(obj["streamingBehavior"] as? String == "followUp")
    #expect(line.last == UInt8(ascii: "\n"))
}

@Test func omitsNilFields() throws {
    let obj = try json(try RpcCommand.prompt(message: "x", streamingBehavior: nil)
        .encodedLine(id: "req_2"))
    #expect(obj["streamingBehavior"] == nil)
}

@Test func switchSessionUsesSessionPathKey() throws {
    let obj = try json(try RpcCommand.switchSession(path: "/tmp/s.jsonl").encodedLine(id: "req_3"))
    #expect(obj["type"] as? String == "switch_session")
    #expect(obj["sessionPath"] as? String == "/tmp/s.jsonl")
}

@Test func extensionUIResponseHasNoRequestId() throws {
    let cmd = RpcCommand.extensionUIResponse(id: "abc", body: ["confirmed": .bool(true)])
    let obj = try json(try cmd.encodedLine(id: "req_9"))
    #expect(obj["type"] as? String == "extension_ui_response")
    #expect(obj["id"] as? String == "abc")        // the UI request id, NOT req_9
    #expect(obj["confirmed"] as? Bool == true)
}

@Test func negotiateProtocolCarriesVersion() throws {
    let obj = try json(try RpcCommand.negotiateProtocol(version: 2).encodedLine(id: "req_4"))
    #expect(obj["type"] as? String == "negotiate_protocol")
    #expect(obj["protocolVersion"] as? Int == 2)
}

@Test func setModelUsesProviderAndModelId() throws {
    let obj = try json(try RpcCommand.setModel(provider: "anthropic", modelId: "claude-opus-5")
        .encodedLine(id: "req_5"))
    #expect(obj["provider"] as? String == "anthropic")
    #expect(obj["modelId"] as? String == "claude-opus-5")
}

@Test func getMessagesPageOmitsAbsentPaging() throws {
    let bare = try json(try RpcCommand.getMessagesPage(cursor: nil, limit: nil)
        .encodedLine(id: "req_6"))
    #expect(bare["type"] as? String == "get_messages_page")
    #expect(bare["cursor"] == nil)
    #expect(bare["limit"] == nil)

    let paged = try json(try RpcCommand.getMessagesPage(cursor: "abc", limit: 50)
        .encodedLine(id: "req_7"))
    #expect(paged["cursor"] as? String == "abc")
    #expect(paged["limit"] as? Int == 50)
}

@Test func subagentSubscriptionLevelEncodesRawValue() throws {
    let obj = try json(try RpcCommand.setSubagentSubscription(level: .events)
        .encodedLine(id: "req_8"))
    #expect(obj["type"] as? String == "set_subagent_subscription")
    #expect(obj["level"] as? String == "events")
}

@Test func getSubagentMessagesOmitsUnavailableSelectors() throws {
    let selected = try json(try RpcCommand.getSubagentMessages(
        subagentId: "agent-1",
        sessionFile: "/tmp/agent.jsonl",
        fromByte: 4096).encodedLine(id: "req_subagent"))
    #expect(selected["type"] as? String == "get_subagent_messages")
    #expect(selected["subagentId"] as? String == "agent-1")
    #expect(selected["sessionFile"] as? String == "/tmp/agent.jsonl")
    #expect(selected["fromByte"] as? Int == 4096)

    let bare = try json(try RpcCommand.getSubagentMessages(
        subagentId: nil,
        sessionFile: nil,
        fromByte: nil).encodedLine(id: "req_bare"))
    #expect(bare.count == 2)
}


@Test func simpleCommandsCarryOnlyIdAndType() throws {
    let obj = try json(try RpcCommand.getState().encodedLine(id: "req_10"))
    #expect(obj.count == 2)
    #expect(obj["type"] as? String == "get_state")
    #expect(obj["id"] as? String == "req_10")
}

@Test func abortAndNewSessionEncode() throws {
    #expect(try json(try RpcCommand.abort().encodedLine(id: "r")) ["type"] as? String == "abort")
    let ns = try json(try RpcCommand.newSession(parentSession: "/tmp/p.jsonl").encodedLine(id: "r"))
    #expect(ns["type"] as? String == "new_session")
    #expect(ns["parentSession"] as? String == "/tmp/p.jsonl")
    let bare = try json(try RpcCommand.newSession(parentSession: nil).encodedLine(id: "r"))
    #expect(bare["parentSession"] == nil)
}

@Test func setFastModeEncodesEnabledBool() throws {
    let obj = try json(try RpcCommand.setFastMode(enabled: false).encodedLine(id: "req_fast"))
    #expect(obj["type"] as? String == "set_fast_mode")
    #expect(obj["enabled"] as? Bool == false)
}

@Test func providerLoginCommandsMatchTheOMPContract() throws {
    let list = try json(try RpcCommand.getLoginProviders().encodedLine(id: "providers"))
    #expect(list.count == 2)
    #expect(list["id"] as? String == "providers")
    #expect(list["type"] as? String == "get_login_providers")

    let login = try json(try RpcCommand.login(providerID: "openai-codex")
        .encodedLine(id: "login"))
    #expect(login["id"] as? String == "login")
    #expect(login["type"] as? String == "login")
    #expect(login["providerId"] as? String == "openai-codex")
}
