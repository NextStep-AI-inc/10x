# OMP Provider Account RPC Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose safe account metadata, batched account usage, exact session pinning, exact account removal, and authoritative account-change state through OMP protocol v2 without exposing credentials.

**Architecture:** Extend the existing RPC union and `rpc-mode` dispatcher with account commands that delegate to `AuthStorage` and the existing usage adapters. Keep account references opaque at the wire boundary, persist pins through the existing `credential_pin` mechanism, and emit sequenced per-session account changes from the same session event stream already consumed by RPC clients.

**Tech Stack:** TypeScript, Bun, ArkType-compatible runtime validation, OMP coding-agent RPC protocol v2, existing OAuth `AuthStorage`, existing provider usage adapters

**Spec:** `10x/docs/superpowers/specs/2026-08-26-multi-account-provider-routing-design.md`

## Global Constraints

- Work in a fresh OMP worktree. Read OMP `AGENTS.md` before editing; `packages/coding-agent/` is the primary package.
- Do not add a credential store, expose credential ids, tokens, provider payloads, filesystem paths, or raw identity beyond safe labels.
- `accountRef` is an opaque durable row reference, stable across token refresh and storage reorder, and validated against `providerId` on pin and removal.
- Use protocol-v2 response envelopes. Older OMP versions must continue returning their existing unsupported-command response for unknown account commands.
- Reuse `AuthStorage.listOAuthAccounts`, `pinSessionOAuthAccount`, `removeCredential`, existing credential-health/retry rotation, and the adapters behind `omp usage --json`.
- Automatic failover occurs only after existing retries, only for existing eligible credential/quota/account-availability classes, and affects one session without changing any application primary preference.
- `provider_account_changed.sequence` is monotonic within one session process. Manual response/event duplication is expected and must be deduplicable by clients.
- No new dependencies. No prompt strings. Do not use `any`, `ReturnType<>`, dynamic imports, `console.*` in RPC/runtime paths, `tsc`, or `npx tsc`.
- Run focused Bun tests first, then `bun check`, then the coding-agent full suite. Never edit generated catalog files.
- OMP source paths below are relative to the OMP repository, not this 10x repository.

## File Map

- Modify `packages/coding-agent/src/modes/rpc/rpc-types.ts`: wire commands, responses, state extension, account summaries, usage values, and account-change frame.
- Create `packages/coding-agent/src/modes/rpc/provider-account-rpc.ts`: validate account arguments, map stored OAuth rows to safe summaries, and adapt account usage without leaking credentials.
- Modify `packages/coding-agent/src/modes/rpc/rpc-mode.ts`: dispatch four account commands and include active accounts in `get_state`.
- Modify `packages/coding-agent/src/security/auth.ts`: expose the existing rotation result through a narrow callback used to publish authoritative active-account changes.
- Modify `packages/coding-agent/src/session/agent-session.ts`: own per-provider active account refs, sequence changes, persist exact pins, and emit manual/failover events.
- Modify `packages/coding-agent/src/commands/usage.ts`: extract/reuse the existing per-credential usage adapter entry point for batched RPC usage.
- Modify `packages/coding-agent/test/rpc-mode.test.ts`: contract-level command, state, event, compatibility, and redaction coverage.
- Modify `packages/coding-agent/test/security/auth.test.ts`: retry exhaustion and eligible-failure failover coverage.
- Modify `packages/coding-agent/test/credential-pin.test.ts`: exact pin persistence, resume, stale reference, provider mismatch, and storage reorder coverage.
- Create `packages/coding-agent/test/provider-account-rpc.test.ts`: metadata, usage, removal, duplicate-label, partial failure, and secret-redaction coverage.

---

### Task 1: Define the Additive Protocol-v2 Account Contract

**Files:**
- Modify: `packages/coding-agent/src/modes/rpc/rpc-types.ts`
- Modify: `packages/coding-agent/test/rpc-mode.test.ts`

**Interfaces:**
- Produces: `ProviderAccountSummary`, `ProviderAccountUsage`, `ProviderAccountUsageWindow`, `ProviderAccountChangedFrame`.
- Produces commands: `list_provider_accounts`, `get_provider_account_usage`, `set_session_provider_account`, `remove_provider_account`.
- Extends: `RpcSessionState.activeProviderAccounts: Record<string, string>`.

- [ ] **Step 1: Add failing wire-shape tests**

Add tests which pass exact input frames through the existing RPC input harness and assert the echoed command name, success shape, and absence of credential fields:

```ts
test("provider account commands use protocol-v2 response envelopes", async () => {
	const responses = await runRpcFrames([
		{ id: "list", type: "list_provider_accounts", providerId: "openai-codex" },
		{ id: "usage", type: "get_provider_account_usage", providerId: "openai-codex" },
		{ id: "pin", type: "set_session_provider_account", providerId: "openai-codex", accountRef: "acct_A" },
		{ id: "remove", type: "remove_provider_account", providerId: "openai-codex", accountRef: "acct_A" },
	]);
	expect(responses.map(response => [response.id, response.type, response.command])).toEqual([
		["list", "response", "list_provider_accounts"],
		["usage", "response", "get_provider_account_usage"],
		["pin", "response", "set_session_provider_account"],
		["remove", "response", "remove_provider_account"],
	]);
});
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
cd packages/coding-agent
bun test test/rpc-mode.test.ts --test-name-pattern "provider account commands"
```

Expected: FAIL because the account commands are not members of `RpcCommand` and fall through to unsupported-command handling.

- [ ] **Step 3: Add exact public types**

Add these shapes to `rpc-types.ts` and include the commands/responses in their existing discriminated unions:

```ts
export type ProviderAccountAvailability = "available" | "limited" | "unavailable";

export interface ProviderAccountSummary {
	providerId: string;
	accountRef: string;
	displayLabel: string;
	detailLabel?: string;
	connectionOrder: number;
	availability: ProviderAccountAvailability;
	isActiveForSession?: boolean;
}

export interface ProviderAccountUsageWindow {
	id: string;
	label: string;
	duration?: { value: number; unit: "minute" | "hour" | "day" | "week" | "month" | "year" };
	sourceIndex: number;
	remainingFraction?: number;
	resetsAt?: string;
	status?: string;
}

export interface ProviderAccountUsage {
	providerId: string;
	accountRef: string;
	refreshedAt: string;
	usageWindows: ProviderAccountUsageWindow[];
}

export interface ProviderAccountChangedFrame {
	type: "provider_account_changed";
	providerId: string;
	accountRef: string;
	reason: "manual" | "automaticFailover";
	sequence: number;
}
```

Use response data exactly as follows: list returns `{ accounts }`; usage returns `{ accounts: ProviderAccountUsage[] }`; pin returns `{ account, sequence }`; removal returns `{ removed, accounts }`. Add `activeProviderAccounts: Record<string, string>` to `RpcSessionState`.

- [ ] **Step 4: Verify types and focused test compile**

Run:

```bash
cd packages/coding-agent
bun check
bun test test/rpc-mode.test.ts --test-name-pattern "provider account commands"
```

Expected: type checking passes; focused test still fails only because dispatcher implementations are absent.

- [ ] **Step 5: Commit the contract types**

```bash
git add packages/coding-agent/src/modes/rpc/rpc-types.ts packages/coding-agent/test/rpc-mode.test.ts
git commit -m "feat(rpc): define provider account contract"
```

---

### Task 2: Map OAuth Rows to Opaque Safe Account Summaries

**Files:**
- Create: `packages/coding-agent/src/modes/rpc/provider-account-rpc.ts`
- Create: `packages/coding-agent/test/provider-account-rpc.test.ts`
- Modify: `packages/coding-agent/src/modes/rpc/rpc-mode.ts`

**Interfaces:**
- Consumes: `AuthStorage.listOAuthAccounts(providerId, sessionId)`.
- Produces: `listProviderAccounts(authStorage, providerId, sessionId, activeAccountRef)`.
- Produces: `resolveProviderAccount(authStorage, providerId, accountRef)` for pin/removal validation.

- [ ] **Step 1: Write failing metadata, identity, and redaction tests**

Use stored rows with duplicate emails, reordered storage, a refreshed token, and one unavailable credential. Assert stable refs, stable connection order, separate duplicate rows, and serialized output without secret-shaped keys:

```ts
test("account summaries preserve opaque row identity without credential material", async () => {
	const accounts = await listProviderAccounts(authStorage, "openai-codex", "session-1", "acct_B");
	expect(accounts.map(account => [account.accountRef, account.displayLabel, account.connectionOrder])).toEqual([
		["acct_A", "same@example.com", 0],
		["acct_B", "same@example.com", 1],
	]);
	expect(accounts[1]?.isActiveForSession).toBe(true);
	const wire = JSON.stringify(accounts);
	expect(wire).not.toMatch(/accessToken|refreshToken|apiKey|credentialId|tokenValue/i);
});
```

- [ ] **Step 2: Run focused tests and verify RED**

```bash
cd packages/coding-agent
bun test test/provider-account-rpc.test.ts
```

Expected: FAIL because `provider-account-rpc.ts` and its exports do not exist.

- [ ] **Step 3: Implement the safe mapper and strict resolver**

Create a focused module whose public surface is:

```ts
export function listProviderAccounts(
	authStorage: AuthStorage,
	providerId: string,
	sessionId?: string,
	activeAccountRef?: string,
): ProviderAccountSummary[];

export function resolveProviderAccount(
	authStorage: AuthStorage,
	providerId: string,
	accountRef: string,
): { credentialId: string; summary: ProviderAccountSummary };
```

Map only the safest available label fields in this precedence: email, account id, project, organization/workspace, enterprise host, then `Account N`. Use the durable stored row id only to derive `accountRef`; never return the backing `credentialId` property. Reject blank providers/refs, missing refs, and provider mismatches with stable RPC error codes `invalid_provider`, `stale_account_ref`, and `provider_account_mismatch`.

- [ ] **Step 4: Dispatch account listing**

Add a `list_provider_accounts` case in `rpc-mode.ts`:

```ts
case "list_provider_accounts": {
	const accounts = listProviderAccounts(
		session.modelRegistry.authStorage,
		command.providerId,
		session.sessionId,
		session.activeProviderAccount(command.providerId),
	);
	return success(id, command.type, { accounts });
}
```

Keep the no-session provider RPC behavior by allowing `sessionId` and active state to be absent in the dependency used by that mode.

- [ ] **Step 5: Verify and commit safe account listing**

```bash
cd packages/coding-agent
bun test test/provider-account-rpc.test.ts
bun test test/rpc-mode.test.ts --test-name-pattern "list_provider_accounts"
bun check
git add src/modes/rpc/provider-account-rpc.ts src/modes/rpc/rpc-mode.ts test/provider-account-rpc.test.ts
git commit -m "feat(rpc): list safe provider accounts"
```

Expected: all focused tests and type checks pass.

---

### Task 3: Reuse Usage Adapters for Batched Account Usage

**Files:**
- Modify: `packages/coding-agent/src/commands/usage.ts`
- Modify: `packages/coding-agent/src/modes/rpc/provider-account-rpc.ts`
- Modify: `packages/coding-agent/src/modes/rpc/rpc-mode.ts`
- Modify: `packages/coding-agent/test/provider-account-rpc.test.ts`

**Interfaces:**
- Produces: `loadProviderAccountUsage(providerId, accounts)` using the same adapter selection and quota interpretation as `omp usage --json`.
- RPC result: `{ accounts: ProviderAccountUsage[] }` in connection order.

- [ ] **Step 1: Add failing batched and partial-failure tests**

```ts
test("batched usage retains healthy siblings when one adapter call fails", async () => {
	const result = await loadProviderAccountUsage(fixtureDeps, "openai-codex", fixtureAccounts);
	expect(result.map(account => account.accountRef)).toEqual(["acct_A"]);
	expect(result[0]?.usageWindows[0]?.remainingFraction).toBe(0.42);
});
```

Also assert duration normalization, source order, ISO-8601 timestamps, clamping to `0...1`, and absence of safe identity metadata from usage responses.

- [ ] **Step 2: Verify RED**

```bash
cd packages/coding-agent
bun test test/provider-account-rpc.test.ts --test-name-pattern "batched usage"
```

Expected: FAIL because the reusable adapter entry point does not exist.

- [ ] **Step 3: Extract the minimum reusable usage entry point**

Keep CLI output formatting in `commands/usage.ts`, but expose a typed function that accepts already-resolved account rows and returns normalized adapter results. Do not duplicate provider switch logic or quota parsing. The RPC mapper converts the adapter output to `ProviderAccountUsageWindow`; a failed account is omitted from the usage response while its independent metadata summary remains available, so 10x can preserve the account and show `Usage unavailable` without inventing quota data.

- [ ] **Step 4: Add the RPC dispatcher case**

```ts
case "get_provider_account_usage": {
	const accounts = listProviderAccounts(authStorage, command.providerId, session.sessionId);
	const usage = await loadProviderAccountUsage(command.providerId, accounts);
	return success(id, command.type, { accounts: usage });
}
```

Ensure the adapter receives credentials internally via resolved storage rows, never through the returned summary.

- [ ] **Step 5: Verify and commit batched usage**

```bash
cd packages/coding-agent
bun test test/provider-account-rpc.test.ts
bun test test/rpc-mode.test.ts --test-name-pattern "get_provider_account_usage"
bun check
git add src/commands/usage.ts src/modes/rpc/provider-account-rpc.ts src/modes/rpc/rpc-mode.ts test/provider-account-rpc.test.ts
git commit -m "feat(rpc): expose batched provider account usage"
```

---

### Task 4: Pin Exact Accounts and Publish Sequenced State

**Files:**
- Modify: `packages/coding-agent/src/session/agent-session.ts`
- Modify: `packages/coding-agent/src/modes/rpc/rpc-mode.ts`
- Modify: `packages/coding-agent/test/credential-pin.test.ts`
- Modify: `packages/coding-agent/test/rpc-mode.test.ts`

**Interfaces:**
- Produces on `AgentSession`: `activeProviderAccount(providerId)` and `setProviderAccount(providerId, accountRef)`.
- Produces event: `provider_account_changed` with `reason: "manual"` and increasing `sequence`.
- Extends `get_state.activeProviderAccounts`.

- [ ] **Step 1: Add failing exact-pin, resume, and sequence tests**

Exercise the public RPC command, then inspect the persisted session entries and emitted frames:

```ts
expect(pinResponse.data).toMatchObject({ account: { accountRef: "acct_B" }, sequence: 1 });
expect(events).toContainEqual({
	type: "provider_account_changed",
	providerId: "openai-codex",
	accountRef: "acct_B",
	reason: "manual",
	sequence: 1,
});
expect(resumedState.activeProviderAccounts).toEqual({ "openai-codex": "acct_B" });
```

Add negative tests proving a stale ref or provider mismatch does not write `credential_pin`, change state, or emit an event.

- [ ] **Step 2: Verify RED**

```bash
cd packages/coding-agent
bun test test/credential-pin.test.ts test/rpc-mode.test.ts --test-name-pattern "provider account"
```

Expected: FAIL because account state and the pin command are absent.

- [ ] **Step 3: Add one authoritative session method**

Implement `setProviderAccount` as the only manual-pin path: resolve the opaque ref, call existing `pinSessionOAuthAccount(providerId, sessionId, credentialId)`, confirm persistence, update the in-memory map, increment the session sequence, and emit one account-change frame. Restore the map from durable pin state during session initialization. Do not create a second session-file representation.

- [ ] **Step 4: Dispatch pinning and extend get_state**

```ts
case "set_session_provider_account": {
	const result = await session.setProviderAccount(command.providerId, command.accountRef);
	return success(id, command.type, result);
}
case "get_state": {
	// retain every existing field
	return success(id, "get_state", { ...state, activeProviderAccounts: session.activeProviderAccounts() });
}
```

The response and event may report the same sequence/account ref; this is intentional.

- [ ] **Step 5: Verify and commit exact pinning**

```bash
cd packages/coding-agent
bun test test/credential-pin.test.ts
bun test test/rpc-mode.test.ts --test-name-pattern "provider account"
bun check
git add src/session/agent-session.ts src/modes/rpc/rpc-mode.ts test/credential-pin.test.ts test/rpc-mode.test.ts
git commit -m "feat(rpc): pin exact provider accounts"
```

---

### Task 5: Emit Automatic Failover from Existing Retry Rotation

**Files:**
- Modify: `packages/coding-agent/src/security/auth.ts`
- Modify: `packages/coding-agent/src/session/agent-session.ts`
- Modify: `packages/coding-agent/test/security/auth.test.ts`
- Modify: `packages/coding-agent/test/rpc-mode.test.ts`

**Interfaces:**
- Consumes: existing credential rotation and retry classification.
- Produces: an account-selection callback/result only when effective credential changes.
- Produces event: `provider_account_changed` with `reason: "automaticFailover"`.

- [ ] **Step 1: Add failing failover invariants**

Create tests proving: retries on the preferred account are exhausted first; quota/auth/account-availability classes rotate; validation/model/tool/ordinary server errors do not; no sibling terminates once; only the affected session changes; and the resulting pin survives restart.

```ts
expect(attemptedAccounts).toEqual(["acct_A", "acct_A", "acct_B"]);
expect(accountEvents).toEqual([{
	type: "provider_account_changed",
	providerId: "openai-codex",
	accountRef: "acct_B",
	reason: "automaticFailover",
	sequence: 3,
}]);
expect(unrelatedSession.activeProviderAccount("openai-codex")).toBe("acct_A");
```

- [ ] **Step 2: Verify RED**

```bash
cd packages/coding-agent
bun test test/security/auth.test.ts test/rpc-mode.test.ts --test-name-pattern "automatic failover"
```

Expected: FAIL because credential rotation does not publish the selected account to session RPC state.

- [ ] **Step 3: Surface rotation without changing policy**

Add a narrow callback or typed result at the existing successful sibling-selection point. `AgentSession` translates the selected credential to its opaque account ref, persists the existing pin, updates only its map, increments sequence, and emits `automaticFailover`. Do not add error-text parsing, retry counters, ranking, or migration back to a recovered primary.

- [ ] **Step 4: Verify conflict and exhaustion behavior**

Run the focused tests and add assertions that repeated exhaustion stops, the current session remains on its backup after recovery, and a fresh session can select the recovered preferred account through normal eligibility.

- [ ] **Step 5: Commit failover attribution**

```bash
cd packages/coding-agent
bun test test/security/auth.test.ts test/rpc-mode.test.ts --test-name-pattern "automatic failover"
bun check
git add src/security/auth.ts src/session/agent-session.ts test/security/auth.test.ts test/rpc-mode.test.ts
git commit -m "feat(rpc): publish provider account failover"
```

---

### Task 6: Remove One Exact Account and Clean Account Health

**Files:**
- Modify: `packages/coding-agent/src/modes/rpc/provider-account-rpc.ts`
- Modify: `packages/coding-agent/src/modes/rpc/rpc-mode.ts`
- Modify: `packages/coding-agent/test/provider-account-rpc.test.ts`
- Modify: `packages/coding-agent/test/security/auth.test.ts`

**Interfaces:**
- Consumes: `AuthStorage.removeCredential(providerId, credentialId)`.
- Produces RPC result: `{ removed: boolean, accounts: ProviderAccountSummary[] }`.

- [ ] **Step 1: Add failing exact-removal tests**

Cover middle row, last row, remote auth storage, stale ref, provider mismatch, duplicate labels, and cleanup of credential health state. Assert a duplicate sibling remains when only one exact ref is removed.

- [ ] **Step 2: Verify RED**

```bash
cd packages/coding-agent
bun test test/provider-account-rpc.test.ts --test-name-pattern "remove provider account"
```

Expected: FAIL because `remove_provider_account` is unsupported.

- [ ] **Step 3: Implement validated exact removal**

Resolve the opaque ref and provider ownership first, delegate to `removeCredential`, clear only that row's health state through the existing auth-storage cleanup path, then list refreshed safe summaries. Do not attempt to coordinate other processes or 10x sessions inside OMP.

- [ ] **Step 4: Dispatch removal and verify response redaction**

```ts
case "remove_provider_account": {
	const result = await removeProviderAccount(authStorage, command.providerId, command.accountRef);
	return success(id, command.type, result);
}
```

Assert the full serialized response contains neither the credential id nor token fields.

- [ ] **Step 5: Verify and commit removal**

```bash
cd packages/coding-agent
bun test test/provider-account-rpc.test.ts test/security/auth.test.ts
bun check
git add src/modes/rpc/provider-account-rpc.ts src/modes/rpc/rpc-mode.ts test/provider-account-rpc.test.ts test/security/auth.test.ts
git commit -m "feat(rpc): remove exact provider accounts"
```

---

### Task 7: Verify Compatibility, Redaction, and the Full OMP Package

**Files:**
- Modify only if a verification failure exposes a contract defect in files already owned by Tasks 1-6.

**Interfaces:**
- Verifies the complete contract consumed by the companion 10x plan.

- [ ] **Step 1: Run focused contract suites**

```bash
cd packages/coding-agent
bun test test/provider-account-rpc.test.ts test/credential-pin.test.ts test/security/auth.test.ts test/rpc-mode.test.ts
```

Expected: all account contract, pin, removal, failover, compatibility, and redaction tests pass.

- [ ] **Step 2: Run static checks**

```bash
cd packages/coding-agent
bun check
```

Expected: Biome and TypeScript checks pass without `any`, inline imports, or new lint suppression.

- [ ] **Step 3: Run the full coding-agent suite**

```bash
cd packages/coding-agent
bun test
```

Expected: full suite passes. Record the executed test count and any pre-existing skips.

- [ ] **Step 4: Inspect representative wire output**

Capture list, usage, pin, get-state, change-event, and removal frames from the test harness. Search them for `token`, `secret`, `credentialId`, known fixture token values, filesystem paths, and raw provider payload fields. Expected: no matches except negative test descriptions.

- [ ] **Step 5: Commit only verification-driven corrections**

If no corrections were needed, do not create an empty commit. Otherwise:

```bash
git add packages/coding-agent/src packages/coding-agent/test
git commit -m "test(rpc): verify provider account contract"
```
