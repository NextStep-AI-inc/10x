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
    private struct SessionState {
        var providerID: String?
        var accountRef: String?
        var sequence: Int
        var isGenerating: Bool
    }

    private(set) var managedSessions: [UUID: any ProviderAccountSession] = [:]
    private(set) var activeAccountRefs: [UUID: String] = [:]
    private(set) var generatingCounts: [ProviderAccountKey: Int] = [:]
    private(set) var activeCounts: [String: Int] = [:]
    private(set) var failureSummary: String?

    @ObservationIgnored private let primaryStore: ProviderPrimaryPreferenceStore
    @ObservationIgnored private var sessionStates: [UUID: SessionState] = [:]
    @ObservationIgnored private var pendingAccountRefs: [UUID: String] = [:]

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
        pendingAccountRefs.removeValue(forKey: sessionID)
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
        pendingAccountRefs[sessionID]
    }

    func useAccount(
        _ accountRef: String,
        providerID: String,
        scope: ProviderAccountScope,
        openSessionID: UUID?
    ) async {
        failureSummary = nil
        if scope == .allNewSessions {
            primaryStore.setPrimaryAccountRef(accountRef, providerID: providerID)
            return
        }

        let targets: [any ProviderAccountSession]
        switch scope {
        case .thisSession:
            targets = openSessionID
                .flatMap { managedSessions[$0] }
                .map { $0.providerID == providerID ? [$0] : [] }
                ?? []
        case .allCurrentSessions:
            targets = managedSessions.values.filter { $0.providerID == providerID }
        case .allNewSessions:
            targets = []
        }

        var failureCount = 0
        for session in targets {
            if session.runtimeState == .streaming {
                pendingAccountRefs[session.id] = accountRef
                continue
            }
            do {
                try await applyAccount(accountRef, providerID: providerID, to: session)
            } catch {
                failureCount += 1
            }
        }
        publishFailure(count: failureCount)
    }

    func sessionDidBecomeIdle(_ sessionID: UUID) async {
        guard let session = managedSessions[sessionID],
              session.runtimeState == .idle,
              let accountRef = pendingAccountRefs.removeValue(forKey: sessionID),
              let providerID = session.providerID
        else { return }

        do {
            try await applyAccount(accountRef, providerID: providerID, to: session)
            failureSummary = nil
        } catch {
            publishFailure(count: 1)
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

    private func applyAccount(
        _ accountRef: String,
        providerID: String,
        to session: any ProviderAccountSession
    ) async throws {
        let result = try await session.setProviderAccount(
            providerID: providerID,
            accountRef: accountRef)
        self.session(
            session.id,
            didChangeAccount: ProviderAccountChangedEvent(
                providerID: result.account.providerID,
                accountRef: result.account.accountRef,
                reason: .manual,
                sequence: result.sequence))
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
        activeCounts = sessionStates.values.reduce(into: [:]) { counts, state in
            guard state.isGenerating, let providerID = normalized(state.providerID) else { return }
            counts[providerID, default: 0] += 1
        }
    }

    private func publishFailure(count: Int) {
        guard count > 0 else { return }
        failureSummary = count == 1
            ? "Couldn’t switch 1 session."
            : "Couldn’t switch \(count) sessions."
    }

    private func normalized(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

typealias SessionActivityRegistry = ProviderAccountCoordinator
