import Foundation
import OmpKit

actor TranscriptEventProcessor {
    private struct PendingMessageUpdate {
        let messageID: String
        let frame: RpcFrame
    }

    nonisolated let id: UUID
    nonisolated let snapshots: AsyncStream<TranscriptSnapshot>
    nonisolated let controlEvents: AsyncStream<RpcFrame>

    private let publicationInterval: Duration
    private let snapshotContinuation: AsyncStream<TranscriptSnapshot>.Continuation
    private let controlContinuation: AsyncStream<RpcFrame>.Continuation

    private var reducer = TranscriptReducer()
    private var revision: UInt64 = 0
    private var isDirty = false
    private var timerTask: Task<Void, Never>?
    private var timerGeneration: UInt64 = 0
    private var reconciliationGeneration: UInt64 = 0
    private var isStopped = false
    private var pendingMessageUpdate: PendingMessageUpdate?
    #if DEBUG
    private var messageUpdateReductionCount = 0
    #endif

    init(
        id: UUID = UUID(),
        publicationInterval: Duration = .milliseconds(50)
    ) {
        self.id = id
        self.publicationInterval = publicationInterval

        var snapshotContinuation: AsyncStream<TranscriptSnapshot>.Continuation!
        snapshots = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            snapshotContinuation = continuation
        }
        self.snapshotContinuation = snapshotContinuation

        var controlContinuation: AsyncStream<RpcFrame>.Continuation!
        controlEvents = AsyncStream { continuation in
            controlContinuation = continuation
        }
        self.controlContinuation = controlContinuation
    }

    func load(
        _ content: TranscriptInitialContent,
        threadStartDate: Date?,
        hasReconciliationWarning: Bool,
        runtimeState: SessionRuntimeState
    ) -> TranscriptSnapshot {
        guard !isStopped else { return currentSnapshot() }
        cancelScheduledPublication()
        pendingMessageUpdate = nil
        isDirty = false

        switch content {
        case .history(let history):
            reducer.load(history: history)
        case .messages(let messages):
            reducer.load(messages: messages)
            reducer.ensureThreadStart(date: threadStartDate)
        }
        reducer.setReconciliationWarning(isPresented: hasReconciliationWarning)
        reducer.runtimeState = runtimeState
        revision = 1
        return currentSnapshot()
    }

    func run(events: AsyncStream<RpcFrame>) async {
        for await frame in events {
            if isStopped { break }
            consume(frame)
        }
        stop()
    }

    func consume(_ frame: RpcFrame) {
        guard !isStopped else { return }
        switch frame {
        case .extensionUIRequest, .providerAccountChanged:
            controlContinuation.yield(frame)
            return
        default:
            break
        }

        if let messageID = messageUpdateIdentity(frame) {
            enqueueMessageUpdate(frame, messageID: messageID)
            return
        }

        let mutation = combinedMutation(
            drainPendingMessageUpdate(),
            reduce(frame))
        publish(mutation)

        if shouldForwardControl(frame) {
            if shouldFlushBeforeControl(frame) {
                _ = flush()
            }
            controlContinuation.yield(frame)
        }
    }

    func setRuntimeState(_ state: SessionRuntimeState) {
        guard !isStopped, reducer.runtimeState != state else { return }
        reducer.runtimeState = state
        publishNow()
    }

    func upsertExtensionUI(_ state: ExtensionUIState) {
        guard !isStopped else { return }
        publish(reducer.upsertExtensionUI(state))
    }

    func removeExtensionUI(id: String) {
        guard !isStopped else { return }
        publish(reducer.removeExtensionUI(id: id))
    }

    func appendNotice(level: String, message: String) {
        guard !isStopped else { return }
        publish(reducer.appendNotice(level: level, message: message))
    }

    func reconcile(
        _ history: TranscriptHistory,
        hasWarning: Bool,
        generation: UInt64 = 0
    ) {
        guard !isStopped else { return }
        guard generation >= reconciliationGeneration else { return }
        reconciliationGeneration = generation
        let pending = drainPendingMessageUpdate()
        let reconciliation = reducer.reconcile(history: history)
        let warning = reducer.setReconciliationWarning(isPresented: hasWarning)
        publish(combinedMutation(
            pending,
            combinedMutation(reconciliation, warning)))
    }

    func currentSnapshot() -> TranscriptSnapshot {
        markDirty(drainPendingMessageUpdate())
        return makeSnapshot()
    }

    func flush() -> TranscriptSnapshot? {
        guard !isStopped else { return nil }
        markDirty(drainPendingMessageUpdate())
        guard isDirty else { return nil }
        return publishNow()
    }

    func stop() {
        guard !isStopped else { return }
        _ = flush()
        isStopped = true
        cancelScheduledPublication()
        isDirty = false
        snapshotContinuation.finish()
        controlContinuation.finish()
    }

    private func makeSnapshot() -> TranscriptSnapshot {
        TranscriptSnapshot(
            processorID: id,
            revision: revision,
            items: reducer.items,
            runtimeState: reducer.runtimeState)
    }

    private func messageUpdateIdentity(_ frame: RpcFrame) -> String? {
        guard case .event("message_update", let payload) = frame,
              let messageID = payload["message"]?["id"]?.stringValue,
              !messageID.isEmpty
        else { return nil }
        return messageID
    }

    private func enqueueMessageUpdate(_ frame: RpcFrame, messageID: String) {
        if let pendingMessageUpdate,
           pendingMessageUpdate.messageID != messageID {
            publish(drainPendingMessageUpdate())
        }
        pendingMessageUpdate = PendingMessageUpdate(
            messageID: messageID,
            frame: frame)
        schedulePublication()
    }

    private func drainPendingMessageUpdate() -> TranscriptMutation {
        guard let pendingMessageUpdate else { return .none }
        self.pendingMessageUpdate = nil
        return reduce(pendingMessageUpdate.frame)
    }

    private func reduce(_ frame: RpcFrame) -> TranscriptMutation {
        #if DEBUG
        if case .event("message_update", _) = frame {
            messageUpdateReductionCount += 1
        }
        #endif
        return reducer.consume(frame)
    }

    private func combinedMutation(
        _ first: TranscriptMutation,
        _ second: TranscriptMutation
    ) -> TranscriptMutation {
        if first == .immediate || second == .immediate { return .immediate }
        if first == .coalesced || second == .coalesced { return .coalesced }
        return .none
    }

    private func markDirty(_ mutation: TranscriptMutation) {
        guard mutation != .none else { return }
        isDirty = true
        schedulePublication()
    }

    private func publish(_ mutation: TranscriptMutation) {
        switch mutation {
        case .none:
            break
        case .coalesced:
            isDirty = true
            schedulePublication()
        case .immediate:
            publishNow()
        }
    }

    @discardableResult
    private func publishNow() -> TranscriptSnapshot {
        _ = drainPendingMessageUpdate()
        cancelScheduledPublication()
        isDirty = false
        revision += 1
        let snapshot = makeSnapshot()
        snapshotContinuation.yield(snapshot)
        return snapshot
    }

    private func schedulePublication() {
        guard timerTask == nil else { return }
        timerGeneration &+= 1
        let token = timerGeneration
        timerTask = Task { [publicationInterval] in
            do {
                try await Task.sleep(for: publicationInterval)
            } catch {
                return
            }
            publishScheduled(token: token)
        }
    }

    private func publishScheduled(token: UInt64) {
        guard token == timerGeneration else { return }
        timerTask = nil
        _ = flush()
    }

    private func cancelScheduledPublication() {
        timerGeneration &+= 1
        timerTask?.cancel()
        timerTask = nil
    }

    #if DEBUG
    func testingTimerGeneration() -> UInt64 {
        timerGeneration
    }

    func testingPublishScheduled(token: UInt64) {
        publishScheduled(token: token)
    }

    func testingMessageUpdateReductionCount() -> Int {
        messageUpdateReductionCount
    }
    #endif

    private func isControlFrame(_ frame: RpcFrame) -> Bool {
        guard case .event(let type, let payload) = frame else { return false }
        switch type {
        case "session_info_update",
             "config_update",
             "thinking_level_changed",
             "model_changed",
             "available_commands_update",
             "agent_start",
             "turn_start",
             "message_end",
             "turn_end",
             "prompt_result":
            return true
        case "agent_end":
            return payload["isTerminal"]?.boolValue != false
        default:
            return false
        }
    }

    private func shouldForwardControl(_ frame: RpcFrame) -> Bool {
        guard isControlFrame(frame) else { return false }
        if case .event("message_end", let payload) = frame {
            guard let message = payload["message"] else { return false }
            if message["role"]?.stringValue == "toolResult",
               message["toolCallId"]?.stringValue == nil {
                return false
            }
            return true
        }
        return true
    }

    private func shouldFlushBeforeControl(_ frame: RpcFrame) -> Bool {
        guard isDirty, case .event(let type, let payload) = frame else { return false }
        switch type {
        case "message_end", "turn_end", "prompt_result":
            return true
        case "agent_end":
            return payload["isTerminal"]?.boolValue != false
        default:
            return false
        }
    }
}
