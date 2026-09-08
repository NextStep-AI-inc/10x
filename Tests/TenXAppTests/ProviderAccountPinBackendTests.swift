import Foundation
import OmpKit
import Testing
@testable import TenXApp

/// Builds a session `.jsonl` fixture: a header line (matching stock OMP's
/// `SessionHeader`, no `parentId` — it is not part of the entry chain), plus
/// an optional literal entry line so chaining tests can assert the pin's
/// `parentId` lands on the file's actual current leaf.
private func temporarySessionFile(extraEntryLine: String? = nil) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "pin-\(UUID().uuidString).jsonl")
    var content = """
    {"type":"session","id":"s1","cwd":"/tmp","timestamp":"2026-08-26T12:00:00.000Z","version":3,"title":"t"}

    """
    if let extraEntryLine {
        content += extraEntryLine + "\n"
    }
    try Data(content.utf8).write(to: url)
    return url
}

private func parseLastLine(of url: URL) throws -> [String: Any] {
    let lines = try String(contentsOf: url, encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: true)
    let last = try #require(lines.last)
    let object = try JSONSerialization.jsonObject(with: Data(last.utf8)) as? [String: Any]
    return try #require(object)
}

// MARK: - Coordinator wiring (Step 6) fixtures
//
// `ProviderAccountCoordinatorTests.swift` and its `FakeProviderAccountSession`
// are outside this task's file fence (Step 8's commit list is
// `ProviderAccountPinBackend.swift`, `ProviderAccountCoordinator.swift`,
// `ProviderAccountPinBackendTests.swift`, `10x.xcodeproj`) and its 31 tests
// must keep passing unchanged, so the coordinator-level tests below use
// their own minimal fake session instead of touching that file.

@MainActor
private final class PinRoutingFakeSession: ProviderAccountSession {
    let id = UUID()
    var providerID: String?
    var runtimeState: SessionRuntimeState
    var currentProviderAccountRef: String?
    var providerAccountSequence = 0

    init(providerID: String?, accountRef: String?, runtimeState: SessionRuntimeState = .idle) {
        self.providerID = providerID
        currentProviderAccountRef = accountRef
        self.runtimeState = runtimeState
    }

    /// Not exercised below: `routingBackend` handles routing whenever it is
    /// configured, and `apply` only falls back to this call when no backend
    /// is set. Implemented anyway so this type satisfies
    /// `ProviderAccountSession` on its own.
    func setProviderAccount(
        providerID: String,
        accountRef: String
    ) async throws -> SetSessionProviderAccountResult {
        currentProviderAccountRef = accountRef
        providerAccountSequence += 1
        return SetSessionProviderAccountResult(
            account: ProviderAccountSummary(
                providerID: providerID,
                accountRef: accountRef,
                displayLabel: "Account",
                connectionOrder: 0,
                availability: .available,
                isActiveForSession: true),
            sequence: providerAccountSequence)
    }
}

@MainActor
private func makePinRoutingCoordinator(
    sessionFile: URL,
    restartSession: @escaping @MainActor (UUID) async -> Bool
) throws -> ProviderAccountCoordinator {
    let suiteName = "TenXAppTests.ProviderAccountPinBackend.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return ProviderAccountCoordinator(
        primaryStore: ProviderPrimaryPreferenceStore(defaults: defaults),
        routingBackend: ProviderAccountPinBackend(sessionFileForID: { _ in sessionFile }),
        restartSession: restartSession)
}

@Suite struct ProviderAccountPinBackendTests {
    // MARK: - appendPin: on-disk shape
    //
    // Step 3 of the brief required reading stock OMP's own
    // `SessionManager.appendCredentialPin` (packages/coding-agent/src/session/
    // session-manager.ts, commit b4e8e856a) before trusting the brief's
    // guessed shape. The real entry is `SessionEntryBase & { type:
    // "credential_pin"; provider; hash }` — i.e. it also carries `id`,
    // `parentId`, and `timestamp`, which the brief's original guess
    // (`{"type","provider","hash"}`) omitted. Those three fields are not
    // decoration: `SessionEntryIndex.insert` sets the file's leaf to
    // whichever entry is last on disk unconditionally, and `pathTo`/
    // `getBranch` walk backwards from that leaf via `parentId`. An entry
    // missing `parentId` (or carrying the wrong one) would make a resumed
    // session's history appear empty from that point on — the exact failure
    // this suite pins down below.

    @Test func appendingAPinAddsOneEntryAndPreservesExistingLines() throws {
        let url = try temporarySessionFile()
        defer { try? FileManager.default.removeItem(at: url) }

        try ProviderAccountPinBackend.appendPin(providerID: "anthropic", accountRef: "abc123", to: url)

        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 2)
        let entry = try JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any]
        #expect(entry?["type"] as? String == "credential_pin")
        #expect(entry?["provider"] as? String == "anthropic")
        #expect(entry?["hash"] as? String == "abc123")
    }

    @Test func appendedPinCarriesAFreshIdAndAnIso8601Timestamp() throws {
        let url = try temporarySessionFile()
        defer { try? FileManager.default.removeItem(at: url) }

        try ProviderAccountPinBackend.appendPin(providerID: "anthropic", accountRef: "abc123", to: url)

        let entry = try parseLastLine(of: url)
        let id = try #require(entry["id"] as? String)
        #expect(!id.isEmpty)
        let timestamp = try #require(entry["timestamp"] as? String)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(formatter.date(from: timestamp) != nil)
    }

    @Test func appendingAPinToAHeaderOnlyFileParentsToNullNotToTheHeader() throws {
        // A freshly created session (no turns yet) has only its header line.
        // `SessionEntryIndex` never inserted the header as an entry, so the
        // first real entry's parent is the tree root: `null`, present as a
        // key — not the header's own id, and not an omitted key (OMP's own
        // writer always emits the key; `tree()` treats `=== null` as root
        // and a missing key as a bug, not as "no parent").
        let url = try temporarySessionFile()
        defer { try? FileManager.default.removeItem(at: url) }

        try ProviderAccountPinBackend.appendPin(providerID: "anthropic", accountRef: "abc123", to: url)

        let entry = try parseLastLine(of: url)
        #expect(entry.keys.contains("parentId"))
        #expect(entry["parentId"] is NSNull)
    }

    @Test func appendingAPinChainsToTheFilesCurrentLeafEntry() throws {
        // The highest-severity failure mode identified while reading OMP's
        // source: an entry appended with the wrong (or no) `parentId` still
        // becomes the file's leaf on the next load — `insert()` sets the
        // leaf unconditionally — but `getBranch()` walking back from that
        // leaf would stop immediately, making every earlier turn invisible
        // even though the bytes are still on disk. This test is the one the
        // brief's original single-header fixture could not catch.
        let url = try temporarySessionFile(
            extraEntryLine: #"{"type":"message","id":"e1","parentId":null,"timestamp":"2026-08-26T12:00:01.000Z"}"#)
        defer { try? FileManager.default.removeItem(at: url) }

        try ProviderAccountPinBackend.appendPin(providerID: "anthropic", accountRef: "abc123", to: url)

        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 3)
        let entry = try parseLastLine(of: url)
        #expect(entry["parentId"] as? String == "e1")
    }

    @Test func appendingASecondPinChainsToTheFirstPinNotToTheOriginalLeaf() throws {
        let url = try temporarySessionFile(
            extraEntryLine: #"{"type":"message","id":"e1","parentId":null,"timestamp":"2026-08-26T12:00:01.000Z"}"#)
        defer { try? FileManager.default.removeItem(at: url) }

        try ProviderAccountPinBackend.appendPin(providerID: "anthropic", accountRef: "first", to: url)
        let firstPinID = try #require(parseLastLine(of: url)["id"] as? String)
        try ProviderAccountPinBackend.appendPin(providerID: "anthropic", accountRef: "second", to: url)

        let secondEntry = try parseLastLine(of: url)
        #expect(secondEntry["parentId"] as? String == firstPinID)
        #expect(secondEntry["id"] as? String != firstPinID)
    }

    @Test func appendingAPinNeverWritesRawIdentity() throws {
        let url = try temporarySessionFile()
        defer { try? FileManager.default.removeItem(at: url) }

        try ProviderAccountPinBackend.appendPin(providerID: "anthropic", accountRef: "abc123", to: url)

        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(!contents.contains("@"))
    }

    @Test func appendingAPinIsAtomicAndSurvivesAMissingTrailingNewline() throws {
        // A torn tail (no trailing newline, e.g. after a crash) must not
        // corrupt the append or lose the existing content.
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pin-\(UUID().uuidString).jsonl")
        try Data(#"{"type":"session","id":"s1","cwd":"/tmp","timestamp":"2026-08-26T12:00:00.000Z","version":3,"title":"t"}"#.utf8)
            .write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try ProviderAccountPinBackend.appendPin(providerID: "anthropic", accountRef: "abc123", to: url)

        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 2)
        #expect(lines[0].contains("\"id\":\"s1\""))
    }

    // MARK: - route(): stock OMP always needs a restart

    @Test func routingARunningSessionRequiresARestart() async throws {
        let backend = ProviderAccountPinBackend(sessionFileForID: { _ in try? temporarySessionFile() })

        let outcome = try await backend.route(
            providerID: "anthropic", accountRef: "abc123", sessionID: UUID())

        #expect(outcome == .restartRequired)
    }

    @Test func routingWithNoResolvableSessionFileThrowsRatherThanFakingSuccess() async throws {
        let backend = ProviderAccountPinBackend(sessionFileForID: { _ in nil })

        await #expect(throws: ProviderAccountPinBackendError.sessionFileUnavailable) {
            try await backend.route(providerID: "anthropic", accountRef: "abc123", sessionID: UUID())
        }
    }

    // MARK: - Coordinator wiring (Step 6)

    @Test @MainActor func restartSucceedingAppliesTheNewAccountAndClearsTheDesiredRoute() async throws {
        let sessionFile = try temporarySessionFile()
        defer { try? FileManager.default.removeItem(at: sessionFile) }
        let session = PinRoutingFakeSession(providerID: "anthropic", accountRef: "old-ref")
        var restartedSessionIDs: [UUID] = []
        let coordinator = try makePinRoutingCoordinator(sessionFile: sessionFile) { sessionID in
            restartedSessionIDs.append(sessionID)
            session.currentProviderAccountRef = "new-ref"
            session.providerAccountSequence += 1
            return true
        }
        coordinator.register(session)

        await coordinator.useAccount(
            "new-ref", providerID: "anthropic", scope: .thisSession, openSessionID: session.id)

        #expect(restartedSessionIDs == [session.id])
        #expect(coordinator.activeAccountRefs[session.id] == "new-ref")
        #expect(coordinator.failureSummary == nil)

        let pinnedEntry = try parseLastLine(of: sessionFile)
        #expect(pinnedEntry["hash"] as? String == "new-ref")
    }

    @Test @MainActor func restartFailingRecordsAFailureAndRestoresThePreviousPinOnDisk() async throws {
        let sessionFile = try temporarySessionFile()
        defer { try? FileManager.default.removeItem(at: sessionFile) }
        let session = PinRoutingFakeSession(providerID: "anthropic", accountRef: "old-ref")
        let coordinator = try makePinRoutingCoordinator(sessionFile: sessionFile) { _ in false }
        coordinator.register(session)

        await coordinator.useAccount(
            "new-ref", providerID: "anthropic", scope: .thisSession, openSessionID: session.id)

        // The session itself never moved off its previous account...
        #expect(session.currentProviderAccountRef == "old-ref")
        #expect(coordinator.failureSummary != nil)
        // ...and the on-disk pin — already written before the restart was
        // attempted — was compensated back to that same previous account,
        // so a future resume does not silently move accounts underneath
        // the user.
        let lastEntry = try parseLastLine(of: sessionFile)
        #expect(lastEntry["hash"] as? String == "old-ref")
    }

    @Test @MainActor func generatingSessionQueuesTheRouteAndRestartsOnlyOnceItGoesIdle() async throws {
        let sessionFile = try temporarySessionFile()
        defer { try? FileManager.default.removeItem(at: sessionFile) }
        let session = PinRoutingFakeSession(
            providerID: "anthropic", accountRef: "old-ref", runtimeState: .streaming)
        var restartCount = 0
        let coordinator = try makePinRoutingCoordinator(sessionFile: sessionFile) { _ in
            restartCount += 1
            session.currentProviderAccountRef = "new-ref"
            return true
        }
        coordinator.register(session)

        await coordinator.useAccount(
            "new-ref", providerID: "anthropic", scope: .thisSession, openSessionID: session.id)
        #expect(restartCount == 0)
        #expect(coordinator.pendingAccountRef(sessionID: session.id) == "new-ref")

        session.runtimeState = .idle
        await coordinator.sessionDidBecomeIdle(session.id)

        #expect(restartCount == 1)
        #expect(session.currentProviderAccountRef == "new-ref")
    }

    @Test @MainActor func newSessionReadoptsBeforeItsFirstPromptViaThePrimarySnapshot() async throws {
        let sessionFile = try temporarySessionFile()
        defer { try? FileManager.default.removeItem(at: sessionFile) }
        let session = PinRoutingFakeSession(providerID: "anthropic", accountRef: nil)
        var restartCount = 0
        let coordinator = try makePinRoutingCoordinator(sessionFile: sessionFile) { _ in
            restartCount += 1
            session.currentProviderAccountRef = "primary-ref"
            return true
        }
        await coordinator.useAccount(
            "primary-ref", providerID: "anthropic", scope: .allNewSessions, openSessionID: nil)
        let snapshot = coordinator.newSessionPrimarySnapshot()
        coordinator.register(session)

        await coordinator.prepareForFirstPrompt(sessionID: session.id, primarySnapshot: snapshot)

        #expect(restartCount == 1)
        #expect(session.currentProviderAccountRef == "primary-ref")
    }
}
