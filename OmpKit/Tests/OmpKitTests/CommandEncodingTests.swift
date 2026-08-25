import Testing
import Foundation
@testable import OmpKit

private func json(_ data: Data) throws -> [String: Any] {
    // dropLast strips the trailing newline the wire format requires.
    try JSONSerialization.jsonObject(with: data.dropLast()) as! [String: Any]
}

private func computerContractClient() -> RpcClient {
    var configuration = RpcClientConfiguration()
    configuration.executable = "/usr/bin/env"
    configuration.extraArguments = [
        "python3", fixtureURL("fake_server.py").path, "basic", "--computer-contract",
    ]
    configuration.rawArgv = true
    configuration.noSession = true
    return RpcClient(configuration: configuration)
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

@Test func computerUseCommandsEncodeTheForegroundPolicy() throws {
    let line = try RpcCommand.setComputerUse(
        enabled: true,
        foregroundPolicy: .requireHandoff
    ).encodedLine(id: "computer-1")
    let value = try JSONValue.decode(from: line)
    #expect(value["type"]?.stringValue == "set_computer_use")
    #expect(value["enabled"]?.boolValue == true)
    #expect(value["foregroundPolicy"]?.stringValue == "require-handoff")
    #expect(RpcCommand.getComputerUse().type == "get_computer_use")
    #expect(RpcCommand.probeComputerUse().type == "probe_computer_use")
}

@Test func computerUseStateAndProbeDecodeTheCompleteSafetyContract() {
    let state = ComputerUseRPCState(json: .object([
        "enabled": .bool(true),
        "foregroundPolicy": .string("require-handoff"),
    ]))
    #expect(state == ComputerUseRPCState(enabled: true, foregroundPolicy: .requireHandoff))

    let probe = ComputerProbeResult(json: .object([
        "capabilities": .object([
            "backend": .string("macos"),
            "capturePermission": .string("granted"),
            "inputPermission": .string("granted"),
            "axPermission": .string("granted"),
        ]),
        "captureSucceeded": .bool(true),
        "backgroundInputSucceeded": .bool(true),
    ]))
    #expect(probe?.capabilities.isReady == true)
    #expect(probe?.captureSucceeded == true)
    #expect(probe?.backgroundInputSucceeded == true)
}

@Test func probePreservesOpaqueWindowTargets() throws {
    let line = try RpcCommand.probeComputerUse(target: "42", verificationText: "ready")
        .encodedLine(id: "probe-1")
    let value = try JSONValue.decode(from: line)
    #expect(value["target"]?.stringValue == "42")
    #expect(value["verificationText"]?.stringValue == "ready")
}

@Test func hostToolCommandsUseTheRequestIDForResults() throws {
    let definition = HostToolDefinition(
        name: "agent_desktop",
        description: "Launch a dedicated app window",
        parameters: .object(["type": .string("object")])
    )
    let tools = try JSONValue.decode(from: RpcCommand.setHostTools([definition]).encodedLine(id: "tools-1"))
    #expect(tools == .object([
        "id": .string("tools-1"),
        "type": .string("set_host_tools"),
        "tools": .array([.object([
            "name": .string("agent_desktop"),
            "description": .string("Launch a dedicated app window"),
            "parameters": .object(["type": .string("object")]),
        ])]),
    ]))

    let partialResult: JSONValue = .object(["content": .array([])])
    let partial = try JSONValue.decode(from: RpcCommand.hostToolUpdate(
        id: "host-1", partialResult: partialResult
    ).encodedLine(id: "ignored"))
    #expect(partial == .object([
        "id": .string("host-1"),
        "type": .string("host_tool_update"),
        "partialResult": partialResult,
    ]))

    let resultValue: JSONValue = .object([
        "content": .array([.object(["type": .string("text"), "text": .string("done")])]),
    ])
    let result = try JSONValue.decode(from: RpcCommand.hostToolResult(
        id: "host-1", result: resultValue,
        isError: false
    ).encodedLine(id: "ignored"))
    #expect(result == .object([
        "id": .string("host-1"),
        "type": .string("host_tool_result"),
        "result": resultValue,
        "isError": .bool(false),
    ]))
}

@Test func computerForegroundHandoffResponseEchoesTheUIRequestID() throws {
    let response = try JSONValue.decode(from: RpcCommand.computerForegroundHandoffResponse(
        id: "handoff-1", approved: true
    ).encodedLine(id: "ignored"))
    #expect(response["type"]?.stringValue == "extension_ui_response")
    #expect(response["id"]?.stringValue == "handoff-1")
    #expect(response["approved"]?.boolValue == true)
}

@Test func computerContractFixtureSeparatesSupportedAndLegacyServers() async throws {
    let supported = computerContractClient()
    _ = try await supported.start()
    let state = try await supported.send(.getState())
    #expect(ComputerUseRPCState(json: state.data?["computerUse"]) == ComputerUseRPCState(
        enabled: false, foregroundPolicy: .requireHandoff
    ))
    let configured = try await supported.send(.setComputerUse(
        enabled: true, foregroundPolicy: .requireHandoff
    ))
    #expect(ComputerUseRPCState(json: configured.data) == ComputerUseRPCState(
        enabled: true, foregroundPolicy: .requireHandoff
    ))
    let probe = try await supported.send(.probeComputerUse())
    #expect(probe.data?["capabilities"]?["capturePermission"]?.stringValue == "granted")
    let tools = try await supported.send(.setHostTools([HostToolDefinition(
        name: "agent_desktop",
        description: "Launch a dedicated app window",
        parameters: .object(["type": .string("object")])
    )]))
    #expect(tools.data?["toolNames"]?.arrayValue?.compactMap(\.stringValue) == ["agent_desktop"])
    await supported.shutdown()

    let legacy = makeClient(mode: "basic")
    _ = try await legacy.start()
    let legacyState = try await legacy.send(.getState())
    #expect(ComputerUseRPCState(json: legacyState.data?["computerUse"]) == nil)
    do {
        _ = try await legacy.send(.setComputerUse(enabled: true, foregroundPolicy: .requireHandoff))
        Issue.record("expected an unknown-command failure")
    } catch let error as RpcClientError {
        guard case .commandFailed(let command, let message, let code) = error else {
            Issue.record("wrong legacy downgrade error: \(error)")
            await legacy.shutdown()
            return
        }
        #expect(command == "set_computer_use")
        #expect(message == "Unknown command: set_computer_use")
        #expect(code == nil)
    } catch {
        Issue.record("wrong legacy downgrade error: \(error)")
    }
    await legacy.shutdown()
}

@Test func hostToolFramesTraverseClientEvents() async throws {
    let client = makeClient(mode: "host-tool-events")
    let stream = client.events
    let driver = Task {
        _ = try? await client.start()
        _ = try? await client.send(.getState())
    }
    defer { driver.cancel() }

    let frames = await withTimeout(.seconds(1)) { () -> [RpcFrame] in
        var frames: [RpcFrame] = []
        for await frame in stream {
            if case .hostToolCall = frame { frames.append(frame) }
            if case .hostToolCancel = frame { frames.append(frame) }
            if frames.count == 2 { break }
        }
        return frames
    } ?? []

    guard frames.count == 2,
          case .hostToolCall(let call) = frames[0],
          case .hostToolCancel(let cancelID, let targetID) = frames[1]
    else {
        Issue.record("Expected host-tool call and cancel frames")
        await client.shutdown()
        return
    }
    #expect(call.id == "host-1")
    #expect(call.toolCallID == "tool-1")
    #expect(call.name == "agent_desktop")
    #expect(call.arguments == .object([
        "action": .string("launch"),
        "application": .string("TextEdit"),
    ]))
    #expect(cancelID == "cancel-1")
    #expect(targetID == "host-1")
    await client.shutdown()
}
