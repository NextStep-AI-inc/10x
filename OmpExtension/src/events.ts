/**
 * Sequencing and wire-frame shaping for availability/failover notifications.
 * Deliberately ctx-free and I/O-free — everything here is a pure function
 * over plain values, so it is unit-testable without a fake ExtensionContext
 * or a spawned `omp`. `index.ts` supplies the OMP-specific lookups (which
 * account is active, its current availability) and drives these functions
 * from its `pi.on(...)` handlers; `command-channel.ts` drains the queue this
 * module builds onto the one transport that exists (see its own doc
 * comment for why there is no second, push-based transport).
 */

/**
 * The brief's Interfaces section names only `"manual"` and `"failover"`, but
 * its own Step 3 also asks for a `credential_disabled` handler that "emit[s]
 * an availability change for the affected account" — a distinct moment from
 * the session's account actually changing (the session can still be
 * nominally on the same account; it has just become unavailable, and may or
 * may not fail over on a later request). Reusing `"failover"` for that would
 * misreport an account as having changed when, at the moment of
 * disablement, it has not. `"unavailable"` is the third reason this module
 * adds for that case. On the wire (`toWireReason` below) it travels as the
 * literal string `"unavailable"`, which Swift's `ProviderAccountChangeReason`
 * does not recognize yet and falls back to `.unknown("unavailable")` for
 * (`OmpKit/Sources/OmpKit/Providers/ProviderAccount.swift:173-188`) — safe
 * and forward-compatible rather than a decode failure.
 */
export type EventReason = "manual" | "failover" | "unavailable";

export interface SequencedEvent {
	providerId: string;
	accountRef: string;
	reason: EventReason;
	sequence: number;
}

export interface EventSequencer {
	next(providerId: string, accountRef: string, reason: EventReason): SequencedEvent;
}

/**
 * Monotonic per-process sequence numbers, starting at 1. One instance is
 * shared by every frame this extension queues AND by `pin_account`'s own
 * `{ account, sequence }` reply (see index.ts) — a manual pin and any event
 * frame it might otherwise generate share one ordering, per this plan's
 * Task 7 dispatch brief. `pin_account` calls `next()` directly rather than
 * also pushing onto the event queue: it already replies to the same client
 * that issued the command, so queuing a duplicate frame would double-report
 * the same change to the one party who already knows about it.
 */
export function createEventSequencer(): EventSequencer {
	let counter = 0;
	return {
		next(providerId, accountRef, reason) {
			counter += 1;
			return { providerId, accountRef, reason, sequence: counter };
		},
	};
}

/**
 * Wire shape of one account-change notification. Matches
 * `OmpKit/Sources/OmpKit/Wire/RpcFrame.swift`'s existing `"provider_account_changed"`
 * frame parser (`ProviderAccountChangedEvent.init(object:)`,
 * `OmpKit/Sources/OmpKit/Providers/ProviderAccount.swift:192-241`) field for
 * field. That Swift type was built against the abandoned fork's native RPC
 * frame of the same name — this plan replaces the fork's OMP-core patch
 * with an unmodified-OMP extension, but the downstream Swift decode target
 * is unchanged, so reusing its exact shape here means whichever task wires
 * the Swift side to this extension's `events` array can decode each entry
 * with code that already exists and is already tested (see
 * `OmpKit/Tests/OmpKitTests/LineTransportTests.swift:392`), instead of
 * needing a new type.
 */
export interface AccountChangedFrame {
	type: "provider_account_changed";
	providerId: string;
	accountRef: string;
	reason: string;
	sequence: number;
}

/**
 * `"failover"` becomes the wire literal `"automaticFailover"` — verified
 * against the already-committed Swift `ProviderAccountChangeReason.init(rawValue:)`
 * (`OmpKit/Sources/OmpKit/Providers/ProviderAccount.swift:180-188`), which
 * switches on the exact strings `"manual"` / `"automaticFailover"` and
 * buckets anything else into `.unknown(String)`. The brief's prose says the
 * reason is `"failover"`; the committed Swift decoder expects
 * `"automaticFailover"`. That decoder is primary-source evidence the
 * brief's shorthand did not carry the wire literal — not a contract this
 * module is free to invent — so the translation follows the committed
 * Swift code, not the brief's prose.
 */
function toWireReason(reason: EventReason): string {
	return reason === "failover" ? "automaticFailover" : reason;
}

/** Builds one wire frame. `reason`/`sequence` normally come from `EventSequencer.next(...)`. */
export function accountChangedFrame(providerId: string, accountRef: string, reason: EventReason, sequence: number): AccountChangedFrame {
	return { type: "provider_account_changed", providerId, accountRef, reason: toWireReason(reason), sequence };
}

/**
 * Coalescing outbound queue: at most one pending frame per `providerId`.
 *
 * The command channel has exactly one transport, and a frame is only
 * deliverable when the client sends its NEXT command (see
 * `command-channel.ts`) — an event firing with no command in flight cannot
 * be pushed, so it waits here. If two events land for the same provider
 * before the client's next turn, only the newer one is kept: for routing
 * purposes only the CURRENT account matters, not the hops it took to get
 * there, and dropping superseded intermediate frames is far better than an
 * unbounded queue if the client goes a long time without sending a command.
 * A `sequence` gap on the client side is the signal that coalescing (or a
 * process restart) happened; the client should treat a gap as "re-list
 * accounts" rather than assume it observed every intermediate state.
 */
export interface EventQueue {
	push(frame: AccountChangedFrame): void;
	drain(): AccountChangedFrame[];
}

export function createEventQueue(): EventQueue {
	const pendingByProvider = new Map<string, AccountChangedFrame>();
	return {
		push(frame) {
			pendingByProvider.set(frame.providerId, frame);
		},
		drain() {
			const frames = [...pendingByProvider.values()].sort((a, b) => a.sequence - b.sequence);
			pendingByProvider.clear();
			return frames;
		},
	};
}
