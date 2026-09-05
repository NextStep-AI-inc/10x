import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Suite @MainActor struct SessionControllerQuestionTests {
    @Test func selectionThenEditorUsesExactFlatResponsesAndGuardsDuplicateSubmission() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "tenx-question-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let responseLog = directory.appending(path: "responses.jsonl")
        let executable = try makeQuestionExecutable(in: directory, responseLog: responseLog)
        let manager = SessionProcessManager(executable: executable.path)
        let controller = SessionController(processManager: manager)

        await controller.openExisting(questionMetadata(cwd: directory.path))
        #expect(await questionEventually {
            controller.questionState(id: "question-select") != nil
                && controller.hasPendingUserInput
        })
        let select = try #require(controller.questionState(id: "question-select"))

        let first = Task { await controller.respond(to: select, with: .value("Other (type your own)")) }
        let duplicate = Task { await controller.respond(to: select, with: .value("Other (type your own)")) }
        let results = [await first.value, await duplicate.value]

        #expect(results.filter { $0 }.count == 1)
        #expect(await questionEventually {
            controller.questionState(id: "question-editor") != nil
                && controller.hasPendingUserInput
        })
        let editor = try #require(controller.questionState(id: "question-editor"))
        #expect(await controller.respond(to: editor, with: .value("A custom answer")))
        #expect(await questionEventually { !controller.hasPendingUserInput })
        #expect(await questionEventually {
            (try? String(contentsOf: responseLog, encoding: .utf8).split(separator: "\n").count) == 2
        })

        let responses = try String(contentsOf: responseLog, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        try #require(responses.count == 2)
        #expect(responses[0]["id"] as? String == "question-select")
        #expect(responses[0]["value"] as? String == "Other (type your own)")
        #expect(responses[1]["id"] as? String == "question-editor")
        #expect(responses[1]["value"] as? String == "A custom answer")

        await controller.close()
    }

    @Test func stoppingClearsPendingQuestionState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "tenx-question-stop-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = try makeQuestionExecutable(
            in: directory,
            responseLog: directory.appending(path: "responses.jsonl"))
        let manager = SessionProcessManager(executable: executable.path)
        let controller = SessionController(processManager: manager)

        await controller.openExisting(questionMetadata(cwd: directory.path))
        #expect(await questionEventually { controller.hasPendingUserInput })
        await controller.close()

        #expect(!controller.hasPendingUserInput)
        #expect(controller.items.isEmpty)
    }
}

private func makeQuestionExecutable(in directory: URL, responseLog: URL) throws -> URL {
    let executable = directory.appending(path: "question-server.py")
    let source = #"""
    #!/usr/bin/env python3
    import json
    import sys

    response_log = "\#(responseLog.path)"

    def emit(value):
        print(json.dumps(value, separators=(",", ":")), flush=True)

    emit({"type":"ready","protocolVersion":1,"supportedProtocolVersions":[1,2],"maxFrameBytes":1048576,"maxReassembledFrameBytes":67108864})
    for line in sys.stdin:
        command = json.loads(line)
        request_id = command.get("id")
        command_type = command.get("type")
        if command_type == "negotiate_protocol":
            data = {"protocolVersion":2}
        elif command_type == "get_state":
            data = {"model":{"id":"gpt-test","provider":"openai-codex"},"isStreaming":False,"sessionFile":"/tmp/question-session.jsonl"}
        elif command_type == "get_messages_page":
            data = {"messages":[],"nextCursor":None}
        elif command_type == "set_subagent_subscription":
            emit({"id":request_id,"type":"response","command":command_type,"success":True,"data":{}})
            emit({"type":"extension_ui_request","id":"question-select","method":"select","title":"Choose an approach","options":["Direct","Other (type your own)"],"optionDetails":[{"description":"Use the suggested approach"},{"description":"Write a custom answer"}]})
            emit({"type":"extension_ui_request","id":"notice","method":"notify","message":"Waiting for input","notifyType":"info"})
            continue
        elif command_type == "extension_ui_response":
            with open(response_log, "a", encoding="utf-8") as log:
                log.write(json.dumps(command, separators=(",", ":")) + "\n")
            if request_id == "question-select":
                emit({"type":"extension_ui_request","id":"question-editor","method":"editor","title":"Enter your answer","prefill":"","promptStyle":True})
            continue
        else:
            data = {}
        emit({"id":request_id,"type":"response","command":command_type,"success":True,"data":data})
    """#
    try Data(source.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    return executable
}

private func questionMetadata(cwd: String) -> SessionMetadata {
    SessionMetadata(
        path: "/tmp/question-session.jsonl",
        sessionId: "question-session",
        cwd: cwd,
        title: "Questions",
        created: .distantPast,
        modified: .distantPast,
        sizeBytes: 0,
        status: .complete)
}

@MainActor
private func questionEventually(_ predicate: @escaping @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if predicate() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return predicate()
}

private extension SessionController {
    func questionState(id: String) -> ExtensionUIState? {
        items.compactMap { item -> ExtensionUIState? in
            guard case .extensionUI(let state) = item, state.id == id else { return nil }
            return state
        }.first
    }
}
