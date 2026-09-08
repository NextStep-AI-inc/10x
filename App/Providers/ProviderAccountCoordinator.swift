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
    case noEligibleReplacement
    case reassignmentFailed(Int)
}

struct NewSessionPrimarySnapshot: Sendable {
    fileprivate let accountRefs: [String: String]
    fileprivate let routingVersion: UInt64
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

    private struct RoutingCompletion: Equatable {
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
    @ObservationIgnored private var activeManagedTurns: Set<UUID> = []
    @ObservationIgnored private var stateChangeWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var appliedRoutes: [UUID: DesiredRoute] = [:]
    @ObservationIgnored private var failureRecord: FailureRecord?
    @ObservationIgnored private var nextOperationID: UInt64 = 0
    // `var`, not `let`: `install(routingBackend:restartSession:)` below is
    // the only place either is ever written after `init`. Both stay
    // `private` regardless — nothing outside this type may assign them
    // directly, keeping `install` the single, greppable point of entry.
    @ObservationIgnored private var routingBackend: ProviderAccountRouting?
    @ObservationIgnored private var restartSession: (@MainActor (UUID) async -> Bool)?

    /// - Parameters:
    ///   - routingBackend: How to change a session's account. `nil` (the
    ///     default) preserves the original behavior — every caller asks the
    ///     session itself via `ProviderAccountSession.setProviderAccount`.
    ///     When set, `apply` routes through the backend instead, which
    ///     covers both `ProviderAccountExtensionBackend` (t2, applies in
    ///     place) and `ProviderAccountPinBackend` (t1, always answers
    ///     `.restartRequired` — see `restartSession` below). Selecting which
    ///     backend a given session gets is done by whoever constructs this
    ///     coordinator, keyed off `ProviderAccountTier`; this type only
    ///     needs to know how to drive whichever one it's handed. Tests
    ///     construct backends directly and pass them here; the live app
    ///     instead constructs this coordinator with both `nil` and calls
    ///     `install(routingBackend:restartSession:)` once its session
    ///     infrastructure exists to build them from — see that method.
    ///   - restartSession: Closes and respawns a session's `omp` process
    ///     with `-r <sessionFile>` so a pin already written to disk takes
    ///     effect, returning whether the restart succeeded. `nil` when no
    ///     backend can ever produce `.restartRequired` (the default, and
    ///     always true for `ProviderAccountExtensionBackend`).
    init(
        primaryStore: ProviderPrimaryPreferenceStore = ProviderPrimaryPreferenceStore(),
        routingBackend: ProviderAccountRouting? = nil,
        restartSession: (@MainActor (UUID) async -> Bool)? = nil
    ) {
        self.primaryStore = primaryStore
        self.routingBackend = routingBackend
        self.restartSession = restartSession
    }

    /// Sets `routingBackend` and `restartSession` after construction — the
    /// live app's only way to configure either, since `AppDependencies`'
    /// coordinator factory is a zero-argument closure and the pieces these
    /// two are built from (the account channel registry, `managedSessions`)
    /// live on `AppModel`, not `AppDependencies`. See `AppModel.init`, the
    /// sole call site.
    ///
    /// Idempotent by design, not one-shot: calling this again just replaces
    /// both values (`@MainActor` isolation rules out a torn read), so a
    /// second call — from a future reconfiguration path, or a test — is a
    /// deliberate reconfiguration rather than a programmer error worth
    /// crashing over. `AppModel` happens to call it exactly once, from
    /// `init`, but nothing here depends on that.
    func install(
        routingBackend: ProviderAccountRouting?,
        restartSession: (@MainActor (UUID) async -> Bool)?
    ) {
        self.routingBackend = routingBackend
        self.restartSession = restartSession
    }

    /// Whether `install` has ever set a non-`nil` backend. Exposed so
    /// callers — today, only a test — can confirm the live app actually
    /// wired one, without exposing the backend value itself (`routingBackend`
    /// stays `private`).
    var hasLiveRoutingBackend: Bool { routingBackend != nil }

    var canCreateManagedSession: Bool {
        pendingRemovalAccounts.isEmpty
    }

    @discardableResult
    func register(_ session: any ProviderAccountSession) -> Bool {
        guard managedSessions[session.id] != nil || canCreateManagedSession else { return false }
        managedSessions[session.id] = session
        sessionStates[session.id] = SessionState(
            providerID: session.providerID,
            accountRef: session.currentProviderAccountRef,
            sequence: session.providerAccountSequence,
            isGenerating: session.runtimeState == .streaming)
        publishSessionState()
        return true
    }

    func unregister(sessionID: UUID) {
        managedSessions.removeValue(forKey: sessionID)
        sessionStates.removeValue(forKey: sessionID)
        desiredRoutes.removeValue(forKey: sessionID)
        pendingRoutes.removeValue(forKey: sessionID)
        routingTails.removeValue(forKey: sessionID)?.task.cancel()
        routingCompletions.removeValue(forKey: sessionID)
        activeManagedTurns.remove(sessionID)
        appliedRoutes.removeValue(forKey: sessionID)
        publishSessionState()
    }

    func update(sessionID: UUID, providerID: String?, isGenerating: Bool) {
        guard managedSessions[sessionID] != nil else { return }
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

    func beginManagedTurn(sessionID: UUID) -> Bool {
        guard let session = managedSessions[sessionID],
              !activeManagedTurns.contains(sessionID)
        else { return false }
        if let providerID = normalized(session.providerID) {
            guard !pendingRemovalAccounts.contains(where: { $0.providerID == providerID }) else {
                return false
            }
        } else {
            guard pendingRemovalAccounts.isEmpty else { return false }
        }
        activeManagedTurns.insert(sessionID)
        notifyStateChange()
        return true
    }

    func endManagedTurn(sessionID: UUID) {
        guard activeManagedTurns.remove(sessionID) != nil else { return }
        notifyStateChange()
    }

    func remove(sessionID: UUID) {
        unregister(sessionID: sessionID)
    }

    /// Whether this coordinator still has work queued for a session: a route
    /// waiting to apply or in flight, a routing tail still running, or a
    /// managed turn between `beginManagedTurn` and `endManagedTurn`.
    /// `AppModel` keeps such sessions out of idle-runtime eviction, because
    /// `unregister` would cancel all of it.
    func hasPendingWork(sessionID: UUID) -> Bool {
        pendingRoutes[sessionID] != nil
            || desiredRoutes[sessionID] != nil
            || routingTails[sessionID] != nil
            || activeManagedTurns.contains(sessionID)
    }

    func primaryAccountRef(providerID: String) -> String? {
        primaryStore.primaryAccountRef(providerID: providerID)
    }

    func scopeAvailability(
        providerID: String,
        openSessionID: UUID?
    ) -> ProviderAccountScopeAvailability {
        let providerSessionIDs = managedSessions.compactMap { sessionID, session in
            session.providerID == providerID ? sessionID : nil
        }
        return ProviderAccountScopeAvailability(
            isThisSessionAvailable: openSessionID.map(providerSessionIDs.contains) ?? false,
            areAllCurrentSessionsAvailable: !providerSessionIDs.isEmpty)
    }

    @discardableResult
    func reconcilePrimaryAccount(
        providerID: String,
        accounts: [ProviderAccountSummary]
    ) -> String? {
        primaryStore.repairPrimary(providerID: providerID, accounts: accounts)
    }

    func newSessionPrimarySnapshot() -> NewSessionPrimarySnapshot {
        NewSessionPrimarySnapshot(
            accountRefs: primaryStore.primaryAccountRefsSnapshot(),
            routingVersion: nextOperationID)
    }

    func pendingAccountRef(sessionID: UUID) -> String? {
        pendingRoutes[sessionID]?.accountRef
    }

    /// Which of the three confirmation scopes an account already satisfies, so the
    /// panel can disable choices that would be a no-op.
    func scopeSatisfaction(
        providerID: String,
        accountRef: String,
        openSessionID: UUID?
    ) -> ProviderAccountScopeSatisfaction {
        let providerSessionIDs = sessionStates.filter { entry in
            entry.value.providerID == providerID
        }.keys
        let isRoutedToAccount = { (sessionID: UUID) -> Bool in
            self.effectiveAccountRef(sessionID: sessionID) == accountRef
        }
        return ProviderAccountScopeSatisfaction(
            isThisSessionSatisfied: openSessionID.map { sessionID in
                providerSessionIDs.contains(sessionID) && isRoutedToAccount(sessionID)
            } ?? false,
            areAllCurrentSessionsSatisfied: !providerSessionIDs.isEmpty
                && providerSessionIDs.allSatisfy(isRoutedToAccount),
            isAllNewSessionsSatisfied: primaryStore.primaryAccountRef(
                providerID: providerID) == accountRef)
    }

    private func effectiveAccountRef(sessionID: UUID) -> String? {
        desiredRoutes[sessionID]?.accountRef
            ?? pendingRoutes[sessionID]?.accountRef
            ?? sessionStates[sessionID]?.accountRef
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

    func prepareForFirstPrompt(
        sessionID: UUID,
        primarySnapshot: NewSessionPrimarySnapshot
    ) async {
        var didApplyPrimary = false
        while true {
            await waitForRoutingTail(sessionID: sessionID)
            guard let session = managedSessions[sessionID],
                  let providerID = session.providerID,
                  let accountRef = primarySnapshot.accountRefs[providerID]
            else { return }
            if hasNewerValidRoute(
                appliedRoutes[sessionID],
                than: primarySnapshot.routingVersion,
                for: session)
                || hasNewerValidRoute(
                    pendingRoutes[sessionID],
                    than: primarySnapshot.routingVersion,
                    for: session)
            {
                return
            }
            guard !didApplyPrimary else { return }

            let route = DesiredRoute(
                providerID: providerID,
                accountRef: accountRef,
                operationID: primarySnapshot.routingVersion)
            desiredRoutes[sessionID] = route
            if session.runtimeState == .streaming {
                pendingRoutes[sessionID] = route
                return
            }
            pendingRoutes.removeValue(forKey: sessionID)

            switch await enqueue(route, sessionID: sessionID).value {
            case .applied:
                didApplyPrimary = true
            case .queued:
                return
            case .failed:
                recordFailure(count: 1, operationID: primarySnapshot.routingVersion)
                return
            case .superseded:
                continue
            }
        }
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

        let originalPrimary = primaryStore.primaryAccountRef(providerID: providerID)
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
        guard remainingAccounts.isEmpty || remainingAccounts.contains(where: \.isEligiblePrimary) else {
            throw ProviderAccountRemovalError.noEligibleReplacement
        }
        let replacement = primaryStore.repairPrimary(
            providerID: providerID,
            accounts: remainingAccounts)
        nextOperationID &+= 1
        let removalOperationID = nextOperationID
        var affectedSessionIDs: Set<UUID> = []
        var failedSessionIDs: Set<UUID> = []
        var movedSessionAccounts: [UUID: String] = [:]

        cancelRoutesTargeting(key)

        while true {
            synchronizeManagedSessionState()
            for session in managedSessions.values
            where session.providerID == providerID && session.currentProviderAccountRef == accountRef {
                affectedSessionIDs.insert(session.id)
            }
            for sessionID in affectedSessionIDs {
                guard routingCompletions[sessionID] == RoutingCompletion(
                    operationID: removalOperationID,
                    outcome: .applied),
                      let currentAccountRef = managedSessions[sessionID]?.currentProviderAccountRef,
                      currentAccountRef != accountRef
                else { continue }
                movedSessionAccounts[sessionID] = currentAccountRef
            }

            let relevantTails = routingTails.filter { sessionID, tail in
                managedSessions[sessionID]?.providerID == providerID
                    || tail.route.providerID == providerID
            }.map(\.value.task)
            if !relevantTails.isEmpty {
                for task in relevantTails {
                    _ = await task.value
                }
                continue
            }

            var routingTasks: [(UUID, DesiredRoute, Task<RoutingOutcome, Never>)] = []
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
                    routingTasks.append((sessionID, route, enqueue(route, sessionID: sessionID)))
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
                    routingTasks.append((sessionID, route, enqueue(route, sessionID: sessionID)))
                }
            }

            if !routingTasks.isEmpty {
                for (sessionID, route, task) in routingTasks {
                    let outcome = await task.value
                    if outcome == .failed {
                        failedSessionIDs.insert(sessionID)
                    } else if outcome == .applied, route.operationID == removalOperationID {
                        movedSessionAccounts[sessionID] = route.accountRef
                    }
                }
                continue
            }
            guard failedSessionIDs.isEmpty else {
                await restoreRemovalMutation(
                    providerID: providerID,
                    accountRef: accountRef,
                    originalPrimary: originalPrimary,
                    removalOperationID: removalOperationID,
                    movedSessionAccounts: movedSessionAccounts)
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
            let hasGeneratingProvider = managedSessions.values.contains { session in
                session.providerID == providerID
                    && session.runtimeState == .streaming
            }
            let hasActiveManagedTurn = activeManagedTurns.contains { sessionID in
                guard let session = managedSessions[sessionID] else { return false }
                return session.providerID == nil || session.providerID == providerID
            }
            let hasLoadingRegistration = managedSessions.values.contains { session in
                session.runtimeState == .loading
                    && (session.providerID == nil || session.providerID == providerID)
            }
            let hasUnmovedTarget = replacement != nil && managedSessions.values.contains { session in
                session.providerID == providerID && session.currentProviderAccountRef == accountRef
            }
            if hasQueuedTarget
                || hasAffectedQueue
                || hasGeneratingProvider
                || hasActiveManagedTurn
                || hasLoadingRegistration
                || hasUnmovedTarget
            {
                await waitForStateChange()
                continue
            }

            let result: ProviderAccountRemovalResult
            do {
                result = try await performRemoval()
            } catch {
                await restoreRemovalMutation(
                    providerID: providerID,
                    accountRef: accountRef,
                    originalPrimary: originalPrimary,
                    removalOperationID: removalOperationID,
                    movedSessionAccounts: movedSessionAccounts)
                throw error
            }
            _ = primaryStore.repairPrimary(
                providerID: providerID,
                accounts: result.accounts.filter { $0.accountRef != accountRef })
            return result
        }
    }

    private func restoreRemovalMutation(
        providerID: String,
        accountRef: String,
        originalPrimary: String?,
        removalOperationID: UInt64,
        movedSessionAccounts: [UUID: String]
    ) async {
        primaryStore.setPrimaryAccountRef(originalPrimary, providerID: providerID)
        for sessionID in movedSessionAccounts.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let movedAccountRef = movedSessionAccounts[sessionID],
                  routingCompletions[sessionID] == RoutingCompletion(
                    operationID: removalOperationID,
                    outcome: .applied),
                  let session = managedSessions[sessionID],
                  session.providerID == providerID,
                  session.currentProviderAccountRef == movedAccountRef,
                  session.runtimeState != .streaming
            else { continue }
            do {
                let result = try await session.setProviderAccount(
                    providerID: providerID,
                    accountRef: accountRef)
                self.session(
                    sessionID,
                    didChangeAccount: ProviderAccountChangedEvent(
                        providerID: result.account.providerID,
                        accountRef: result.account.accountRef,
                        reason: .manual,
                        sequence: result.sequence))
            } catch {
                synchronizeState(from: session)
            }
        }
        publishSessionState()
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

        guard let routingBackend else {
            return await applyDirectly(route, sessionID: sessionID, session: session)
        }
        return await applyThroughBackend(routingBackend, route: route, sessionID: sessionID, session: session)
    }

    /// The original apply path: ask the session itself to change its
    /// account over its own RPC connection. Used whenever no
    /// `ProviderAccountRouting` backend is configured, so every existing
    /// caller — and every test double that implements only
    /// `ProviderAccountSession` — keeps working unchanged.
    private func applyDirectly(
        _ route: DesiredRoute,
        sessionID: UUID,
        session: any ProviderAccountSession
    ) async -> RoutingOutcome {
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
        appliedRoutes[sessionID] = route
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

    /// Routes through a `ProviderAccountRouting` backend instead of the
    /// direct RPC call above. `.queued` mirrors the streaming guard already
    /// passed in `apply` — a backend can discover a session went live
    /// mid-route even though that guard already cleared it (currently only
    /// reachable via `ProviderAccountExtensionBackend`, never
    /// `ProviderAccountPinBackend`, which never returns it).
    /// `.restartRequired` is `ProviderAccountPinBackend`'s only successful
    /// outcome: the pin is already on disk, and only a
    /// close-and-respawn-with-`-r` makes it take effect.
    private func applyThroughBackend(
        _ backend: ProviderAccountRouting,
        route: DesiredRoute,
        sessionID: UUID,
        session: any ProviderAccountSession
    ) async -> RoutingOutcome {
        let previousAccountRef = session.currentProviderAccountRef
        let outcome: ProviderAccountRouteOutcome
        do {
            outcome = try await backend.route(
                providerID: route.providerID,
                accountRef: route.accountRef,
                sessionID: sessionID)
        } catch {
            guard desiredRoutes[sessionID] == route else { return .superseded }
            clear(route, sessionID: sessionID)
            return .failed
        }
        guard desiredRoutes[sessionID] == route else { return .superseded }

        switch outcome {
        case .applied:
            appliedRoutes[sessionID] = route
            clear(route, sessionID: sessionID)
            // The backend applied the change over its own transport (the
            // extension channel), not through `session.setProviderAccount`,
            // so there is no `SetSessionProviderAccountResult` to fabricate
            // an event from — resync from the session's own state instead.
            synchronizeState(from: session)
            publishSessionState()
            return .applied
        case .queued:
            pendingRoutes[sessionID] = route
            return .queued
        case .restartRequired:
            return await performRestart(
                route,
                sessionID: sessionID,
                backend: backend,
                previousAccountRef: previousAccountRef)
        }
    }

    /// Honors `.restartRequired` by closing and respawning the session's
    /// `omp` process with `-r <sessionFile>` via the caller-supplied
    /// `restartSession` closure. A failed restart must not strand the
    /// on-disk pin pointing at an account the running process never
    /// adopted — the file already carries the new pin by the time this
    /// runs, so on failure this re-pins the previous account before
    /// reporting failure, keeping the session usable on the account it was
    /// already on both in memory and on disk.
    private func performRestart(
        _ route: DesiredRoute,
        sessionID: UUID,
        backend: ProviderAccountRouting,
        previousAccountRef: String?
    ) async -> RoutingOutcome {
        guard let restartSession else {
            await compensate(route, backend: backend, previousAccountRef: previousAccountRef, sessionID: sessionID)
            clear(route, sessionID: sessionID)
            return .failed
        }
        let didRestart = await restartSession(sessionID)
        guard desiredRoutes[sessionID] == route else { return .superseded }
        guard didRestart, let session = managedSessions[sessionID] else {
            await compensate(route, backend: backend, previousAccountRef: previousAccountRef, sessionID: sessionID)
            clear(route, sessionID: sessionID)
            return .failed
        }
        appliedRoutes[sessionID] = route
        clear(route, sessionID: sessionID)
        synchronizeState(from: session)
        publishSessionState()
        return .applied
    }

    /// Best-effort: re-pin the previous account so a future resume does not
    /// silently move accounts underneath the user. Errors are swallowed —
    /// this call is already inside a failure path, and the coordinator has
    /// no better recovery to offer than the failure it is about to report
    /// either way.
    private func compensate(
        _ route: DesiredRoute,
        backend: ProviderAccountRouting,
        previousAccountRef: String?,
        sessionID: UUID
    ) async {
        guard let previousAccountRef else { return }
        _ = try? await backend.route(
            providerID: route.providerID,
            accountRef: previousAccountRef,
            sessionID: sessionID)
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

    private func waitForRoutingTail(sessionID: UUID) async {
        while let latest = routingTails[sessionID]?.task {
            _ = await latest.value
        }
    }

    private func hasNewerValidRoute(
        _ route: DesiredRoute?,
        than routingVersion: UInt64,
        for session: any ProviderAccountSession
    ) -> Bool {
        guard let route else { return false }
        return route.operationID > routingVersion && route.providerID == session.providerID
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
