import Foundation
import Observation
import OmpKit

enum ProviderAccountScope: Sendable {
    case thisSession
    case allCurrentSessions
    case allNewSessions
}

struct ProviderAccountKey: Hashable, Sendable {
    let providerID: String
    let accountRef: String
}

enum ProviderAccountRemovalError: Error, Equatable {
    case alreadyInProgress
    case reassignmentFailed(Int)
}

@MainActor
protocol ProviderAccountSession: AnyObject {
    var id: UUID { get }
    var providerID: String? { get }
    var runtimeState: SessionRuntimeState { get }
    var currentProviderAccountRef: String? { get }
    var providerAccountSequence: Int { get }

    func setProviderAccount(
        providerID: String,
        accountRef: String
    ) async throws -> SetSessionProviderAccountResult
}

@MainActor
@Observable
final class ProviderAccountCoordinator {
    private struct DesiredRoute: Equatable {
        let providerID: String
        let accountRef: String
        let operationID: UInt64
    }

    private enum RoutingOutcome: Equatable {
        case applied
        case queued
        case failed
        case superseded
    }

    private struct RoutingTail {
        let route: DesiredRoute
        let task: Task<RoutingOutcome, Never>
    }

    private struct RoutingCompletion {
        let operationID: UInt64
        let outcome: RoutingOutcome
    }

    private struct FailureRecord {
        let operationID: UInt64
        var count: Int
    }

    private struct SessionState {
        var providerID: String?
        var accountRef: String?
        var sequence: Int
        var isGenerating: Bool
    }

    private(set) var managedSessions: [UUID: any ProviderAccountSession] = [:]
    private(set) var activeAccountRefs: [UUID: String] = [:]
    private(set) var generatingCounts: [ProviderAccountKey: Int] = [:]
    private(set) var sessionCounts: [ProviderAccountKey: Int] = [:]
    private(set) var activeCounts: [String: Int] = [:]
    private(set) var pendingRemovalAccounts: Set<ProviderAccountKey> = []
    private(set) var failureSummary: String?

    @ObservationIgnored private let primaryStore: ProviderPrimaryPreferenceStore
    @ObservationIgnored private var sessionStates: [UUID: SessionState] = [:]
    @ObservationIgnored private var desiredRoutes: [UUID: DesiredRoute] = [:]
    @ObservationIgnored private var pendingRoutes: [UUID: DesiredRoute] = [:]
    @ObservationIgnored private var routingTails: [UUID: RoutingTail] = [:]
    @ObservationIgnored private var routingCompletions: [UUID: RoutingCompletion] = [:]
    @ObservationIgnored private var stateChangeWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var failureRecord: FailureRecord?
    @ObservationIgnored private var nextOperationID: UInt64 = 0

    init(primaryStore: ProviderPrimaryPreferenceStore = ProviderPrimaryPreferenceStore()) {
        self.primaryStore = primaryStore
    }

    func register(_ session: any ProviderAccountSession) {
        managedSessions[session.id] = session
        sessionStates[session.id] = SessionState(
            providerID: session.providerID,
            accountRef: session.currentProviderAccountRef,
            sequence: session.providerAccountSequence,
            isGenerating: session.runtimeState == .streaming)
        publishSessionState()
    }

    func unregister(sessionID: UUID) {
        managedSessions.removeValue(forKey: sessionID)
        sessionStates.removeValue(forKey: sessionID)
        desiredRoutes.removeValue(forKey: sessionID)
        pendingRoutes.removeValue(forKey: sessionID)
        routingTails.removeValue(forKey: sessionID)?.task.cancel()
        routingCompletions.removeValue(forKey: sessionID)
        publishSessionState()
    }

    func update(sessionID: UUID, providerID: String?, isGenerating: Bool) {
        var state = sessionStates[sessionID] ?? SessionState(
            providerID: providerID,
            accountRef: managedSessions[sessionID]?.currentProviderAccountRef,
            sequence: managedSessions[sessionID]?.providerAccountSequence ?? 0,
            isGenerating: isGenerating)
        state.providerID = providerID
        if let session = managedSessions[sessionID] {
            state.accountRef = session.currentProviderAccountRef
            state.sequence = session.providerAccountSequence
        }
        state.isGenerating = isGenerating
        sessionStates[sessionID] = state
        publishSessionState()
    }

    func remove(sessionID: UUID) {
        unregister(sessionID: sessionID)
    }

    func primaryAccountRef(providerID: String) -> String? {
        primaryStore.primaryAccountRef(providerID: providerID)
    }

    func pendingAccountRef(sessionID: UUID) -> String? {
        pendingRoutes[sessionID]?.accountRef
    }

    func useAccount(
        _ accountRef: String,
        providerID: String,
        scope: ProviderAccountScope,
        openSessionID: UUID?
    ) async {
        guard !pendingRemovalAccounts.contains(ProviderAccountKey(
            providerID: providerID,
            accountRef: accountRef
        )) else {
            failureRecord = nil
            failureSummary = "Account is no longer available."
            return
        }
        nextOperationID &+= 1
        let operationID = nextOperationID
        failureRecord = FailureRecord(operationID: operationID, count: 0)
        failureSummary = nil
        if scope == .allNewSessions {
            primaryStore.setPrimaryAccountRef(accountRef, providerID: providerID)
            return
        }

        let targetIDs: [UUID]
        switch scope {
        case .thisSession:
            guard let openSessionID,
                  managedSessions[openSessionID]?.providerID == providerID
            else { return }
            targetIDs = [openSessionID]
        case .allCurrentSessions:
            targetIDs = managedSessions.values
                .filter { $0.providerID == providerID }
                .map(\.id)
        case .allNewSessions:
            targetIDs = []
        }

        let route = DesiredRoute(
            providerID: providerID,
            accountRef: accountRef,
            operationID: operationID)
        var tasks: [Task<RoutingOutcome, Never>] = []
        for sessionID in targetIDs {
            desiredRoutes[sessionID] = route
            guard let session = managedSessions[sessionID] else { continue }
            if session.runtimeState == .streaming {
                pendingRoutes[sessionID] = route
                continue
            }
            pendingRoutes.removeValue(forKey: sessionID)
            tasks.append(enqueue(route, sessionID: sessionID))
        }
        var failureCount = 0
        for task in tasks where await task.value == .failed {
            failureCount += 1
        }
        recordFailure(count: failureCount, operationID: operationID)
        notifyStateChange()
    }

    func sessionDidBecomeIdle(_ sessionID: UUID) async {
        guard let session = managedSessions[sessionID], session.runtimeState == .idle else { return }
        synchronizeState(from: session)
        publishSessionState()
        guard let route = pendingRoutes.removeValue(forKey: sessionID) else { return }
        let outcome = await enqueue(route, sessionID: sessionID).value
        if outcome == .failed {
            recordFailure(count: 1, operationID: route.operationID)
        }
    }

    func removeAccount(
        providerID: String,
        accountRef: String,
        accounts: [ProviderAccountSummary],
        performRemoval: @escaping @MainActor () async throws -> ProviderAccountRemovalResult
    ) async throws -> ProviderAccountRemovalResult {
        let key = ProviderAccountKey(providerID: providerID, accountRef: accountRef)
        guard pendingRemovalAccounts.insert(key).inserted else {
            throw ProviderAccountRemovalError.alreadyInProgress
        }
        notifyStateChange()
        defer {
            pendingRemovalAccounts.remove(key)
            notifyStateChange()
        }

        let remainingAccounts = accounts
            .enumerated()
            .filter { entry in
                let account = entry.element
                return account.providerID == providerID
                    && account.accountRef != accountRef
                    && !pendingRemovalAccounts.contains(ProviderAccountKey(
                        providerID: providerID,
                        accountRef: account.accountRef))
            }
            .sorted { lhs, rhs in
                if lhs.element.connectionOrder != rhs.element.connectionOrder {
                    return lhs.element.connectionOrder < rhs.element.connectionOrder
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        let replacement = primaryStore.repairPrimary(
            providerID: providerID,
            accounts: remainingAccounts)
        nextOperationID &+= 1
        let removalOperationID = nextOperationID
        var affectedSessionIDs: Set<UUID> = []
        var failedSessionIDs: Set<UUID> = []

        cancelRoutesTargeting(key)

        while true {
            synchronizeManagedSessionState()
            for session in managedSessions.values
            where session.providerID == providerID && session.currentProviderAccountRef == accountRef {
                affectedSessionIDs.insert(session.id)
            }

            let relevantTails = routingTails.filter { sessionID, tail in
                affectedSessionIDs.contains(sessionID)
                    || (tail.route.providerID == providerID && tail.route.accountRef == accountRef)
            }.map(\.value.task)
            if !relevantTails.isEmpty {
                for task in relevantTails {
                    _ = await task.value
                }
                continue
            }

            var routingTasks: [(UUID, Task<RoutingOutcome, Never>)] = []
            for sessionID in affectedSessionIDs {
                guard let session = managedSessions[sessionID],
                      session.providerID == providerID,
                      session.currentProviderAccountRef == accountRef
                else { continue }

                if routingCompletions[sessionID]?.operationID == removalOperationID,
                   routingCompletions[sessionID]?.outcome == .failed {
                    failedSessionIDs.insert(sessionID)
                    continue
                }
                guard let replacement else { continue }
                if let route = desiredRoutes[sessionID], route.accountRef != accountRef {
                    guard session.runtimeState != .streaming else { continue }
                    pendingRoutes.removeValue(forKey: sessionID)
                    routingTasks.append((sessionID, enqueue(route, sessionID: sessionID)))
                    continue
                }

                let route = DesiredRoute(
                    providerID: providerID,
                    accountRef: replacement,
                    operationID: removalOperationID)
                desiredRoutes[sessionID] = route
                if session.runtimeState == .streaming {
                    pendingRoutes[sessionID] = route
                } else {
                    pendingRoutes.removeValue(forKey: sessionID)
                    routingTasks.append((sessionID, enqueue(route, sessionID: sessionID)))
                }
            }

            if !routingTasks.isEmpty {
                for (sessionID, task) in routingTasks where await task.value == .failed {
                    failedSessionIDs.insert(sessionID)
                }
                continue
            }
            guard failedSessionIDs.isEmpty else {
                throw ProviderAccountRemovalError.reassignmentFailed(failedSessionIDs.count)
            }

            let hasQueuedTarget = desiredRoutes.values.contains {
                $0.providerID == providerID && $0.accountRef == accountRef
            } || pendingRoutes.values.contains {
                $0.providerID == providerID && $0.accountRef == accountRef
            }
            let hasAffectedQueue = affectedSessionIDs.contains { sessionID in
                desiredRoutes[sessionID] != nil || pendingRoutes[sessionID] != nil
            }
            let hasGeneratingTarget = managedSessions.values.contains { session in
                session.providerID == providerID
                    && session.currentProviderAccountRef == accountRef
                    && session.runtimeState == .streaming
            }
            let hasUnmovedTarget = replacement != nil && managedSessions.values.contains { session in
                session.providerID == providerID && session.currentProviderAccountRef == accountRef
            }
            if hasQueuedTarget || hasAffectedQueue || hasGeneratingTarget || hasUnmovedTarget {
                await waitForStateChange()
                continue
            }

            let result = try await performRemoval()
            _ = primaryStore.repairPrimary(
                providerID: providerID,
                accounts: result.accounts.filter { $0.accountRef != accountRef })
            return result
        }
    }

    func session(_ sessionID: UUID, didChangeAccount event: ProviderAccountChangedEvent) {
        guard let session = managedSessions[sessionID], session.providerID == event.providerID else {
            return
        }
        var state = sessionStates[sessionID] ?? SessionState(
            providerID: event.providerID,
            accountRef: nil,
            sequence: 0,
            isGenerating: session.runtimeState == .streaming)
        guard event.sequence > state.sequence else { return }
        state.providerID = event.providerID
        state.accountRef = event.accountRef
        state.sequence = event.sequence
        state.isGenerating = session.runtimeState == .streaming
        sessionStates[sessionID] = state
        publishSessionState()
    }

    private func enqueue(
        _ route: DesiredRoute,
        sessionID: UUID
    ) -> Task<RoutingOutcome, Never> {
        let previous = routingTails[sessionID]?.task
        let task = Task { @MainActor [weak self] in
            _ = await previous?.value
            guard let self else { return RoutingOutcome.superseded }
            let outcome = await self.apply(route, sessionID: sessionID)
            self.routingCompletions[sessionID] = RoutingCompletion(
                operationID: route.operationID,
                outcome: outcome)
            self.finishRouting(sessionID: sessionID, operationID: route.operationID)
            return outcome
        }
        routingTails[sessionID] = RoutingTail(route: route, task: task)
        return task
    }

    private func apply(
        _ route: DesiredRoute,
        sessionID: UUID
    ) async -> RoutingOutcome {
        guard desiredRoutes[sessionID] == route,
              let session = managedSessions[sessionID]
        else { return .superseded }
        guard !pendingRemovalAccounts.contains(ProviderAccountKey(
            providerID: route.providerID,
            accountRef: route.accountRef
        )) else {
            clear(route, sessionID: sessionID)
            return .superseded
        }
        guard session.runtimeState != .streaming else {
            pendingRoutes[sessionID] = route
            return .queued
        }
        guard session.providerID == route.providerID else {
            clear(route, sessionID: sessionID)
            return .failed
        }

        let result: SetSessionProviderAccountResult
        do {
            result = try await session.setProviderAccount(
                providerID: route.providerID,
                accountRef: route.accountRef)
        } catch {
            guard desiredRoutes[sessionID] == route else { return .superseded }
            clear(route, sessionID: sessionID)
            return .failed
        }
        guard desiredRoutes[sessionID] == route else { return .superseded }
        clear(route, sessionID: sessionID)
        self.session(
            session.id,
            didChangeAccount: ProviderAccountChangedEvent(
                providerID: result.account.providerID,
                accountRef: result.account.accountRef,
                reason: .manual,
                sequence: result.sequence))
        return .applied
    }

    private func clear(_ route: DesiredRoute, sessionID: UUID) {
        if desiredRoutes[sessionID] == route {
            desiredRoutes.removeValue(forKey: sessionID)
        }
        if pendingRoutes[sessionID] == route {
            pendingRoutes.removeValue(forKey: sessionID)
        }
    }

    private func finishRouting(sessionID: UUID, operationID: UInt64) {
        guard routingTails[sessionID]?.route.operationID == operationID else { return }
        routingTails.removeValue(forKey: sessionID)
        notifyStateChange()
    }

    private func publishSessionState() {
        activeAccountRefs = sessionStates.reduce(into: [:]) { refs, entry in
            if let accountRef = entry.value.accountRef {
                refs[entry.key] = accountRef
            }
        }
        generatingCounts = sessionStates.values.reduce(into: [:]) { counts, state in
            guard state.isGenerating,
                  let providerID = normalized(state.providerID),
                  let accountRef = normalized(state.accountRef)
            else { return }
            counts[ProviderAccountKey(providerID: providerID, accountRef: accountRef), default: 0] += 1
        }
        sessionCounts = sessionStates.values.reduce(into: [:]) { counts, state in
            guard let providerID = normalized(state.providerID),
                  let accountRef = normalized(state.accountRef)
            else { return }
            counts[ProviderAccountKey(providerID: providerID, accountRef: accountRef), default: 0] += 1
        }
        activeCounts = sessionStates.values.reduce(into: [:]) { counts, state in
            guard state.isGenerating, let providerID = normalized(state.providerID) else { return }
            counts[providerID, default: 0] += 1
        }
        notifyStateChange()
    }

    private func synchronizeManagedSessionState() {
        for session in managedSessions.values {
            synchronizeState(from: session)
        }
        publishSessionState()
    }

    private func synchronizeState(from session: any ProviderAccountSession) {
        sessionStates[session.id] = SessionState(
            providerID: session.providerID,
            accountRef: session.currentProviderAccountRef,
            sequence: session.providerAccountSequence,
            isGenerating: session.runtimeState == .streaming)
    }

    private func cancelRoutesTargeting(_ key: ProviderAccountKey) {
        let targetSessionIDs = desiredRoutes.compactMap { sessionID, route in
            route.providerID == key.providerID && route.accountRef == key.accountRef
                ? sessionID
                : nil
        }
        for sessionID in targetSessionIDs {
            desiredRoutes.removeValue(forKey: sessionID)
            pendingRoutes.removeValue(forKey: sessionID)
        }
        notifyStateChange()
    }

    private func waitForStateChange() async {
        await withCheckedContinuation { continuation in
            stateChangeWaiters.append(continuation)
        }
    }

    private func notifyStateChange() {
        let waiters = stateChangeWaiters
        stateChangeWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func recordFailure(count: Int, operationID: UInt64) {
        guard count > 0 else { return }
        if let current = failureRecord {
            guard operationID >= current.operationID else { return }
            failureRecord = FailureRecord(
                operationID: operationID,
                count: operationID == current.operationID ? current.count + count : count)
        } else {
            failureRecord = FailureRecord(operationID: operationID, count: count)
        }
        guard let failureRecord else { return }
        failureSummary = failureRecord.count == 1
            ? "Couldn’t switch 1 session."
            : "Couldn’t switch \(failureRecord.count) sessions."
    }

    private func normalized(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

typealias SessionActivityRegistry = ProviderAccountCoordinator
