import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { activeAccountRef, listAccounts, pinAccount, reapplyPin, removeAccount, shouldReapplyPin } from "./src/accounts";
import type { AccountCommandContext } from "./src/accounts";
import { openCommandChannel } from "./src/command-channel";
import { accountChangedFrame, createEventQueue, createEventSequencer } from "./src/events";
import type { EventReason } from "./src/events";

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null;
}

function requireString(params: unknown, key: string): string {
	const value = isRecord(params) ? params[key] : undefined;
	if (typeof value !== "string" || value.length === 0) {
		throw new Error(`Missing or invalid "${key}" parameter`);
	}
	return value;
}

export default function (pi: ExtensionAPI) {
	// One sequencer, one queue, shared by the whole process — matches
	// createEventSequencer's documented "monotonic per-process" contract.
	// OMP loads one extension instance per session process (Task 1's real-omp
	// test spawns a fresh `omp` per test, and every session gets its own
	// process), so "per process" and "per session" coincide here.
	const sequencer = createEventSequencer();
	const eventQueue = createEventQueue();

	// Extension-local memory of what the USER most recently pinned per
	// provider (via the `pin_account` command) — deliberately distinct from
	// OMP's own session-sticky pointer (`OAuthAccountSummary.active`, read
	// through `activeAccountRef`), which moves on its own the moment OMP
	// fails over. `before_provider_request` below diffs the two: a mismatch
	// against THIS map is "the user's pin is not in force," which is worth
	// correcting; a mismatch would mean nothing at all if this were instead
	// derived from `active` itself, since `active` and the pin can never
	// differ that way.
	const pinnedAccountByProvider = new Map<string, string>();

	// The last `active` account observed per provider, refreshed by every
	// handler below (including after a successful pin/re-pin, so our own
	// corrections never look like drift on the next check). This is how
	// `before_provider_request` notices "the session-sticky account moved
	// since I last looked" without a dedicated OMP event for it: stock's
	// actual same-provider sibling-account rotation,
	// `AuthStorage.rotateSessionCredential` (`packages/ai/src/auth-storage.ts:6410`),
	// has no corresponding entry in the stock `ExtensionEvent` union — see
	// task-7-report.md for the full verification trail. `retry_fallback_applied`/
	// `retry_fallback_succeeded` are wired below too, per the brief, but they
	// fire for a different OMP feature (a configured model/provider fallback
	// chain) and will not fire for this.
	const lastSeenActiveRef = new Map<string, string>();

	function queueAccountChangedFrame(providerId: string, accountRef: string, reason: EventReason): void {
		const numbered = sequencer.next(providerId, accountRef, reason);
		eventQueue.push(accountChangedFrame(numbered.providerId, numbered.accountRef, numbered.reason, numbered.sequence));
	}

	/** Reads the session's current account and queues a frame for it, tagged `reason`. Used by both retry-fallback events. */
	function reportCurrentAccount(ctx: AccountCommandContext, providerId: string, reason: EventReason): void {
		const accountRef = activeAccountRef(ctx.modelRegistry.authStorage, providerId, ctx.sessionManager.getSessionId());
		if (!accountRef) return;
		lastSeenActiveRef.set(providerId, accountRef);
		queueAccountChangedFrame(providerId, accountRef, reason);
	}

	// `ExtensionHandler<E> = (event: E, ctx: ExtensionContext) => ...` — the UI
	// context lives on the second parameter, not on the session_start event
	// (which is just `{ type: "session_start" }`).
	pi.on("session_start", async (_event, ctx) => {
		// Not `void openCommandChannel(...)`: that discarded the returned
		// promise outright, so a rejection from inside the loop — e.g.
		// `ctx.ui.input()` itself throwing because the client disconnected —
		// surfaced as an unhandled promise rejection instead of a caught,
		// logged failure. `openCommandChannel` never retries on its own
		// (Task 10b final fix, Finding 1's fold-in item), so this session's
		// command channel is done either way; the `.catch` only replaces a
		// silent, uncaught death with one that leaves a trace.
		openCommandChannel(
			ctx.ui,
			async command => {
				switch (command.command) {
					case "ping":
						return "pong";
					case "hello":
						return { contractVersion: 1 };
					case "list_accounts":
						return { accounts: await listAccounts(ctx, requireString(command.params, "providerId")) };
					case "pin_account": {
						const providerId = requireString(command.params, "providerId");
						const accountRef = requireString(command.params, "accountRef");
						const account = await pinAccount(ctx, providerId, accountRef);
						pinnedAccountByProvider.set(providerId, accountRef);
						lastSeenActiveRef.set(providerId, accountRef);
						// Numbered on the shared sequencer so this reply and any
						// event frame share one monotonic ordering, but NOT also
						// pushed onto eventQueue: this reply already tells the one
						// client that asked, so queuing a duplicate "manual" frame
						// would double-report the same change to the same party.
						const numbered = sequencer.next(providerId, accountRef, "manual");
						return { account, sequence: numbered.sequence };
					}
					case "remove_account": {
						const providerId = requireString(command.params, "providerId");
						const accountRef = requireString(command.params, "accountRef");
						const result = await removeAccount(ctx, providerId, accountRef);
						// A removed pin can no longer be enforced; leaving it in the
						// map would have before_provider_request try to re-pin a
						// credential that no longer exists on every future request.
						if (result.removed && pinnedAccountByProvider.get(providerId) === accountRef) {
							pinnedAccountByProvider.delete(providerId);
						}
						return result;
					}
					default:
						throw new Error(`Unknown command: ${command.command}`);
				}
			},
			() => true,
			() => eventQueue.drain(),
		).catch(error => {
			console.error("[tenx-provider-accounts] command channel ended:", error);
		});
	});

	// Registered once per process, not inside session_start: if session_start
	// ever fired more than once for the same process, nesting these `pi.on`
	// calls inside it would stack a second copy of each handler and
	// double-emit every frame. Sequencer/queue/maps above are already
	// process-scoped closures, so top-level registration is the only change
	// needed to keep "one handler per event" true.

	// Fires when OMP switches to a *configured* fallback model/provider
	// after repeated failures (stock `turn-recovery.ts` / `session-advisors.ts`)
	// — a different feature from same-provider sibling-account rotation, but
	// still a real, OMP-driven account change worth reporting. Neither event's
	// payload carries account identity (`from`/`to`/`model` are model selector
	// strings, verified at stock `shared-events.ts:270-280`), so both handlers
	// re-read "the session's current account" via ctx rather than the event.
	pi.on("retry_fallback_applied", async (_event, ctx) => {
		const providerId = ctx.model?.provider;
		if (providerId) reportCurrentAccount(ctx, providerId, "failover");
	});
	pi.on("retry_fallback_succeeded", async (_event, ctx) => {
		const providerId = ctx.model?.provider;
		if (providerId) reportCurrentAccount(ctx, providerId, "failover");
	});

	// Stock's `CredentialDisabledEvent` carries only `provider` +
	// `disabledCause` (types.ts:833-838) — no credentialId or accountRef.
	// Attribute it to this session's active account for that provider, and
	// only report it when that account is now actually classified
	// unavailable: `credential_disabled` can fire for a credential this
	// session isn't even using (a different stored account, or a startup
	// probe — runner.ts's own comment calls this out), and reporting THIS
	// session's active account as unavailable in that case would be false.
	pi.on("credential_disabled", async (event, ctx) => {
		const providerId = event.provider;
		const accountRef = activeAccountRef(ctx.modelRegistry.authStorage, providerId, ctx.sessionManager.getSessionId());
		if (!accountRef) return;
		const accounts = await listAccounts(ctx, providerId);
		const active = accounts.find(a => a.accountRef === accountRef);
		if (!active || active.availability !== "unavailable") return;
		lastSeenActiveRef.set(providerId, accountRef);
		queueAccountChangedFrame(providerId, accountRef, "unavailable");
	});

	// Fires before every provider request. Does two independent things:
	//
	// 1. Detects OMP's own sibling-account rotation. There is no dedicated
	//    event for `rotateSessionCredential` (see the module-level comment on
	//    `lastSeenActiveRef`), so this is the only observable signal: the
	//    session-sticky account moved since the last time this handler (or a
	//    retry-fallback handler, or a successful pin) looked, and it wasn't
	//    caused by a `pin_account` command (which updates `lastSeenActiveRef`
	//    itself, so it can never appear as drift here).
	//
	// 2. Enforces a recorded pin: if the user pinned an account for this
	//    provider and OMP has since drifted off it, re-apply the pin — UNLESS
	//    the pinned account is currently unavailable, in which case OMP
	//    almost certainly drifted for exactly that reason, and re-pinning
	//    would fight a legitimate failover. `pinSessionOAuthAccount` does not
	//    check availability itself (stock `auth-storage.ts:5793`), so
	//    `shouldReapplyPin`'s availability check is the only thing standing
	//    between this handler and a pin/fail/rotate loop that wedges the
	//    session. Once re-applied, `lastSeenActiveRef` is updated immediately
	//    (not left for the next tick to observe), so this handler's own
	//    correction is never mistaken for OMP-driven drift and double-reported
	//    as a second failover frame.
	//
	// Must never return a value: `emitBeforeProviderRequest` (stock
	// `runner.ts`) replaces the outgoing provider request payload with any
	// non-undefined handler result, and this handler has no payload to give
	// back — an accidental return here would silently corrupt every request.
	pi.on("before_provider_request", async (_event, ctx) => {
		const providerId = ctx.model?.provider;
		if (!providerId) return;
		const authStorage = ctx.modelRegistry.authStorage;
		const sessionId = ctx.sessionManager.getSessionId();
		const observedRef = activeAccountRef(authStorage, providerId, sessionId);
		const previousRef = lastSeenActiveRef.get(providerId);
		if (observedRef) lastSeenActiveRef.set(providerId, observedRef);

		if (previousRef !== undefined && observedRef !== undefined && observedRef !== previousRef) {
			queueAccountChangedFrame(providerId, observedRef, "failover");
		}

		const pinnedRef = pinnedAccountByProvider.get(providerId);
		if (!pinnedRef || observedRef === pinnedRef) return;
		const accounts = await listAccounts(ctx, providerId);
		const pinnedAccount = accounts.find(a => a.accountRef === pinnedRef);
		if (!shouldReapplyPin(pinnedAccount?.availability)) return;
		const reapplied = await reapplyPin(ctx, providerId, pinnedRef);
		if (reapplied) lastSeenActiveRef.set(providerId, pinnedRef);
	});
}
