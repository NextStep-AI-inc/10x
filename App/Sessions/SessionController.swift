import Foundation
import Observation
import OmpKit

@MainActor
@Observable
final class SessionController {
    private(set) var items: [TranscriptItem] = []
    private(set) var runtimeState: SessionRuntimeState = .loading
    private(set) var title = "Untitled session"
    private(set) var headerMetadata = SessionHeaderMetadata(
        branch: "",
        repo: "",
        worktreePath: nil)
    private(set) var modelName = "Model"
    private(set) var thinkingLevel = "Thinking"
    private(set) var contextPercentage: Int?
    private(set) var queuedMessageCount = 0
    private(set) var sessionPath: String?
    var draft = ""
    var streamingBehavior: StreamingBehavior? = .steer

    private let processManager: SessionProcessManager
    private var projectURL: URL?
    private var handle: SessionProcessManager.Handle?
    private var reducer = TranscriptReducer()
    private var eventTask: Task<Void, Never>?

    init(processManager: SessionProcessManager) {
        self.processManager = processManager
    }

    var isComposerAvailable: Bool {
        switch runtimeState {
        case .idle, .streaming:
            return true
        case .loading, .stopped, .failed:
            return false
        }
    }

    func openExisting(_ metadata: SessionMetadata) async {
        title = metadata.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session"
        let projectURL = URL(filePath: metadata.cwd, directoryHint: .isDirectory)
        self.projectURL = projectURL
        headerMetadata = await SessionHeaderMetadata.resolve(projectURL: projectURL)
        runtimeState = .loading

        do {
            let handle = try await processManager.open(
                sessionPath: metadata.path,
                cwd: metadata.cwd)
            try await finishOpening(handle)
        } catch {
            fail(error, function: "openExisting")
        }
    }

    func openNew(projectURL: URL) async {
        self.projectURL = projectURL
        title = "New session"
        headerMetadata = await SessionHeaderMetadata.resolve(projectURL: projectURL)
        runtimeState = .loading

        do {
            let handle = try await processManager.openNew(projectDirectory: projectURL.path)
            try await finishOpening(handle)
        } catch {
            fail(error, function: "openNew")
        }
    }

    func sendPrompt() async {
        guard let handle,
              isComposerAvailable,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        let behavior: StreamingBehavior?
        if runtimeState == .streaming {
            guard let streamingBehavior else { return }
            behavior = streamingBehavior
        } else {
            behavior = nil
        }

        let message = draft
        do {
            _ = try await handle.client.send(.prompt(
                message: message,
                streamingBehavior: behavior))
            draft = ""
            reducer.runtimeState = .streaming
            syncReducerState()
        } catch {
            fail(error, function: "sendPrompt")
        }
    }

    func abort() async {
        guard let handle, runtimeState == .streaming else { return }
        do {
            _ = try await handle.client.send(.abort())
        } catch {
            fail(error, function: "abort")
        }
    }

    func restart() async {
        guard let projectURL, let sessionPath else { return }
        eventTask?.cancel()
        await processManager.close(sessionPath: sessionPath)
        runtimeState = .loading
        do {
            let handle = try await processManager.open(
                sessionPath: sessionPath,
                cwd: projectURL.path)
            try await finishOpening(handle)
        } catch {
            fail(error, function: "restart")
        }
    }

    func selectStreamingBehavior(_ behavior: StreamingBehavior) {
        streamingBehavior = behavior
    }

    private func finishOpening(_ handle: SessionProcessManager.Handle) async throws {
        self.handle = handle
        sessionPath = handle.sessionPath

        let state = try await handle.client.send(.getState())
        applyState(state.data)
        let messages = try await loadMessages(client: handle.client)
        reducer.load(messages: messages)
        reducer.runtimeState = runtimeState
        syncReducerState()
        consumeEvents(from: handle.client)
    }

    private func loadMessages(client: RpcClient) async throws -> [JSONValue] {
        do {
            var messages: [JSONValue] = []
            var cursor: String?
            repeat {
                let response = try await client.send(.getMessagesPage(cursor: cursor, limit: 256))
                guard let data = response.data else { break }
                messages.append(contentsOf: data["messages"]?.arrayValue ?? [])
                cursor = data["nextCursor"]?.stringValue
            } while cursor != nil
            return messages
        } catch {
            let response = try await client.send(.getMessages())
            return response.data?["messages"]?.arrayValue
                ?? response.data?.arrayValue
                ?? []
        }
    }

    private func consumeEvents(from client: RpcClient) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await frame in client.events {
                guard let self, !Task.isCancelled else { return }
                self.reducer.consume(frame)
                self.syncReducerState()
                self.applyEventMetadata(frame)
            }
        }
    }

    private func applyState(_ data: JSONValue?) {
        guard let data else {
            runtimeState = .idle
            return
        }
        title = data["sessionName"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? title
        modelName = Self.modelLabel(data["model"]) ?? modelName
        thinkingLevel = data["thinkingLevel"]?.stringValue?.capitalized ?? thinkingLevel
        contextPercentage = Self.contextPercent(data["contextUsage"])
        queuedMessageCount = data["queuedMessageCount"]?.intValue ?? 0
        runtimeState = data["isStreaming"]?.boolValue == true ? .streaming : .idle
        if let reportedPath = data["sessionFile"]?.stringValue {
            sessionPath = reportedPath
        }
    }

    private func applyEventMetadata(_ frame: RpcFrame) {
        guard case .event(let type, let payload) = frame else { return }
        switch type {
        case "session_info_update":
            title = payload["title"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? title
        case "config_update":
            modelName = Self.modelLabel(payload["model"]) ?? modelName
            thinkingLevel = payload["thinkingLevel"]?.stringValue?.capitalized ?? thinkingLevel
        case "thinking_level_changed":
            thinkingLevel = payload["thinkingLevel"]?.stringValue?.capitalized ?? thinkingLevel
        case "model_changed":
            Task { [weak self] in await self?.refreshState() }
        default:
            break
        }
    }

    private func refreshState() async {
        guard let handle else { return }
        do {
            applyState(try await handle.client.send(.getState()).data)
            reducer.runtimeState = runtimeState
        } catch {
            fail(error, function: "refreshState")
        }
    }

    private func syncReducerState() {
        items = reducer.items
        runtimeState = reducer.runtimeState
    }

    private func fail(_ error: any Error, function: String) {
        runtimeState = .failed("[Session:\(function)] Session command failed: \(error)")
        reducer.runtimeState = runtimeState
    }

    private static func modelLabel(_ value: JSONValue?) -> String? {
        value?.stringValue
            ?? value?["id"]?.stringValue
            ?? value?["modelId"]?.stringValue
            ?? value?["name"]?.stringValue
    }

    static func contextPercent(_ value: JSONValue?) -> Int? {
        if let percentage = value?["percentage"]?.doubleValue ?? value?["percent"]?.doubleValue {
            return clampedPercent(percentage <= 1 ? percentage * 100 : percentage)
        }
        guard let used = value?["tokens"]?.doubleValue ?? value?["used"]?.doubleValue,
              let limit = value?["contextWindow"]?.doubleValue ?? value?["limit"]?.doubleValue,
              limit > 0
        else { return nil }
        return clampedPercent(used / limit * 100)
    }

    private static func clampedPercent(_ percentage: Double) -> Int {
        Int(min(100, max(0, percentage)).rounded())
    }
}
