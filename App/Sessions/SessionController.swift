import AppKit
import Foundation
import Observation
import OmpKit
import os
import UserNotifications

@MainActor
@Observable
final class SessionController: ComposerSessionControlling, ProviderAccountSession {
    typealias HistoryLoader = @Sendable (String) async throws -> TranscriptHistory?
    private(set) var items: [TranscriptItem] = []
    private(set) var runtimeState: SessionRuntimeState = .loading
    private(set) var title = "Untitled session"
    private(set) var headerMetadata = SessionHeaderMetadata(
        branch: "",
        repo: "",
        worktreePath: nil)
    private(set) var modelName = "Model"
    private(set) var thinkingLevel = "Thinking"
    private(set) var liveComposerSelection = ComposerLiveSelection(
        provider: nil,
        modelID: nil,
        thinkingLevel: nil,
        fastModeEnabled: false)
    private(set) var contextPercentage: Int?
    private(set) var queuedMessageCount = 0
    private(set) var sessionPath: String?
    private(set) var extensionSheetRequest: ExtensionUIState?
    private(set) var isRecoveryPresented = false
    private(set) var isLogPresented = false
    private(set) var logText = ""
    let id: UUID
    private(set) var providerID: String?
    private(set) var activeProviderAccounts: [String: String] = [:]
    private(set) var providerAccountSequence = 0
    var draft = ""
    var streamingBehavior: StreamingBehavior? = .steer

    private let processManager: SessionProcessManager
    private let historyLoader: HistoryLoader
    private weak var accountCoordinator: ProviderAccountCoordinator?
    private(set) var projectURL: URL?
    private var fallbackThreadStartDate: Date?
    private var handle: SessionProcessManager.Handle?
    private var processor: TranscriptEventProcessor?
    private var installedSnapshotRevision: UInt64 = 0
    private var extensionRouter = ExtensionUIRouter()
    private var eventTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?
    private var controlTask: Task<Void, Never>?
    private var reconciliationTask: Task<Void, Never>?
    private var openingTask: Task<SessionProcessManager.Handle, any Error>?
    private var openingTaskToken: UInt64?
    private var openingCloseTask: Task<Void, Never>?
    private var reconciliationGeneration: UInt64 = 0
    private var pipelineGeneration: UInt64 = 0
    private var nextOpeningTaskToken: UInt64 = 0
    private var extensionTimeoutTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private weak var attachedComposerControls: ComposerControlsModel?
    private static let transcriptLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "TenXApp",
        category: .pointsOfInterest)

    private struct PipelineContext {
        let generation: UInt64
        let handle: SessionProcessManager.Handle?
        let processor: TranscriptEventProcessor?
    }

    init(
        processManager: SessionProcessManager,
        id: UUID = UUID(),
        activityRegistry: SessionActivityRegistry? = nil,
        historyLoader: @escaping HistoryLoader = SessionController.loadHistory(path:)
    ) {
        self.processManager = processManager
        self.id = id
        self.accountCoordinator = activityRegistry
        self.historyLoader = historyLoader
        activityRegistry?.register(self)
    }

    init(
        processManager: SessionProcessManager,
        previewItems: [TranscriptItem],
        runtimeState: SessionRuntimeState,
        title: String = "Transcript",
        modelName: String = "GPT-5.6",
        thinkingLevel: String = "High",
        headerMetadata: SessionHeaderMetadata = SessionHeaderMetadata(
            branch: "",
            repo: "",
            worktreePath: nil),
        id: UUID = UUID(),
        providerID: String? = nil,
        activityRegistry: SessionActivityRegistry? = nil,
        historyLoader: @escaping HistoryLoader = SessionController.loadHistory(path:)
    ) {
        self.processManager = processManager
        self.historyLoader = historyLoader
        self.items = previewItems
        self.runtimeState = runtimeState
        self.title = title
        self.modelName = modelName
        self.thinkingLevel = thinkingLevel
        self.headerMetadata = headerMetadata
        self.id = id
        self.providerID = providerID
        self.accountCoordinator = activityRegistry
        activityRegistry?.register(self)
    }

    var currentProviderAccountRef: String? {
        providerID.flatMap { activeProviderAccounts[$0] }
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
        let priorSessionPath = stopAndDetachCurrentSession()
        let openingGeneration = pipelineGeneration
        let pendingOpeningCloseTask = openingCloseTask
        if let priorSessionPath {
            await processManager.close(sessionPath: priorSessionPath)
            guard pipelineGeneration == openingGeneration else { return }
        }
        await pendingOpeningCloseTask?.value
        guard pipelineGeneration == openingGeneration else { return }
        let openingContext = PipelineContext(
            generation: openingGeneration,
            handle: nil,
            processor: nil)
        title = metadata.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session"
        let projectURL = URL(filePath: metadata.cwd, directoryHint: .isDirectory)
        self.projectURL = projectURL
        fallbackThreadStartDate = metadata.created
        let headerMetadata = await SessionHeaderMetadata.resolve(projectURL: projectURL)
        guard pipelineGeneration == openingGeneration else { return }
        self.headerMetadata = headerMetadata
        runtimeState = .loading
        reportActivity()

        let sessionPath = metadata.path
        let cwd = metadata.cwd
        let (openingToken, openTask) = beginOpening { [processManager] in
            try await processManager.open(sessionPath: sessionPath, cwd: cwd)
        }
        do {
            let handle = try await openTask.value
            clearOpeningTask(token: openingToken)
            guard pipelineGeneration == openingGeneration else {
                return
            }
            await finishOpening(handle, failureFunction: "openExisting")
        } catch {
            clearOpeningTask(token: openingToken)
            fail(error, function: "openExisting", context: openingContext)
        }
    }

    enum ComposerFastModeApplyOutcome: Sendable {
        case notRequested
        case applied
        case unsupported
        case failed
    }

    @discardableResult
    func openNew(
        projectURL: URL,
        selection: ComposerSpawnSelection? = nil
    ) async -> ComposerFastModeApplyOutcome {
        let failureOutcome: ComposerFastModeApplyOutcome = selection?.fastModeEnabled == true
            ? .failed
            : .notRequested
        let priorSessionPath = stopAndDetachCurrentSession()
        let openingGeneration = pipelineGeneration
        let pendingOpeningCloseTask = openingCloseTask
        if let priorSessionPath {
            await processManager.close(sessionPath: priorSessionPath)
            guard pipelineGeneration == openingGeneration else { return failureOutcome }
        }
        await pendingOpeningCloseTask?.value
        guard pipelineGeneration == openingGeneration else { return failureOutcome }
        let openingContext = PipelineContext(
            generation: openingGeneration,
            handle: nil,
            processor: nil)
        self.projectURL = projectURL
        fallbackThreadStartDate = Date()
        title = "New session"
        let headerMetadata = await SessionHeaderMetadata.resolve(projectURL: projectURL)
        guard pipelineGeneration == openingGeneration else { return failureOutcome }
        self.headerMetadata = headerMetadata
        runtimeState = .loading
        reportActivity()

        let projectPath = projectURL.path
        let provider = selection?.provider
        let model = selection?.modelID
        let thinking = selection?.thinking
        let (openingToken, openTask) = beginOpening { [processManager] in
            try await processManager.openNew(
                projectDirectory: projectPath,
                provider: provider,
                model: model,
                thinking: thinking)
        }
        do {
            let handle = try await openTask.value
            clearOpeningTask(token: openingToken)
            guard pipelineGeneration == openingGeneration else {
                return failureOutcome
            }
            await finishOpening(handle, failureFunction: "openNew")
            guard self.handle?.client === handle.client, isComposerAvailable else {
                return failureOutcome
            }
            guard selection?.fastModeEnabled == true else { return .notRequested }
            do {
                let supported = try await setFastMode(true)
                return supported ? .applied : .unsupported
            } catch {
                return .failed
            }
        } catch {
            clearOpeningTask(token: openingToken)
            fail(error, function: "openNew", context: openingContext)
            return failureOutcome
        }
    }

    func bindComposerControls(_ controls: ComposerControlsModel?) {
        attachedComposerControls = controls
        controls?.applyLiveSelection(liveComposerSelection)
    }

    func setModel(provider: String, modelID: String) async throws {
        guard let handle else { throw RpcClientError.notStarted }
        let context = currentPipelineContext()
        let response = try await handle.client.send(.setModel(provider: provider, modelId: modelID))
        guard isCurrent(context) else { return }
        if let data = response.data {
            applyModelPayload(data)
            publishLiveComposerSelection()
        } else {
            await refreshState()
        }
    }

    func setThinkingLevel(_ level: String) async throws {
        guard let handle else { throw RpcClientError.notStarted }
        let context = currentPipelineContext()
        _ = try await handle.client.send(.setThinkingLevel(level))
        guard isCurrent(context) else { return }
        thinkingLevel = level.capitalized
        liveComposerSelection.thinkingLevel = level
        publishLiveComposerSelection()
    }

    func setProviderAccount(
        providerID: String,
        accountRef: String
    ) async throws -> SetSessionProviderAccountResult {
        guard let handle else { throw RpcClientError.notStarted }
        let context = currentPipelineContext()
        let response = try await handle.client.send(.setSessionProviderAccount(
            providerID: providerID,
            accountRef: accountRef))
        guard isCurrent(context) else { throw RpcClientError.notStarted }
        let result = try response.setSessionProviderAccountResult()
        handleProviderAccountChange(ProviderAccountChangedEvent(
            providerID: result.account.providerID,
            accountRef: result.account.accountRef,
            reason: .manual,
            sequence: result.sequence))
        return result
    }

    /// Returns `false` only when Fast mode is unsupported (`active == false`).
    /// Transport / OMP command failures throw.
    func setFastMode(_ enabled: Bool) async throws -> Bool {
        guard let handle else { throw RpcClientError.notStarted }
        let context = currentPipelineContext()
        let response = try await handle.client.send(.setFastMode(enabled: enabled))
        guard isCurrent(context) else { return false }
        if response.data?["active"]?.boolValue == false {
            liveComposerSelection.fastModeEnabled = false
            publishLiveComposerSelection()
            return false
        }
        liveComposerSelection.fastModeEnabled = enabled
        publishLiveComposerSelection()
        return true
    }

    func sendPrompt() async {
        guard let handle,
              isComposerAvailable,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        guard accountCoordinator?.beginManagedTurn(sessionID: id) != false else { return }
        defer { accountCoordinator?.endManagedTurn(sessionID: id) }

        let behavior: StreamingBehavior?
        if runtimeState == .streaming {
            guard let streamingBehavior else { return }
            behavior = streamingBehavior
        } else {
            behavior = nil
        }

        let message = draft
        let context = currentPipelineContext()
        do {
            _ = try await handle.client.send(.prompt(
                message: message,
                streamingBehavior: behavior))
            guard isCurrent(context) else { return }
            draft = ""
            runtimeState = .streaming
            reportActivity()
            await context.processor?.setRuntimeState(.streaming)
        } catch {
            fail(error, function: "sendPrompt", context: context)
        }
    }

    func abort() async {
        guard let handle, runtimeState == .streaming else { return }
        let context = currentPipelineContext()
        do {
            _ = try await handle.client.send(.abort())
        } catch {
            fail(error, function: "abort", context: context)
        }
    }

    func restart() async {
        guard let projectURL, let sessionPath else { return }
        stopEventPipeline()
        let openingGeneration = pipelineGeneration
        let pendingOpeningCloseTask = openingCloseTask
        await processManager.close(sessionPath: sessionPath)
        guard pipelineGeneration == openingGeneration else { return }
        await pendingOpeningCloseTask?.value
        guard pipelineGeneration == openingGeneration else { return }
        let openingContext = PipelineContext(
            generation: openingGeneration,
            handle: nil,
            processor: nil)
        runtimeState = .loading
        reportActivity()
        isRecoveryPresented = false
        let projectPath = projectURL.path
        let (openingToken, openTask) = beginOpening { [processManager] in
            try await processManager.open(sessionPath: sessionPath, cwd: projectPath)
        }
        do {
            let handle = try await openTask.value
            clearOpeningTask(token: openingToken)
            guard pipelineGeneration == openingGeneration else {
                return
            }
            await finishOpening(handle, failureFunction: "restart")
        } catch {
            clearOpeningTask(token: openingToken)
            fail(error, function: "restart", context: openingContext)
        }
    }

    func selectStreamingBehavior(_ behavior: StreamingBehavior) {
        streamingBehavior = behavior
    }

    func respond(to state: ExtensionUIState, with response: ExtensionUIResponse) async {
        let context = currentPipelineContext()
        guard context.handle != nil else { return }
        await respond(to: state, with: response, context: context)
    }

    private func respond(
        to state: ExtensionUIState,
        with response: ExtensionUIResponse,
        context: PipelineContext
    ) async {
        guard let handle = context.handle, isCurrent(context) else { return }
        do {
            try await handle.client.sendRaw(.extensionUIResponse(id: state.id, body: response.body))
            guard isCurrent(context) else { return }
            await removeExtensionRequest(id: state.id)
        } catch {
            fail(error, function: "respondToExtensionUI", context: context)
        }
    }

    func openURL(_ url: URL, requestID: String) {
        let context = currentPipelineContext()
        NSWorkspace.shared.open(url)
        Task { [weak self] in
            await self?.removeExtensionRequest(id: requestID, context: context)
        }
    }

    func copyURL(_ url: URL, requestID: String) {
        let context = currentPipelineContext()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        Task { [weak self] in
            await self?.removeExtensionRequest(id: requestID, context: context)
        }
    }

    func handleUnexpectedExit(code: Int32?, stderrTail: String) {
        stopEventPipeline()
        runtimeState = .stopped(code: code, stderrTail: stderrTail)
        isRecoveryPresented = true
        logText = stderrTail.isEmpty ? "OMP exited without stderr output." : stderrTail
        reportActivity()
    }

    func stopActivityTracking() {
        stopEventPipeline()
        accountCoordinator?.unregister(sessionID: id)
    }

    func close() async {
        await dispose()?.value
    }

    @discardableResult
    func dispose() -> Task<Void, Never>? {
        let sessionPath = stopAndDetachCurrentSession()
        let openingCloseTask = openingCloseTask
        self.sessionPath = nil
        items = []
        runtimeState = .stopped(code: nil, stderrTail: "")
        accountCoordinator?.unregister(sessionID: id)
        guard let sessionPath else {
            return openingCloseTask
        }
        return Task { [processManager] in
            await openingCloseTask?.value
            await processManager.close(sessionPath: sessionPath)
        }
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

    private func finishOpening(
        _ handle: SessionProcessManager.Handle,
        failureFunction: String
    ) async {
        stopEventPipeline()
        providerAccountSequence = 0
        self.handle = handle
        sessionPath = handle.sessionPath
        let openingContext = currentPipelineContext()

        do {
            let state = try await handle.client.send(.getState())
            guard isCurrent(openingContext) else { return }
            applyState(state.data)
            var loadedHistory: TranscriptHistory?
            var didHistoryLoadFail = false
            if let sessionPath {
                do {
                    loadedHistory = try await historyLoader(sessionPath)
                } catch {
                    didHistoryLoadFail = true
                }
            }
            guard isCurrent(openingContext) else { return }
            let initialContent: TranscriptInitialContent
            if let history = loadedHistory {
                initialContent = .history(history)
            } else {
                initialContent = .messages(try await loadMessages(client: handle.client))
            }
            guard isCurrent(openingContext) else { return }
            let processor = TranscriptEventProcessor()
            self.processor = processor
            let processorContext = currentPipelineContext()
            let initialSnapshot = await processor.load(
                initialContent,
                threadStartDate: fallbackThreadStartDate,
                hasReconciliationWarning: didHistoryLoadFail,
                runtimeState: runtimeState)
            install(snapshot: initialSnapshot)
            _ = try? await handle.client.send(.setSubagentSubscription(level: .progress))
            guard isCurrent(processorContext) else { return }
            startEventPipeline(processor: processor, client: handle.client)
        } catch {
            fail(error, function: failureFunction, context: openingContext)
        }
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

    private func startEventPipeline(processor: TranscriptEventProcessor, client: RpcClient) {
        guard let context = currentPipelineContext(for: processor) else { return }
        eventTask = Task { [weak self, processor, events = client.events] in
            for await frame in events {
                guard !Task.isCancelled else { break }
                await self?.consume(frame, processor: processor, context: context)
            }
            await processor.stop()
        }
        snapshotTask = Task { [weak self, processor] in
            for await snapshot in processor.snapshots {
                guard !Task.isCancelled else { return }
                self?.install(snapshot: snapshot)
            }
        }
        controlTask = Task { [weak self, processor] in
            for await frame in processor.controlEvents {
                guard !Task.isCancelled else { return }
                await self?.handleControl(frame, processor: processor)
            }
        }
    }

    private func consume(
        _ frame: RpcFrame,
        processor: TranscriptEventProcessor,
        context: PipelineContext
    ) async {
        guard isCurrent(context) else { return }
        await processor.consume(frame)
        guard isCurrent(context) else { return }
        if case .providerAccountChanged(let event) = frame {
            handleProviderAccountChange(event)
        }
    }

    private func stopEventPipeline() {
        let detachedProcessor = processor
        let openingTaskToClose = openingTask
        let previousOpeningCloseTask = openingCloseTask
        eventTask?.cancel()
        snapshotTask?.cancel()
        controlTask?.cancel()
        reconciliationTask?.cancel()
        openingTask = nil
        openingTaskToken = nil
        eventTask = nil
        snapshotTask = nil
        controlTask = nil
        reconciliationTask = nil
        if previousOpeningCloseTask != nil || openingTaskToClose != nil {
            openingCloseTask = Task { [processManager] in
                await previousOpeningCloseTask?.value
                guard let openingTaskToClose else { return }
                do {
                    let handle = try await openingTaskToClose.value
                    await processManager.close(sessionPath: handle.sessionPath)
                } catch {
                    return
                }
            }
        } else {
            openingCloseTask = nil
        }
        reconciliationGeneration &+= 1
        pipelineGeneration &+= 1
        extensionTimeoutTasks.values.forEach { $0.cancel() }
        extensionTimeoutTasks.removeAll()
        extensionRouter = ExtensionUIRouter()
        extensionSheetRequest = nil
        handle = nil
        processor = nil
        installedSnapshotRevision = 0
        if let detachedProcessor {
            Task.detached { await detachedProcessor.stop() }
        }
    }

    private func stopAndDetachCurrentSession() -> String? {
        let sessionPath = handle?.sessionPath ?? sessionPath
        stopEventPipeline()
        return sessionPath
    }

    private func currentPipelineContext() -> PipelineContext {
        PipelineContext(
            generation: pipelineGeneration,
            handle: handle,
            processor: processor)
    }

    private func beginOpening(
        _ operation: @escaping @Sendable () async throws -> SessionProcessManager.Handle
    ) -> (UInt64, Task<SessionProcessManager.Handle, any Error>) {
        nextOpeningTaskToken &+= 1
        let token = nextOpeningTaskToken
        let task = Task { try await operation() }
        openingTask = task
        openingTaskToken = token
        return (token, task)
    }

    private func clearOpeningTask(token: UInt64) {
        guard openingTaskToken == token else { return }
        openingTask = nil
        openingTaskToken = nil
    }

    private func isCurrent(_ context: PipelineContext) -> Bool {
        guard context.generation == pipelineGeneration else { return false }
        guard handle?.client === context.handle?.client else { return false }
        return processor?.id == context.processor?.id
    }

    private func currentPipelineContext(for processor: TranscriptEventProcessor) -> PipelineContext? {
        guard self.processor?.id == processor.id else { return nil }
        return currentPipelineContext()
    }

    private func handleControl(_ frame: RpcFrame, processor: TranscriptEventProcessor) async {
        guard let context = currentPipelineContext(for: processor) else { return }
        let snapshot = await processor.currentSnapshot()
        guard isCurrent(context),
              Self.accepts(
                snapshot: snapshot,
                activeProcessorID: self.processor?.id)
        else { return }

        if case .extensionUIRequest(let request) = frame {
            await consumeExtensionUI(request, processor: processor, context: context)
            return
        }

        guard isCurrent(context) else { return }
        applyEventMetadata(frame)
        if isReconciliationBoundary(frame) {
            let snapshot = await processor.currentSnapshot()
            guard isCurrent(context) else { return }
            install(snapshot: snapshot)
            reconcileAfterBoundary(frame, processor: processor, context: context)
        }
    }

    private func reconcileAfterBoundary(
        _ frame: RpcFrame,
        processor: TranscriptEventProcessor,
        context: PipelineContext
    ) {
        guard isCurrent(context), isReconciliationBoundary(frame), let sessionPath else { return }

        reconciliationGeneration &+= 1
        let generation = reconciliationGeneration
        let processorID = processor.id
        reconciliationTask?.cancel()
        reconciliationTask = Task { [weak self, historyLoader, processor, processorID, generation] in
            guard self != nil, !Task.isCancelled else { return }
            do {
                guard let history = try await historyLoader(sessionPath),
                      !Task.isCancelled,
                      self?.canApplyReconciliation(
                        processorID: processorID,
                        generation: generation) == true
                else { return }
                await processor.reconcile(history, hasWarning: false, generation: generation)
            } catch {
                guard !Task.isCancelled,
                      self?.canApplyReconciliation(
                        processorID: processorID,
                        generation: generation) == true
                else { return }
                await processor.reconcile(
                    TranscriptHistory(items: await processor.currentSnapshot().items),
                    hasWarning: true,
                    generation: generation)
            }
        }
    }

    private func canApplyReconciliation(
        processorID: UUID,
        generation: UInt64
    ) -> Bool {
        processor?.id == processorID && reconciliationGeneration == generation
    }

#if DEBUG
    func testingCapturedAccountEventConsumer(
        _ frame: RpcFrame
    ) -> (@MainActor () async -> Void)? {
        guard let processor,
              let context = currentPipelineContext(for: processor)
        else { return nil }
        return { [weak self, processor] in
            await self?.consume(frame, processor: processor, context: context)
        }
    }

    func testingCapturedExtensionRemoval(id: String) -> @MainActor () async -> Void {
        let context = currentPipelineContext()
        return { [weak self] in
            await self?.removeExtensionRequest(id: id, context: context)
        }
    }

    func testingCapturedBoundaryReconciler(frame: RpcFrame) -> @MainActor () -> Void {
        let context = currentPipelineContext()
        let capturedProcessor = processor
        return { [weak self] in
            guard let self, let capturedProcessor else { return }
            self.reconcileAfterBoundary(
                frame,
                processor: capturedProcessor,
                context: context)
        }
    }
#endif

    private func isReconciliationBoundary(_ frame: RpcFrame) -> Bool {
        guard case .event(let type, let payload) = frame else { return false }
        return switch type {
        case "message_end", "turn_end", "prompt_result":
            true
        case "agent_end":
            payload["isTerminal"]?.boolValue != false
        default:
            false
        }
    }

    private func applyState(_ data: JSONValue?) {
        guard let data else {
            runtimeState = .idle
            reportActivity()
            return
        }
        title = data["sessionName"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? title
        if let model = data["model"] {
            applyModelPayload(model)
        }
        if let thinking = data["thinkingLevel"]?.stringValue {
            thinkingLevel = thinking.capitalized
            liveComposerSelection.thinkingLevel = thinking
        }
        if let fastEnabled = data["fastModeEnabled"]?.boolValue
            ?? data["fastModeActive"]?.boolValue
        {
            liveComposerSelection.fastModeEnabled = fastEnabled
        }
        contextPercentage = Self.contextPercent(data["contextUsage"])
        queuedMessageCount = data["queuedMessageCount"]?.intValue ?? 0
        runtimeState = data["isStreaming"]?.boolValue == true ? .streaming : .idle
        activeProviderAccounts = Self.activeProviderAccountRefs(from: data)
        if let reportedPath = data["sessionFile"]?.stringValue {
            sessionPath = reportedPath
        }
        publishLiveComposerSelection()
        accountCoordinator?.register(self)
        reportActivity()
    }

    private func applyEventMetadata(_ frame: RpcFrame) {
        guard case .event(let type, let payload) = frame else { return }
        switch type {
        case "session_info_update":
            title = payload["title"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? title
        case "config_update":
            if let model = payload["model"] {
                applyModelPayload(model)
            }
            if let thinking = payload["thinkingLevel"]?.stringValue {
                thinkingLevel = thinking.capitalized
                liveComposerSelection.thinkingLevel = thinking
            }
            publishLiveComposerSelection()
            reportActivity()
        case "thinking_level_changed":
            if let thinking = payload["thinkingLevel"]?.stringValue {
                thinkingLevel = thinking.capitalized
                liveComposerSelection.thinkingLevel = thinking
                publishLiveComposerSelection()
            }
        case "model_changed":
            Task { [weak self] in await self?.refreshState() }
        default:
            break
        }
    }

    private func refreshState() async {
        guard let handle else { return }
        let context = currentPipelineContext()
        do {
            let data = try await handle.client.send(.getState()).data
            guard isCurrent(context) else { return }
            applyState(data)
            await context.processor?.setRuntimeState(runtimeState)
        } catch {
            fail(error, function: "refreshState", context: context)
        }
    }

    private func applyModelPayload(_ value: JSONValue) {
        if let label = Self.modelLabel(value) {
            modelName = label
        }
        liveComposerSelection.provider = value["provider"]?.stringValue
            ?? liveComposerSelection.provider
        liveComposerSelection.modelID = value["id"]?.stringValue
            ?? value["modelId"]?.stringValue
            ?? liveComposerSelection.modelID
        providerID = Self.providerID(from: value)
        reportActivity()
    }

    func handleProviderAccountChange(_ event: ProviderAccountChangedEvent) {
        guard event.sequence > providerAccountSequence else { return }
        providerAccountSequence = event.sequence
        activeProviderAccounts[event.providerID] = event.accountRef
        accountCoordinator?.session(id, didChangeAccount: event)
    }

    private func publishLiveComposerSelection() {
        attachedComposerControls?.applyLiveSelection(liveComposerSelection)
    }

    private func consumeExtensionUI(
        _ request: ExtensionUIRequest,
        processor: TranscriptEventProcessor,
        context: PipelineContext
    ) async {
        guard isCurrent(context) else { return }
        guard let state = ExtensionUIRouter.parse(request) else { return }
        extensionRouter.consume(request)

        switch state {
        case .confirm, .select:
            await processor.upsertExtensionUI(state)
            guard isCurrent(context) else { return }
            scheduleTimeout(for: state, context: context)
        case .input, .editor:
            extensionSheetRequest = state
            scheduleTimeout(for: state, context: context)
        case .cancel(_, let targetID):
            await removeExtensionRequest(id: targetID, context: context)
        case .notification(_, let message, let level):
            await processor.appendNotice(level: level, message: message)
            guard isCurrent(context) else { return }
            postNotification(message: message)
        case .title(_, let updatedTitle):
            guard isCurrent(context) else { return }
            title = updatedTitle
        case .setEditorText(_, let text):
            guard isCurrent(context) else { return }
            draft = text
            extensionRouter.clearEditorText()
        case .openURL:
            await processor.upsertExtensionUI(state)
            guard isCurrent(context) else { return }
        case .status, .widget:
            break
        }
    }

    private func scheduleTimeout(for state: ExtensionUIState, context: PipelineContext) {
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
        guard isCurrent(context) else { return }
        extensionTimeoutTasks[state.id]?.cancel()
        extensionTimeoutTasks[state.id] = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(timeout)) }
            catch { return }
            guard let self else { return }
            await self.respond(to: state, with: .cancelled(timedOut: true), context: context)
        }
    }

    private func removeExtensionRequest(id: String) async {
        let context = currentPipelineContext()
        await removeExtensionRequest(id: id, context: context)
    }

    private func removeExtensionRequest(id: String, context: PipelineContext) async {
        guard isCurrent(context) else { return }
        extensionTimeoutTasks.removeValue(forKey: id)?.cancel()
        extensionRouter.removeRequest(id: id)
        await context.processor?.removeExtensionUI(id: id)
        guard isCurrent(context) else { return }
        if extensionSheetRequest?.id == id { extensionSheetRequest = nil }
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

    private func fail(
        _ error: any Error,
        function: String,
        context: PipelineContext
    ) {
        guard isCurrent(context) else { return }
        runtimeState = .failed("[Session:\(function)] Session command failed: \(error)")
        reportActivity()
        let state = runtimeState
        let failedProcessor = context.processor
        Task { await failedProcessor?.setRuntimeState(state) }
    }

    nonisolated static func accepts(
        snapshot: TranscriptSnapshot,
        activeProcessorID: UUID?
    ) -> Bool {
        snapshot.processorID == activeProcessorID
    }

    private func install(snapshot: TranscriptSnapshot) {
        guard Self.accepts(snapshot: snapshot, activeProcessorID: processor?.id),
              snapshot.revision > installedSnapshotRevision
        else { return }
        installedSnapshotRevision = snapshot.revision
        items = snapshot.items
        runtimeState = snapshot.runtimeState
        os_signpost(
            .event,
            log: Self.transcriptLog,
            name: "TranscriptSnapshotInstalled",
            "revision %{public}llu",
            snapshot.revision)
        reportActivity()
    }

    private func reportActivity() {
        accountCoordinator?.update(
            sessionID: id,
            providerID: providerID,
            isGenerating: runtimeState == .streaming)
        if runtimeState == .idle {
            Task { [weak accountCoordinator] in
                await accountCoordinator?.sessionDidBecomeIdle(id)
            }
        }
    }

    private static func modelLabel(_ value: JSONValue?) -> String? {
        value?.stringValue
            ?? value?["id"]?.stringValue
            ?? value?["modelId"]?.stringValue
            ?? value?["name"]?.stringValue
    }

    static func providerID(from value: JSONValue?) -> String? {
        guard let providerID = value?["provider"]?.stringValue,
              !providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return providerID
    }

    static func activeProviderAccountRefs(from value: JSONValue?) -> [String: String] {
        guard let accounts = value?["activeProviderAccounts"]?.objectValue else { return [:] }
        return accounts.reduce(into: [:]) { refs, entry in
            if let accountRef = entry.value.stringValue {
                refs[entry.key] = accountRef
            }
        }
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

    private static func loadHistory(path: String) async throws -> TranscriptHistory? {
        try await SessionTimelineLoader().load(path: path)
    }
}
