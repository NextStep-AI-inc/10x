import AppKit
import Foundation
import Observation
import OmpKit
import UserNotifications

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
    private(set) var extensionSheetRequest: ExtensionUIState?
    private(set) var isRecoveryPresented = false
    private(set) var isLogPresented = false
    private(set) var logText = ""
    var draft = ""
    var streamingBehavior: StreamingBehavior? = .steer

    private let processManager: SessionProcessManager
    private let timelineLoader = SessionTimelineLoader()
    private(set) var projectURL: URL?
    private var fallbackThreadStartDate: Date?
    private var handle: SessionProcessManager.Handle?
    private var reducer = TranscriptReducer()
    private var extensionRouter = ExtensionUIRouter()
    private var eventTask: Task<Void, Never>?
    private var reconciliationTask: Task<Void, Never>?
    private var extensionTimeoutTasks: [String: Task<Void, Never>] = [:]

    init(processManager: SessionProcessManager) {
        self.processManager = processManager
    }

    init(
        processManager: SessionProcessManager,
        previewItems: [TranscriptItem],
        runtimeState: SessionRuntimeState,
        title: String = "Transcript",
        modelName: String = "GPT-5.6",
        thinkingLevel: String = "High"
    ) {
        self.processManager = processManager
        self.items = previewItems
        self.runtimeState = runtimeState
        self.title = title
        self.modelName = modelName
        self.thinkingLevel = thinkingLevel
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
        fallbackThreadStartDate = metadata.created
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
        fallbackThreadStartDate = Date()
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
        reconciliationTask?.cancel()
        await processManager.close(sessionPath: sessionPath)
        runtimeState = .loading
        isRecoveryPresented = false
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

    func respond(to state: ExtensionUIState, with response: ExtensionUIResponse) async {
        guard let handle else { return }
        do {
            try await handle.client.sendRaw(.extensionUIResponse(id: state.id, body: response.body))
            removeExtensionRequest(id: state.id)
        } catch {
            fail(error, function: "respondToExtensionUI")
        }
    }

    func openURL(_ url: URL, requestID: String) {
        NSWorkspace.shared.open(url)
        removeExtensionRequest(id: requestID)
    }

    func copyURL(_ url: URL, requestID: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        removeExtensionRequest(id: requestID)
    }

    func handleUnexpectedExit(code: Int32?, stderrTail: String) {
        runtimeState = .stopped(code: code, stderrTail: stderrTail)
        reducer.runtimeState = runtimeState
        isRecoveryPresented = true
        logText = stderrTail.isEmpty ? "OMP exited without stderr output." : stderrTail
    }

    func dismissRecovery() {
        isRecoveryPresented = false
    }

    func openLog() {
        isLogPresented = true
    }

    func dismissLog() {
        isLogPresented = false
    }

    private func finishOpening(_ handle: SessionProcessManager.Handle) async throws {
        self.handle = handle
        sessionPath = handle.sessionPath

        let state = try await handle.client.send(.getState())
        applyState(state.data)
        var didLoadHistory = false
        var didHistoryLoadFail = false
        if let sessionPath {
            do {
                if let history = try await timelineLoader.load(path: sessionPath) {
                    reducer.load(history: history)
                    didLoadHistory = true
                }
            } catch {
                didHistoryLoadFail = true
            }
        }
        if !didLoadHistory {
            reducer.load(messages: try await loadMessages(client: handle.client))
        }
        reducer.ensureThreadStart(date: fallbackThreadStartDate)
        reducer.setReconciliationWarning(isPresented: didHistoryLoadFail)
        reducer.runtimeState = runtimeState
        syncReducerState()
        _ = try? await handle.client.send(.setSubagentSubscription(level: .progress))
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
                if case .extensionUIRequest(let request) = frame {
                    self.consumeExtensionUI(request)
                } else {
                    self.reducer.consume(frame)
                }
                self.syncReducerState()
                self.applyEventMetadata(frame)
                self.reconcileAfterBoundary(frame)
            }
        }
    }

    private func reconcileAfterBoundary(_ frame: RpcFrame) {
        guard case .event(let type, let payload) = frame else { return }
        let isBoundary = switch type {
        case "message_end", "turn_end", "prompt_result":
            true
        case "agent_end":
            payload["isTerminal"]?.boolValue != false
        default:
            false
        }
        guard isBoundary, let sessionPath else { return }

        reconciliationTask?.cancel()
        reconciliationTask = Task { [weak self, timelineLoader] in
            guard let self, !Task.isCancelled else { return }
            do {
                for delay in [0, 100, 250, 500, 1_000] {
                    if delay > 0 {
                        try await Task.sleep(for: .milliseconds(delay))
                    }
                    guard !Task.isCancelled else { return }
                    if let history = try await timelineLoader.load(path: sessionPath) {
                        self.reducer.reconcile(history: history)
                        self.reducer.setReconciliationWarning(isPresented: false)
                        self.syncReducerState()
                        if !self.reducer.hasPendingPersistence { return }
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                self.reducer.setReconciliationWarning(isPresented: true)
                self.syncReducerState()
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

    private func consumeExtensionUI(_ request: ExtensionUIRequest) {
        guard let state = ExtensionUIRouter.parse(request) else { return }
        extensionRouter.consume(request)

        switch state {
        case .confirm, .select:
            reducer.upsertExtensionUI(state)
            scheduleTimeout(for: state)
        case .input, .editor:
            extensionSheetRequest = state
            scheduleTimeout(for: state)
        case .cancel(_, let targetID):
            removeExtensionRequest(id: targetID)
        case .notification(_, let message, let level):
            reducer.appendNotice(level: level, message: message)
            postNotification(message: message)
        case .title(_, let updatedTitle):
            title = updatedTitle
        case .setEditorText(_, let text):
            draft = text
            extensionRouter.clearEditorText()
        case .openURL:
            reducer.upsertExtensionUI(state)
        case .status, .widget:
            break
        }
    }

    private func scheduleTimeout(for state: ExtensionUIState) {
        let timeout: Int?
        switch state {
        case .confirm(_, _, _, let value),
             .select(_, _, _, let value),
             .input(_, _, _, let value):
            timeout = value
        default:
            timeout = nil
        }
        guard let timeout, timeout > 0 else { return }
        extensionTimeoutTasks[state.id]?.cancel()
        extensionTimeoutTasks[state.id] = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(timeout)) }
            catch { return }
            guard let self else { return }
            await self.respond(to: state, with: .cancelled(timedOut: true))
        }
    }

    private func removeExtensionRequest(id: String) {
        extensionTimeoutTasks.removeValue(forKey: id)?.cancel()
        extensionRouter.removeRequest(id: id)
        reducer.removeExtensionUI(id: id)
        if extensionSheetRequest?.id == id { extensionSheetRequest = nil }
        syncReducerState()
    }

    private func postNotification(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "10x"
        content.body = message
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
