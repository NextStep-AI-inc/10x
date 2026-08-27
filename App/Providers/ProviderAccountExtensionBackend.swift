import Foundation
import OmpKit

/// One command sent through the `tenx.provider-accounts.v1` channel. `id` is
/// caller-generated and echoed back by the extension so a reply — which
/// arrives asynchronously, on a later frame — can be matched to the command
/// that produced it.
struct ProviderAccountChannelCommand: Sendable, Equatable {
    let id: String
    let command: String
    let params: [String: JSONValue]
}

enum ProviderAccountChannelError: Error, Equatable {
    /// No extension answered, or the loop dropped. The caller degrades this
    /// session to the stock tier rather than reporting a routing failure.
    case unavailable
    case rejected(String)
}

/// Transport for the extension command channel, kept separate from
/// `ProviderAccountExtensionBackend` so tests can drive the backend without
/// spawning `omp`. `send` resolves to the command's reply `data` on success;
/// a command-level failure (the extension's `{ok: false, error}`) is
/// reported as a returned `JSONValue` containing an `"error"` key, not a
/// thrown error — only channel-level failures (no answer, the loop
/// dropped) throw `ProviderAccountChannelError.unavailable`.
protocol ProviderAccountChannel: Sendable {
    func send(_ command: ProviderAccountChannelCommand) async throws -> JSONValue
}

/// Routes account changes through the bundled TypeScript extension (tier
/// t2). Every write is a `pin_account` command sent over the caller-supplied
/// `channel`, which is already scoped to the one session being routed — see
/// `ProviderAccountExtensionChannel` below for how that scoping is wired to
/// a live `omp` process.
struct ProviderAccountExtensionBackend: ProviderAccountRouting {
    private let channel: any ProviderAccountChannel

    init(channel: any ProviderAccountChannel) {
        self.channel = channel
    }

    /// `sessionID` is not consulted here: `channel` is already bound to one
    /// session's RPC event stream by whoever constructed this backend, so
    /// there is nothing left for this call to disambiguate. It stays a
    /// parameter to satisfy `ProviderAccountRouting`, the interface shared
    /// with `ProviderAccountPinBackend`, which is not similarly scoped.
    func route(
        providerID: String,
        accountRef: String,
        sessionID: UUID
    ) async throws -> ProviderAccountRouteOutcome {
        let command = ProviderAccountChannelCommand(
            id: UUID().uuidString,
            command: "pin_account",
            params: [
                "providerId": .string(providerID),
                "accountRef": .string(accountRef),
            ])

        let reply: JSONValue
        do {
            reply = try await channel.send(command)
        } catch let error as ProviderAccountChannelError {
            throw error
        } catch {
            throw ProviderAccountChannelError.unavailable
        }

        guard let errorField = reply["error"] else {
            return .applied
        }
        let message = errorField.stringValue ?? "unknown error"
        if message == "streaming" {
            // The session is mid-turn. The coordinator already owns
            // queueing and re-issues once the session goes idle — this is
            // not a routing failure.
            return .queued
        }
        throw ProviderAccountChannelError.rejected(message)
    }
}

/// Talks the `tenx.provider-accounts.v1` command protocol over one omp
/// session's RPC event stream and its `extension_ui_response` sender.
///
/// The extension (`OmpExtension/src/command-channel.ts`) holds exactly one
/// `ctx.ui.input()` call open at all times (confirmed live against `omp`
/// 18.0.4 in Task 1). Sending a command means answering that open request;
/// the extension's reply is never the return value of that answer — it
/// arrives as the `placeholder` of the *next* `extension_ui_request` frame
/// the extension opens, after it has finished processing the command. This
/// type correlates a reply to its command by matching the pending command's
/// `id` against the `id` embedded in that later placeholder's JSON.
///
/// Single-flight, matching the extension: only one command may be in flight
/// at a time. A second concurrent `send` call waits its turn rather than
/// racing the first for the one open request slot.
///
/// Verified by reading `command-channel.ts` and `task-1-report.md` against
/// the real wire behavior, not by a test of its own — nothing in this task
/// spins up a live extension loop against Swift, so
/// `ProviderAccountExtensionBackendTests` exercises the backend only
/// through `ProviderAccountChannel`, never this concrete type. Two things
/// still open for whoever wires this to a real session: (1) `events` and
/// `respond` must come from that session's own RPC client, and
/// `AsyncStream` has exactly one consumer — `SessionController` already
/// consumes every frame on that stream (see
/// `App/Sessions/SessionController.swift` `consumeExtensionUI`), so this
/// channel cannot simply attach a second `for await` loop to the same
/// stream; some fan-out is required. This channel's frames are no longer a
/// *UI* hazard either way — `ExtensionUIRouter.parse` now excludes
/// `ExtensionUIRouter.providerAccountChannelTitle` unconditionally, so
/// `SessionController` seeing them without this channel also attached is
/// silently harmless, just non-functional. (2) a reply's optional `events`
/// key (Task 7's piggybacked availability/failover frames) is
/// intentionally ignored here; nothing in this task consumes it.
actor ProviderAccountExtensionChannel: ProviderAccountChannel {
    /// Single source of truth for the marker string, shared with the guard
    /// in `ExtensionUIRouter.parse` that keeps these frames off any
    /// user-facing surface — see that constant's doc comment for why this
    /// type does not declare its own copy of the literal.
    private static let title = ExtensionUIRouter.providerAccountChannelTitle

    private let events: AsyncStream<RpcFrame>
    private let respond: @Sendable (String, [String: JSONValue]) async throws -> Void

    private var listenerTask: Task<Void, Never>?
    private var openRequestID: String?
    private var readyWaiter: CheckedContinuation<String?, Never>?
    private var inFlight: (commandID: String, continuation: CheckedContinuation<JSONValue, any Error>)?
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isDropped = false

    init(
        events: AsyncStream<RpcFrame>,
        respond: @escaping @Sendable (String, [String: JSONValue]) async throws -> Void
    ) {
        self.events = events
        self.respond = respond
    }

    deinit {
        listenerTask?.cancel()
    }

    /// Started lazily, on the first `send`, rather than from `init`: an
    /// actor's synchronous `init` is nonisolated, so it cannot assign an
    /// actor-isolated stored property (`listenerTask`) from a closure that
    /// captures `self` — the compiler rejects it outright. This mirrors
    /// `ProviderManagementService.startForwarding`, which for the same
    /// reason is also called after construction rather than from `init`.
    /// `AsyncStream`'s default buffering means no frame is lost by waiting:
    /// values queue until this consumer attaches.
    private func startListeningIfNeeded() {
        guard listenerTask == nil else { return }
        listenerTask = Task { [weak self] in
            guard let self else { return }
            for await frame in self.events {
                await self.handle(frame)
            }
            await self.handleStreamEnded()
        }
    }

    func send(_ command: ProviderAccountChannelCommand) async throws -> JSONValue {
        startListeningIfNeeded()
        await waitForTurn()
        defer { releaseTurn() }

        guard let requestID = await claimOpenRequestID() else {
            throw ProviderAccountChannelError.unavailable
        }

        let body: [String: JSONValue] = ["value": .string(Self.encode(command))]
        return try await withCheckedThrowingContinuation { continuation in
            inFlight = (command.id, continuation)
            Task { [respond] in
                do {
                    try await respond(requestID, body)
                } catch {
                    await self.failInFlight(commandID: command.id)
                }
            }
        }
    }

    // MARK: - Single-flight turn queue

    private func waitForTurn() async {
        if !isBusy {
            isBusy = true
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    private func releaseTurn() {
        guard !waiters.isEmpty else {
            isBusy = false
            return
        }
        // Ownership transfers straight to the next waiter; `isBusy` stays
        // true throughout, so this is not a re-entry into "not busy".
        waiters.removeFirst().resume()
    }

    /// Awaits the extension's open request slot rather than checking it
    /// synchronously. `waitForTurn()`'s fast (uncontended) path returns
    /// without ever suspending, so a plain `if let requestID = openRequestID`
    /// performed right after it can run before the just-scheduled listener
    /// `Task` (`startListeningIfNeeded`) has had any opportunity to drain
    /// even an *already-buffered* frame — `AsyncStream` buffers unboundedly
    /// by default, so a frame can be sitting there the whole time. Proven
    /// empirically: a fresh channel's first `send` threw `.unavailable`
    /// despite a request already present in `events`
    /// (`firstSendSucceedsEvenWhenTheOpeningFrameWasAlreadyBuffered`).
    /// A `nil` result here means the channel is genuinely gone
    /// (`isDropped`), never merely "not scheduled yet" — `.unavailable`
    /// must keep meaning "degrade to the stock tier," not "raced our own
    /// startup."
    private func claimOpenRequestID() async -> String? {
        if isDropped { return nil }
        if let requestID = openRequestID {
            openRequestID = nil
            return requestID
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            readyWaiter = continuation
        }
    }

    /// The `handle`-side counterpart to `claimOpenRequestID`: hands a newly
    /// opened request straight to whichever `send` is already waiting on
    /// it, or stores it for the next `send` to claim if none is waiting.
    /// Single-flight (`waitForTurn`) guarantees at most one `readyWaiter`
    /// is ever registered at a time.
    private func provideOpenRequestID(_ requestID: String) {
        if let readyWaiter {
            self.readyWaiter = nil
            readyWaiter.resume(returning: requestID)
        } else {
            openRequestID = requestID
        }
    }

    // MARK: - Frame handling

    private func handle(_ frame: RpcFrame) {
        guard case .extensionUIRequest(let request) = frame,
              request.payload["title"]?.stringValue == Self.title
        else { return }

        resolveIfMatching(placeholder: request.payload["placeholder"]?.stringValue)
        provideOpenRequestID(request.id)
    }

    private func resolveIfMatching(placeholder: String?) {
        guard let inFlight,
              let placeholder,
              let reply = try? Self.decode(placeholder),
              reply["id"]?.stringValue == inFlight.commandID
        else { return }

        self.inFlight = nil
        if reply["ok"]?.boolValue == true {
            inFlight.continuation.resume(returning: reply["data"] ?? .null)
        } else {
            let message = reply["error"]?.stringValue ?? "unknown error"
            inFlight.continuation.resume(returning: .object(["error": .string(message)]))
        }
    }

    private func handleStreamEnded() {
        isDropped = true
        openRequestID = nil
        if let inFlight {
            self.inFlight = nil
            inFlight.continuation.resume(throwing: ProviderAccountChannelError.unavailable)
        }
        if let readyWaiter {
            self.readyWaiter = nil
            readyWaiter.resume(returning: nil)
        }
        let queued = waiters
        waiters.removeAll()
        queued.forEach { $0.resume() }
    }

    private func failInFlight(commandID: String) {
        guard let inFlight, inFlight.commandID == commandID else { return }
        self.inFlight = nil
        inFlight.continuation.resume(throwing: ProviderAccountChannelError.unavailable)
    }

    // MARK: - Wire encoding

    private static func encode(_ command: ProviderAccountChannelCommand) -> String {
        let object = JSONValue.object([
            "id": .string(command.id),
            "command": .string(command.command),
            "params": .object(command.params),
        ])
        let data = (try? JSONEncoder().encode(object)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static func decode(_ raw: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
    }
}
