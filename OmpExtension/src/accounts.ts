import type { OAuthAccountSummary, StoredCredentialBlock } from "@oh-my-pi/pi-coding-agent";

/**
 * The exact subset of `AuthStorage` these commands call. Narrower than the
 * real class on purpose: it documents precisely what this module touches,
 * and lets tests fake it completely instead of stubbing ~50 unrelated
 * methods. A real `AuthStorage` instance (reached via
 * `ctx.modelRegistry.authStorage`) satisfies this structurally.
 */
export interface AccountAuthStorage {
	listOAuthAccounts(provider: string, sessionId?: string): OAuthAccountSummary[];
	pinSessionOAuthAccount(provider: string, sessionId: string, credentialId: number): boolean;
	removeCredential(provider: string, credentialId: number): Promise<boolean>;
	listCredentialBlocks(credentialIds: readonly number[]): StoredCredentialBlock[];
}

/**
 * The slice of `ExtensionContext` these commands need. Stock's
 * `ExtensionContext` (verified against `b4e8e856a`
 * `packages/coding-agent/src/extensibility/extensions/types.ts`, the literal
 * object built by `runner.ts#createContext()`) has no `session` member — so,
 * unlike `AgentSession.listCurrentProviderOAuthAccounts` /
 * `pinCurrentProviderOAuthAccount`, everything here goes through the
 * publicly exposed `modelRegistry.authStorage`, `sessionManager`, `model`,
 * and `isIdle()` instead. `!ctx.isIdle()` is stock's own `isStreaming`:
 * `ExtensionContextActions.isIdle` is wired as `() => !this.isStreaming` at
 * both `agent-session.ts:6052` and `:9009`.
 */
export interface AccountCommandContext {
	modelRegistry: { authStorage: AccountAuthStorage };
	sessionManager: { getSessionId(): string };
	model: { provider: string } | undefined;
	isIdle(): boolean;
}

export type AccountAvailability = "available" | "limited" | "unavailable";

export interface SafeAccount {
	accountRef: string | undefined;
	providerId: string;
	displayLabel: string;
	detailLabel?: string;
	connectionOrder: number;
	availability: AccountAvailability;
}

/** Identity fields `credentialPinHash` reads off a stored OAuth row. */
interface CredentialPinIdentity {
	accountId?: string;
	email?: string;
	orgId?: string;
	projectId?: string;
}

/**
 * The account ref contract with the Swift side. Verbatim port of stock
 * OMP's `credentialPinHash` (`b4e8e856a`
 * `packages/coding-agent/src/session/credential-pin.ts:44`) — sha256 of the
 * five-field tuple, bare lowercase hex, `undefined` when both `accountId`
 * and `email` are absent. Swift computes the identical value in
 * `App/Providers/ProviderAccountRef.swift`; Task 3's fixtures
 * (`Tests/TenXAppTests/Fixtures/credential-pin-hashes.json`) pin the parity.
 * Never imported from OMP at runtime — reimplemented here so this module has
 * no dependency on the scratch OMP worktree.
 */
function credentialPinHash(provider: string, identity: CredentialPinIdentity): string | undefined {
	if (!identity.accountId && !identity.email) return undefined;
	const key = [provider, identity.accountId ?? "", identity.email ?? "", identity.orgId ?? "", identity.projectId ?? ""].join("\0");
	return new Bun.CryptoHasher("sha256").update(key).digest("hex");
}

function trimmed(value: string | undefined): string | undefined {
	const text = value?.trim();
	return text && text.length > 0 ? text : undefined;
}

/**
 * Ported from the fork's `provider-account-rpc.ts` `displayLabel`
 * (`d65d2247f`), with the enterprise-URL fallback removed: redaction is a
 * hard requirement here, and a URL-derived label (even just its host) is
 * only ever a "best effort" leak away from showing up in a UI or a log.
 * Falls back to a positional label when nothing else identifies the row.
 */
function displayLabel(row: CredentialPinIdentity & { orgName?: string }, index: number): string {
	return trimmed(row.email) ?? trimmed(row.accountId) ?? trimmed(row.projectId) ?? trimmed(row.orgName) ?? trimmed(row.orgId) ?? `Account ${index + 1}`;
}

/**
 * The `detailLabel` candidate chain, in order: `email → projectId → orgName
 * → orgId`. Deliberately wider than any written spec called for — recorded
 * here so a future reader sees why rather than suspecting drift.
 *
 * `detailLabel` (below) walks this list and returns the first candidate that
 * is NOT the value that already won `displayLabel` — so the two labels are
 * guaranteed to differ whenever a second identifying field exists. That is
 * what makes two accounts sharing the same email address distinguishable in
 * the UI, an explicit product requirement, not an accident of iteration
 * order.
 *
 * Every field in this chain is safe to render: no URLs. `enterpriseUrl` (and
 * any other endpoint-shaped field) is deliberately excluded, here and in
 * `displayLabel` — ported from the fork's `safeLabels`, minus its
 * `enterpriseHost(...)` fallback, so redaction holds unconditionally rather
 * than only when a non-URL field happens to be available.
 */
function safeLabels(row: CredentialPinIdentity & { orgName?: string }): string[] {
	const labels: string[] = [];
	const add = (value: string | undefined): void => {
		const text = trimmed(value);
		if (!text || labels.includes(text)) return;
		labels.push(text);
	};
	add(row.email);
	add(row.projectId);
	add(row.orgName);
	add(row.orgId);
	return labels;
}

/** Ported from the fork's `detailLabel`: first safe label that isn't already the display label. */
function detailLabel(row: CredentialPinIdentity & { orgName?: string }, display: string): string | undefined {
	for (const candidate of safeLabels(row)) {
		if (candidate !== display) return candidate;
	}
	return undefined;
}

/**
 * Maps a stored OAuth row to the six fields the Swift side is allowed to
 * see. Never spreads `row` — every field is picked explicitly — so adding a
 * field to `OAuthAccountSummary` upstream can never leak it here by
 * accident. `availability` defaults to `"available"` so the 3-arg brief
 * tests (which don't classify blocks) still get a valid value; `listAccounts`
 * / `removeAccount` pass the real classification.
 */
export function toSafeAccount(
	providerId: string,
	row: OAuthAccountSummary,
	index: number,
	availability: AccountAvailability = "available",
): SafeAccount {
	const display = displayLabel(row, index);
	return {
		accountRef: credentialPinHash(providerId, row),
		providerId,
		displayLabel: display,
		detailLabel: detailLabel(row, display),
		connectionOrder: row.position,
		availability,
	};
}

function isAddressable(account: SafeAccount): account is SafeAccount & { accountRef: string } {
	return account.accountRef !== undefined;
}

/**
 * Classifies each credential id as available / limited / unavailable.
 * Ported from the fork's `credentialAvailability`, against stock's real
 * `listCredentialBlocks` (`auth-storage.ts:6774`) and `StoredCredentialBlock`
 * shape (`providerKey`, `blockScope`, `auth-storage.ts:168-179`): an
 * unscoped block (`blockScope === ""`) blocks the credential entirely
 * ("unavailable"); a scoped block (e.g. one model tier) only narrows it
 * ("limited"), and never downgrades an already-"unavailable" verdict.
 */
function credentialAvailability(authStorage: AccountAuthStorage, providerId: string, credentialIds: readonly number[]): Map<number, AccountAvailability> {
	const availability = new Map<number, AccountAvailability>();
	for (const block of authStorage.listCredentialBlocks(credentialIds)) {
		if (block.providerKey !== `${providerId}:oauth`) continue;
		if (block.blockScope === "") {
			availability.set(block.credentialId, "unavailable");
		} else if (availability.get(block.credentialId) !== "unavailable") {
			availability.set(block.credentialId, "limited");
		}
	}
	return availability;
}

/**
 * Lists safe accounts for `providerId`, classified by availability. Rows
 * whose `accountRef` is `undefined` (no `accountId` and no `email` — the row
 * can never be resolved back by `pinAccount`/`removeAccount`) are dropped:
 * Swift's `ProviderAccountSummary.accountRef` is a non-optional `String`, so
 * including one would fail the whole array's decode, not just that entry.
 */
function listSafeAccounts(authStorage: AccountAuthStorage, providerId: string, sessionId: string): SafeAccount[] {
	const rows = authStorage.listOAuthAccounts(providerId, sessionId);
	const availability = credentialAvailability(
		authStorage,
		providerId,
		rows.map(row => row.credentialId),
	);
	return rows.map((row, index) => toSafeAccount(providerId, row, index, availability.get(row.credentialId) ?? "available")).filter(isAddressable);
}

/** `listAccounts(ctx, providerId)` per the brief: list, then map every row through `toSafeAccount`. */
export async function listAccounts(ctx: AccountCommandContext, providerId: string): Promise<SafeAccount[]> {
	return listSafeAccounts(ctx.modelRegistry.authStorage, providerId, ctx.sessionManager.getSessionId());
}

/**
 * Resolves the session's current session-sticky account for `providerId`,
 * via `OAuthAccountSummary.active` — "True when this account is the
 * session-sticky OAuth credential requested by `listOAuthAccounts`" (stock
 * `b4e8e856a` `packages/ai/src/auth-storage.ts:905`). This is Task 7's only
 * way to answer "what account is this session on right now": none of the
 * four `ExtensionAPI` events it subscribes to carry account identity in
 * their payload (`retry_fallback_applied`/`succeeded` carry model selector
 * strings, `before_provider_request` carries an opaque `payload: unknown`,
 * and `credential_disabled` carries only `provider` + `disabledCause`) — see
 * `task-7-report.md` for the full verification trail. Returns `undefined`
 * when no row is active, or the active row has no addressable ref (no
 * `accountId`/`email` — the same condition `listSafeAccounts` already
 * filters on).
 */
export function activeAccountRef(authStorage: AccountAuthStorage, providerId: string, sessionId: string): string | undefined {
	const rows = authStorage.listOAuthAccounts(providerId, sessionId);
	const active = rows.find(row => row.active);
	if (!active) return undefined;
	return toSafeAccount(providerId, active, active.position).accountRef;
}

/**
 * Resolves an `accountRef` back to its stored row by recomputing
 * `credentialPinHash` per row until one matches — the ref carries no
 * `credentialId` itself (that's exactly the redaction the ref exists for).
 * Deliberately does not port the fork's cross-provider mismatch detection
 * (`resolveProviderOAuthRow`'s two-error-code branch): that's RPC-plumbing
 * the fork built for its own error-code contract, which this plan replaces;
 * a plain not-found error is enough for Task 1's generic `{ok:false,error}`
 * channel path.
 */
function resolveAccountRow(rows: readonly OAuthAccountSummary[], providerId: string, accountRef: string): OAuthAccountSummary {
	const match = rows.find(row => credentialPinHash(providerId, row) === accountRef);
	if (!match) throw new Error(`No account found for ref "${accountRef}" on provider "${providerId}"`);
	return match;
}

/**
 * The unguarded core both `pinAccount` (command path) and `reapplyPin`
 * (Task 7's `before_provider_request` enforcement path) share: resolve
 * `accountRef` back to its stored row, pin it, and resolve to its
 * `SafeAccount`. Split out because the two callers need different guards —
 * see `reapplyPin`'s doc comment for why enforcement cannot reuse
 * `pinAccount` itself.
 */
async function pinResolvedAccount(ctx: AccountCommandContext, providerId: string, accountRef: string): Promise<SafeAccount> {
	const authStorage = ctx.modelRegistry.authStorage;
	const sessionId = ctx.sessionManager.getSessionId();
	const row = resolveAccountRow(authStorage.listOAuthAccounts(providerId, sessionId), providerId, accountRef);
	const pinned = authStorage.pinSessionOAuthAccount(providerId, sessionId, row.credentialId);
	if (!pinned) throw new Error(`Unable to pin account for provider "${providerId}"`);
	const availability = credentialAvailability(authStorage, providerId, [row.credentialId]);
	return toSafeAccount(providerId, row, row.position, availability.get(row.credentialId) ?? "available");
}

/**
 * `pinAccount(ctx, providerId, accountRef)` per the brief. Reproduces stock
 * `AgentSession.pinCurrentProviderOAuthAccount` (`agent-session.ts:9151`)
 * exactly — same guard order, same underlying call — just through the
 * context surface that's actually public:
 *
 *     const provider = this.model?.provider;
 *     if (!provider || this.isStreaming) return false;
 *     return authStorage.pinSessionOAuthAccount(provider, this.sessionId, credentialId);
 *
 * Two differences from stock, both per the regenerated brief: (1) `providerId`
 * is caller-supplied rather than always "the current model's provider", so a
 * mismatch is rejected explicitly rather than silently pinning the wrong
 * provider; (2) the streaming rejection is the exact string `"streaming"`
 * (not a bare `false`) so 10x can distinguish "queue and retry" from every
 * other failure. Provider mismatch is checked first: unlike streaming, it is
 * not a transient condition retrying would ever resolve.
 *
 * Resolves to the pinned account's `SafeAccount` (not a bare boolean): the
 * surviving Swift contract, `ProviderAccountSession.setProviderAccount(
 * providerID:accountRef:) async throws -> SetSessionProviderAccountResult`
 * (`App/Providers/ProviderAccountCoordinator.swift:34`), consumes
 * `result.account.providerID`/`.accountRef` to emit a
 * `ProviderAccountChangedEvent` (`ProviderAccountCoordinator.swift:624-643`)
 * — a bare boolean would force the caller to re-list just to find the
 * account it already pinned. `index` for the returned `toSafeAccount` call
 * is `row.position`: harmless even though `displayLabel`'s index-based
 * fallback (`Account ${index+1}`) can never actually fire here, since a row
 * that resolved at all is guaranteed to have `accountId` or `email` (that's
 * the same condition `credentialPinHash` requires to produce the `accountRef`
 * this function was called with). `sequence` is deliberately not part of
 * this result at this layer — `index.ts` extends it to `{ account, sequence }`
 * using Task 7's shared sequencer.
 */
export async function pinAccount(ctx: AccountCommandContext, providerId: string, accountRef: string): Promise<SafeAccount> {
	if (providerId !== ctx.model?.provider) {
		throw new Error(`Cannot pin account: "${providerId}" is not the session's current provider`);
	}
	if (!ctx.isIdle()) throw new Error("streaming");
	return pinResolvedAccount(ctx, providerId, accountRef);
}

/**
 * Re-applies a previously pinned account without `pinAccount`'s command-path
 * guards. Used exclusively by Task 7's `before_provider_request`
 * enforcement, which by definition fires while a provider request is being
 * assembled — i.e. never idle, `pinAccount`'s `!ctx.isIdle()` guard would
 * throw `"streaming"` on every single enforcement attempt if reused as-is —
 * and may run after `ctx.model` has already moved past the provider being
 * enforced for one turn's tail requests. Resolves to `undefined` instead of
 * throwing when the ref no longer resolves (stale/removed) or the pin call
 * itself fails: enforcement is a best-effort background correction, not a
 * client-facing command, so there is no channel to report a failure through
 * and swallowing it here is correct rather than crashing the provider
 * request it is guarding.
 */
export async function reapplyPin(ctx: AccountCommandContext, providerId: string, accountRef: string): Promise<SafeAccount | undefined> {
	try {
		return await pinResolvedAccount(ctx, providerId, accountRef);
	} catch {
		return undefined;
	}
}

/**
 * Whether enforcement should re-pin, given the pinned account's current
 * classification (`undefined` when it is no longer listed at all). Refusing
 * on `"unavailable"` is what keeps enforcement from fighting OMP's own
 * failover: `pinSessionOAuthAccount` does not check availability itself
 * (stock `auth-storage.ts:5793` — "Normal auth retry and usage-limit
 * handling may still route around an unavailable account"), so nothing else
 * stops a naive re-pin from forcing the session back onto a credential OMP
 * just legitimately rotated away from, guaranteeing another failed request
 * next turn and wedging the session in a pin/fail/rotate loop forever.
 */
export function shouldReapplyPin(pinnedAvailability: AccountAvailability | undefined): boolean {
	return pinnedAvailability !== undefined && pinnedAvailability !== "unavailable";
}

export interface RemoveAccountResult {
	removed: boolean;
	accounts: SafeAccount[];
}

/**
 * `removeAccount(ctx, providerId, accountRef)` per the brief. Ordering and
 * partial-failure handling ported from the fork's `removeProviderAccount`:
 * resolve the row FIRST (a stale/unknown ref fails before touching storage),
 * remove it, THEN re-list so the returned accounts reflect the
 * post-removal state. `removeCredential` returning `false` (row already
 * gone, or a remote delete that reported failure) is not an error — it is
 * reported as `removed: false` alongside the current account list, matching
 * the existing Swift `RemoveProviderAccountResult`
 * (`OmpKit/Sources/OmpKit/Providers/ProviderAccount.swift:269`,
 * `{ removed: Bool, accounts: [ProviderAccountSummary] }`).
 */
export async function removeAccount(ctx: AccountCommandContext, providerId: string, accountRef: string): Promise<RemoveAccountResult> {
	const authStorage = ctx.modelRegistry.authStorage;
	const sessionId = ctx.sessionManager.getSessionId();
	const row = resolveAccountRow(authStorage.listOAuthAccounts(providerId, sessionId), providerId, accountRef);
	const removed = await authStorage.removeCredential(providerId, row.credentialId);
	const accounts = listSafeAccounts(authStorage, providerId, sessionId);
	return { removed, accounts };
}
