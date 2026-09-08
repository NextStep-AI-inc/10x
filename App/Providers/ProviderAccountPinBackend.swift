import Foundation

/// Errors thrown by `ProviderAccountPinBackend` when a pin cannot be routed
/// or written.
enum ProviderAccountPinBackendError: Error, Equatable {
    /// `sessionFileForID` returned `nil`. The coordinator only calls
    /// `route` for sessions it already manages, and every managed session
    /// has spawned `omp` at least once by then (`get_state` reports
    /// `sessionFile` right after spawn — see the brand-new-session flow in
    /// the task brief), so an unresolvable file here is a caller bug, not
    /// an expected outcome to paper over with a fabricated `.applied`.
    case sessionFileUnavailable
}

/// One `credential_pin` entry exactly as stock OMP 18.0.6's own
/// `SessionManager.appendCredentialPin` writes it
/// (`packages/coding-agent/src/session/session-manager.ts` and
/// `session-entries.ts`, commit `b4e8e856a`):
///
/// ```ts
/// appendCredentialPin(provider: string, hash: string): string {
///     const entry: CredentialPinEntry = {
///         type: "credential_pin",
///         ...this.#freshEntryFields(),  // id, parentId, timestamp
///         provider,
///         hash,
///     };
///     this.#recordEntry(entry);
///     return entry.id;
/// }
/// ```
///
/// `CredentialPinEntry extends SessionEntryBase`, so the on-disk object has
/// six keys, not the three (`type`/`provider`/`hash`) the task brief
/// originally guessed: `id`, `parentId`, and `timestamp` come from
/// `SessionEntryBase` and are required. This is not a cosmetic gap —
/// `SessionEntryIndex.insert` (in the same file) sets the file's leaf to
/// whichever entry was last processed *unconditionally*, and every read
/// (`getBranch`, `pathTo`, `getCredentialPins`) walks backward from that
/// leaf via `parentId`. An entry written without the correct `parentId`
/// still becomes the leaf on the next load, but the walk back from it stops
/// immediately — the resumed session would appear to have no history at
/// all, even though every prior turn is still sitting in the file.
private struct CredentialPinEntry: Encodable {
    let id: String
    let parentId: String?
    let timestamp: String
    let provider: String
    let hash: String

    private enum CodingKeys: String, CodingKey {
        case type, id, parentId, timestamp, provider, hash
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("credential_pin", forKey: .type)
        try container.encode(id, forKey: .id)
        // OMP's own writer always emits this key, `null` for the tree root
        // (`SessionEntryIndex.tree()` treats `=== null` as root and would
        // treat a missing key as a bug, not "no parent"). Swift's default
        // `Encodable` synthesis for `Optional` would instead *omit* the key
        // on `nil`, so this is spelled out explicitly.
        if let parentId {
            try container.encode(parentId, forKey: .parentId)
        } else {
            try container.encodeNil(forKey: .parentId)
        }
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(provider, forKey: .provider)
        try container.encode(hash, forKey: .hash)
    }
}

/// Routes provider-account changes on completely stock `omp` — no
/// extension, no forked RPC surface — by writing a `credential_pin` entry
/// directly into the session's own `.jsonl` file (tier t1,
/// `ProviderAccountTier.stockOMP`).
///
/// Stock OMP applies a pinned account only at session *adoption*
/// (`-r <sessionFile>`), never to a live process, so a successful write
/// here never takes effect on its own — the caller must close and respawn
/// the session's `omp` process with `-r` afterward. This backend therefore
/// never applies a pin in place and never returns `.applied`; queueing
/// while a session is mid-turn is the coordinator's job, performed before
/// ever calling `route`, so this backend also never returns `.queued`. Both
/// omissions are asserted structurally: `route`'s only successful outcome
/// is `.restartRequired`.
struct ProviderAccountPinBackend: ProviderAccountRouting {
    private let sessionFileForID: @Sendable (UUID) -> URL?

    init(sessionFileForID: @escaping @Sendable (UUID) -> URL?) {
        self.sessionFileForID = sessionFileForID
    }

    func route(
        providerID: String,
        accountRef: String,
        sessionID: UUID
    ) async throws -> ProviderAccountRouteOutcome {
        guard let sessionFile = sessionFileForID(sessionID) else {
            throw ProviderAccountPinBackendError.sessionFileUnavailable
        }
        try Self.appendPin(providerID: providerID, accountRef: accountRef, to: sessionFile)
        return .restartRequired
    }

    /// Appends one `credential_pin` entry to the session file at `url`,
    /// atomically: the whole file — existing bytes plus the new line — is
    /// written to a temporary file in the same directory and then swapped
    /// into place with a single rename (`Data.write(options: .atomic)`), so
    /// a crash mid-write can never leave a truncated or half-written
    /// session file behind. This is someone's conversation history.
    ///
    /// The new entry's `hash` carries only `accountRef` — the opaque
    /// `ProviderAccountRef.make(...)` digest, never a raw email, account
    /// id, or org id — so the session file never gains an identity it
    /// didn't already have.
    static func appendPin(providerID: String, accountRef: String, to url: URL) throws {
        let existing = try String(contentsOf: url, encoding: .utf8)
        let entry = CredentialPinEntry(
            id: freshID(avoiding: knownIDs(in: existing)),
            parentId: lastEntryID(in: existing),
            timestamp: iso8601Now(),
            provider: providerID,
            hash: accountRef)
        let line = try String(decoding: JSONEncoder().encode(entry), as: UTF8.self)

        var updated = existing
        if !updated.isEmpty, !updated.hasSuffix("\n") {
            updated += "\n"
        }
        updated += line + "\n"
        try Data(updated.utf8).write(to: url, options: .atomic)
    }

    // MARK: - Session-file parsing
    //
    // Lines are parsed leniently — an unparseable line (e.g. a torn tail
    // from a crash mid-write) is skipped rather than failing the whole
    // append, mirroring OMP's own `parseJsonlLenient`.

    /// The id of the file's current leaf entry: the last line whose parsed
    /// `type` is neither the session header (`"session"`) nor the optional
    /// fixed-width title slot (`"title"`) OMP may prefix the file with —
    /// neither participates in the `SessionEntryBase.parentId` chain. `nil`
    /// when the file has no entries yet (a freshly created session with
    /// only its header line), which is exactly when the correct parent for
    /// the first entry is the tree root, `null`.
    private static func lastEntryID(in content: String) -> String? {
        var leaf: String?
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let object = jsonObject(from: line),
                  let type = object["type"] as? String,
                  type != "session", type != "title",
                  let id = object["id"] as? String
            else { continue }
            leaf = id
        }
        return leaf
    }

    private static func knownIDs(in content: String) -> Set<String> {
        var ids: Set<String> = []
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let object = jsonObject(from: line), let id = object["id"] as? String else { continue }
            ids.insert(id)
        }
        return ids
    }

    private static func jsonObject(from line: Substring) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Mirrors stock OMP's `generateId` (`session-migrations.ts`):
    /// `crypto.randomUUID().slice(-8)`, retried on collision against every
    /// id already in the file (not just entries on the current branch, same
    /// as OMP's own `byId.has(id)` check).
    private static func freshID(avoiding known: Set<String>) -> String {
        for _ in 0..<100 {
            let candidate = String(UUID().uuidString.suffix(8)).lowercased()
            if !known.contains(candidate) { return candidate }
        }
        // Astronomically unlikely (100 collisions against 128-bit UUIDs) —
        // OMP's own fallback here is a Snowflake id; a full UUID is just as
        // collision-free and needs no extra dependency.
        return UUID().uuidString.lowercased()
    }

    /// Matches OMP's `nowIso()` (`new Date().toISOString()`) exactly,
    /// including milliseconds — see the task brief's own fixture
    /// (`"2026-08-26T12:00:00.000Z"`).
    private static func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
