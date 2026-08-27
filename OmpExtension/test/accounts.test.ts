import { expect, test } from "bun:test";
import { activeAccountRef, listAccounts, pinAccount, reapplyPin, removeAccount, shouldReapplyPin, toSafeAccount } from "../src/accounts";
import type { AccountAuthStorage, AccountCommandContext } from "../src/accounts";

const row = (over: Record<string, unknown> = {}) => ({
	credentialId: 7,
	position: 0,
	email: "a@example.com",
	accountId: "acc-1",
	access: "sk-secret",
	refresh: "refresh-secret",
	// `active` mirrors stock `OAuthAccountSummary.active`: "True when this
	// account is the session-sticky OAuth credential requested by
	// listOAuthAccounts" (auth-storage.ts:905). Defaults to false so existing
	// fixtures that never mention it don't accidentally register as active.
	active: false,
	...over,
});

test("a safe account carries no credential material", () => {
	const safe = toSafeAccount("anthropic", row(), 0);
	const serialized = JSON.stringify(safe);
	expect(serialized).not.toContain("sk-secret");
	expect(serialized).not.toContain("refresh-secret");
	expect(serialized).not.toContain("credentialId");
	expect(safe.displayLabel).toBe("a@example.com");
	expect(safe.connectionOrder).toBe(0);
	// Allowlist, not a blocklist: a future field added to SafeAccount without
	// updating this test should fail here, not slip through because it isn't
	// one of the four named leaks above.
	expect(Object.keys(safe).sort()).toEqual(["accountRef", "providerId", "displayLabel", "detailLabel", "connectionOrder", "availability"].sort());
});

test("the account ref matches omp's credential pin hash", async () => {
	// Asserts against the fixtures Task 3 generated from OMP's own
	// credentialPinHash. Do not import OMP at test time — that worktree is
	// scratch and may be gone.
	const fixtures = (await Bun.file(
		new URL("../../Tests/TenXAppTests/Fixtures/credential-pin-hashes.json", import.meta.url),
	).json()) as { input: Record<string, string>; hash: string | null }[];
	const expected = fixtures.find(
		f => f.input.provider === "anthropic" && f.input.accountId === "acc-1" && f.input.email === "a@example.com" && !f.input.orgId && !f.input.projectId,
	);
	expect(expected?.hash).toBeTruthy();
	expect(toSafeAccount("anthropic", row(), 0).accountRef).toBe(expected!.hash);
});

test("enterprise labels are redacted to a safe detail", () => {
	const safe = toSafeAccount("anthropic", row({ orgName: "Acme Internal Ops", enterpriseUrl: "https://sso.acme.test" }), 0);
	expect(JSON.stringify(safe)).not.toContain("sso.acme.test");
	expect(safe.detailLabel).toBe("Acme Internal Ops");
});

test("a row with neither accountId nor email produces no accountRef", () => {
	const safe = toSafeAccount("anthropic", row({ accountId: undefined, email: undefined }), 2);
	expect(safe.accountRef).toBeUndefined();
	expect(safe.displayLabel).toBe("Account 3");
});

// --- fakes for the ctx-shaped, ExtensionContext-independent handler tests ---

interface FakeCredentialBlock {
	credentialId: number;
	providerKey: string;
	blockScope: string;
	blockedUntilMs: number;
}

interface FakeAuthStorage extends AccountAuthStorage {
	rows: ReturnType<typeof row>[];
	addBlock(block: { credentialId: number; providerKey: string; blockScope: string }): void;
}

function makeAuthStorage(initial: ReturnType<typeof row>[]): FakeAuthStorage {
	const blocks: FakeCredentialBlock[] = [];
	return {
		rows: [...initial],
		listOAuthAccounts(_provider, _sessionId) {
			return this.rows.map((r, index) => ({ ...r, position: index }));
		},
		pinSessionOAuthAccount(_provider, sessionId, credentialId) {
			if (!sessionId) return false;
			return this.rows.some(r => r.credentialId === credentialId);
		},
		async removeCredential(_provider, credentialId) {
			const before = this.rows.length;
			this.rows = this.rows.filter(r => r.credentialId !== credentialId);
			return this.rows.length < before;
		},
		listCredentialBlocks(credentialIds) {
			return blocks.filter(b => credentialIds.includes(b.credentialId));
		},
		// test-only helper, not part of AccountAuthStorage
		addBlock(block) {
			blocks.push({ ...block, blockedUntilMs: Date.now() + 60_000 });
		},
	};
}

function makeCtx(
	authStorage: AccountAuthStorage,
	options: { provider?: string; idle?: boolean; sessionId?: string } = {},
): AccountCommandContext {
	return {
		modelRegistry: { authStorage },
		sessionManager: { getSessionId: () => options.sessionId ?? "session-1" },
		model: options.provider === undefined ? undefined : { provider: options.provider },
		isIdle: () => options.idle ?? true,
	};
}

test("listAccounts maps every stored row and classifies availability", async () => {
	const authStorage = makeAuthStorage([
		row({ credentialId: 1, email: "one@example.com" }),
		row({ credentialId: 2, email: "two@example.com", accountId: "acc-2" }),
	]);
	authStorage.addBlock({
		credentialId: 2,
		providerKey: "anthropic:oauth",
		blockScope: "",
	});
	const ctx = makeCtx(authStorage, { provider: "anthropic" });

	const accounts = await listAccounts(ctx, "anthropic");

	expect(accounts).toHaveLength(2);
	expect(accounts[0]?.displayLabel).toBe("one@example.com");
	expect(accounts[0]?.availability).toBe("available");
	expect(accounts[1]?.availability).toBe("unavailable");
});

test("listAccounts omits rows that have no addressable accountRef", async () => {
	const authStorage = makeAuthStorage([row({ credentialId: 1, accountId: undefined, email: undefined })]);
	const ctx = makeCtx(authStorage, { provider: "anthropic" });

	const accounts = await listAccounts(ctx, "anthropic");

	expect(accounts).toHaveLength(0);
});

test("pinAccount pins the resolved credential and resolves to its safe account", async () => {
	const authStorage = makeAuthStorage([row({ credentialId: 9, email: "pin-me@example.com" })]);
	const ctx = makeCtx(authStorage, { provider: "anthropic", idle: true, sessionId: "sess-42" });
	const ref = toSafeAccount("anthropic", row({ credentialId: 9, email: "pin-me@example.com" }), 0).accountRef;
	if (!ref) throw new Error("test setup: expected a ref");

	const account = await pinAccount(ctx, "anthropic", ref);

	expect(account.accountRef).toBe(ref);
	expect(account.providerId).toBe("anthropic");
	expect(account.displayLabel).toBe("pin-me@example.com");
	expect(JSON.stringify(account)).not.toContain("credentialId");
});

test("pinAccount rejects with the exact string streaming while the session is streaming", async () => {
	const authStorage = makeAuthStorage([row({ credentialId: 9, email: "pin-me@example.com" })]);
	const ctx = makeCtx(authStorage, { provider: "anthropic", idle: false });
	const ref = toSafeAccount("anthropic", row({ credentialId: 9, email: "pin-me@example.com" }), 0).accountRef;
	if (!ref) throw new Error("test setup: expected a ref");

	await expect(pinAccount(ctx, "anthropic", ref)).rejects.toThrow("streaming");
});

test("pinAccount rejects a provider that is not the session's current provider", async () => {
	const authStorage = makeAuthStorage([row({ credentialId: 9, email: "pin-me@example.com" })]);
	const ctx = makeCtx(authStorage, { provider: "openai-codex", idle: true });
	const ref = toSafeAccount("anthropic", row({ credentialId: 9, email: "pin-me@example.com" }), 0).accountRef;
	if (!ref) throw new Error("test setup: expected a ref");

	await expect(pinAccount(ctx, "anthropic", ref)).rejects.toThrow();
});

test("pinAccount rejects a stale accountRef", async () => {
	const authStorage = makeAuthStorage([row({ credentialId: 9, email: "pin-me@example.com" })]);
	const ctx = makeCtx(authStorage, { provider: "anthropic", idle: true });

	await expect(pinAccount(ctx, "anthropic", "not-a-real-ref")).rejects.toThrow();
});

test("removeAccount removes the resolved credential and returns the remaining safe accounts", async () => {
	const gone = row({ credentialId: 1, email: "gone@example.com" });
	const stays = row({ credentialId: 2, email: "stays@example.com" });
	const authStorage = makeAuthStorage([gone, stays]);
	const ctx = makeCtx(authStorage, { provider: "anthropic" });
	const ref = toSafeAccount("anthropic", gone, 0).accountRef;
	if (!ref) throw new Error("test setup: expected a ref");

	const result = await removeAccount(ctx, "anthropic", ref);

	expect(result.removed).toBe(true);
	expect(result.accounts).toHaveLength(1);
	expect(result.accounts[0]?.displayLabel).toBe("stays@example.com");
});

test("removeAccount reports removed:false for an already-gone credential without throwing", async () => {
	const authStorage = makeAuthStorage([row({ credentialId: 1, email: "solo@example.com" })]);
	const ctx = makeCtx(authStorage, { provider: "anthropic" });
	const ref = toSafeAccount("anthropic", row({ credentialId: 1, email: "solo@example.com" }), 0).accountRef;
	if (!ref) throw new Error("test setup: expected a ref");
	// Simulate the row vanishing between resolution and removal (e.g. a
	// concurrent /session logout) by making removeCredential report failure
	// while still leaving the row listable — removeAccount must not throw.
	authStorage.removeCredential = async () => false;

	const result = await removeAccount(ctx, "anthropic", ref);

	expect(result.removed).toBe(false);
});

// --- activeAccountRef: Task 7's only source of "current account" independent of any event payload ---

test("activeAccountRef resolves the ref of the session-sticky row", () => {
	const authStorage = makeAuthStorage([
		row({ credentialId: 1, email: "one@example.com", active: false }),
		row({ credentialId: 2, email: "two@example.com", accountId: "acc-2", active: true }),
	]);

	const ref = activeAccountRef(authStorage, "anthropic", "session-1");

	expect(ref).toBe(toSafeAccount("anthropic", row({ credentialId: 2, email: "two@example.com", accountId: "acc-2" }), 0).accountRef);
});

test("activeAccountRef returns undefined when no row is marked active", () => {
	const authStorage = makeAuthStorage([row({ credentialId: 1, email: "one@example.com", active: false })]);

	expect(activeAccountRef(authStorage, "anthropic", "session-1")).toBeUndefined();
});

test("activeAccountRef returns undefined when the active row has no addressable ref", () => {
	const authStorage = makeAuthStorage([row({ credentialId: 1, accountId: undefined, email: undefined, active: true })]);

	expect(activeAccountRef(authStorage, "anthropic", "session-1")).toBeUndefined();
});

// --- reapplyPin: the unguarded enforcement path (before_provider_request fires mid-request, never idle) ---

test("reapplyPin re-pins while the session is streaming, unlike pinAccount", async () => {
	const authStorage = makeAuthStorage([row({ credentialId: 9, email: "pin-me@example.com" })]);
	const ctx = makeCtx(authStorage, { provider: "anthropic", idle: false, sessionId: "sess-1" });
	const ref = toSafeAccount("anthropic", row({ credentialId: 9, email: "pin-me@example.com" }), 0).accountRef;
	if (!ref) throw new Error("test setup: expected a ref");

	const account = await reapplyPin(ctx, "anthropic", ref);

	expect(account?.accountRef).toBe(ref);
});

test("reapplyPin resolves to undefined instead of throwing for a stale ref", async () => {
	const authStorage = makeAuthStorage([row({ credentialId: 9, email: "pin-me@example.com" })]);
	const ctx = makeCtx(authStorage, { provider: "anthropic", idle: false });

	const account = await reapplyPin(ctx, "anthropic", "not-a-real-ref");

	expect(account).toBeUndefined();
});

// --- shouldReapplyPin: the anti-wedge predicate ---
//
// `pinSessionOAuthAccount` does not itself check availability (stock
// auth-storage.ts:5793 — "Normal auth retry and usage-limit handling may
// still route around an unavailable account"), so nothing stops enforcement
// from re-pinning a blocked credential except this check. Skipping it would
// wedge every session that legitimately failed over: each
// before_provider_request would force the session back onto the dead
// credential, guaranteeing a failed request before OMP's own rotation
// undoes it again, forever.

test("shouldReapplyPin refuses an unavailable pinned account", () => {
	expect(shouldReapplyPin("unavailable")).toBe(false);
});

test("shouldReapplyPin refuses when the pinned account is no longer listed at all", () => {
	expect(shouldReapplyPin(undefined)).toBe(false);
});

test("shouldReapplyPin allows re-pinning an available or a merely rate-limited (limited) account", () => {
	expect(shouldReapplyPin("available")).toBe(true);
	expect(shouldReapplyPin("limited")).toBe(true);
});
