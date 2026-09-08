# OMP Computer Foreground Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a session-scoped OMP RPC contract that enables the computer tool with a hard `require-handoff` gate before any foreground desktop side effect.

**Architecture:** The existing computer worker remains the only desktop executor. A per-run policy travels from `AgentSession` through `ComputerTool` and `ComputerSupervisor` to the worker; risky operations issue a blocking worker-to-host request, and RPC mode presents that request as a typed extension UI frame before allowing exactly one operation. Cancellation resolves the pending gate as denied and never performs the native call.

**Tech Stack:** Bun, TypeScript, OMP RPC v2, `@oh-my-pi/pi-natives`, Bun test

**Spec:** `docs/superpowers/specs/2026-08-25-computer-use-agent-desktop-design.md`

## Global Constraints

- Integration baseline is OMP 18.0.4 and RPC protocol v2.
- `computer.enabled` remains false by default and is not persisted by this work.
- The new policy is session-scoped and its only enforced value in V1 is `require-handoff`.
- Foreground input, physical pointer movement, window raising, and focus-changing Accessibility actions must suspend before the native side effect.
- Approval authorizes one pending native operation only; it never creates a session-wide exception.
- Abort, Stop, disconnect, timeout, or cancellation must wake and deny a suspended operation.
- OMP's existing point-of-risk approval system remains unchanged and authoritative.
- Do not add a second automation backend or change `@oh-my-pi/pi-natives` APIs.
- Work in a dedicated `codex/` worktree of `can1357/oh-my-pi`; do not edit the globally installed Bun package.

---

## File map

| File | Responsibility |
|---|---|
| `packages/coding-agent/src/tools/computer/protocol.ts` | Clone-safe policy, handoff request, and worker message types |
| `packages/coding-agent/src/tools/computer/worker.ts` | Classify and suspend risky native operations before dispatch |
| `packages/coding-agent/src/tools/computer/supervisor.ts` | Bridge worker handoff requests to the active tool UI and settle replies |
| `packages/coding-agent/src/tools/computer.ts` | Put the session policy into each run and expose handoff metadata in details |
| `packages/coding-agent/src/tools/index.ts` | Declare the narrow foreground-handoff host callback on `ToolSession` |
| `packages/coding-agent/src/session/session-tools.ts` | Store the session-scoped policy beside computer enablement |
| `packages/coding-agent/src/session/agent-session.ts` | Public session methods used by RPC mode |
| `packages/coding-agent/src/modes/rpc/rpc-types.ts` | Typed enable/status commands, state, response, and handoff UI frame |
| `packages/coding-agent/src/modes/rpc/rpc-mode.ts` | Handle policy commands and issue blocking typed UI requests |
| `packages/coding-agent/test/tools/computer.test.ts` | Worker/supervisor enforcement, single-use approval, and cancellation |
| `packages/coding-agent/test/sdk-computer-tool-toggle.test.ts` | Session policy and enable/disable behavior |
| `packages/coding-agent/test/rpc-extension-ui.test.ts` | RPC request/response and disconnect behavior |
| `docs/rpc.md` | Public RPC command and frame contract |

### Task 1: Session Policy and Typed RPC Control

**Files:**
- Modify: `packages/coding-agent/src/tools/computer/protocol.ts`
- Modify: `packages/coding-agent/src/tools/computer.ts`
- Modify: `packages/coding-agent/src/tools/computer/worker.ts`
- Modify: `packages/coding-agent/src/tools/computer/supervisor.ts`
- Modify: `packages/coding-agent/src/tools/index.ts`
- Modify: `packages/coding-agent/src/session/session-tools.ts`
- Modify: `packages/coding-agent/src/session/agent-session.ts`
- Modify: `packages/coding-agent/src/modes/rpc/rpc-types.ts`
- Modify: `packages/coding-agent/src/modes/rpc/rpc-mode.ts`
- Test: `packages/coding-agent/test/sdk-computer-tool-toggle.test.ts`
- Test: `packages/coding-agent/test/tools/computer.test.ts`
- Test: `packages/coding-agent/test/rpc.test.ts`

**Interfaces:**
- Consumes: `AgentSession.setComputerToolEnabled(enabled: boolean): Promise<boolean>` and the current `get_state` RPC response.
- Produces: `ComputerForegroundPolicy`, `AgentSession.setComputerUse(options)`, model-free `ComputerController.probe`, RPC commands `set_computer_use`, `get_computer_use`, and `probe_computer_use`, plus `RpcSessionState.computerUse`.

- [ ] **Step 1: Write failing session-policy tests**

Add cases proving the default is disabled/allow, policy is applied before enablement, and disabling resets no persistent setting:

```ts
test("stores require-handoff only for the current session", async () => {
	const session = await createTestSession();
	expect(session.computerUseState()).toEqual({ enabled: false, foregroundPolicy: "allow" });

	expect(await session.setComputerUse({ enabled: true, foregroundPolicy: "require-handoff" })).toBe(true);
	expect(session.computerUseState()).toEqual({ enabled: true, foregroundPolicy: "require-handoff" });

	expect(await session.setComputerUse({ enabled: false, foregroundPolicy: "require-handoff" })).toBe(true);
	expect(session.settings.get("computer.enabled")).toBe(false);
});

test("capability probe uses the native worker without running model code", async () => {
	const result = await harness.controller.probe(harness.snapshot);
	expect(result.capabilities).toEqual(harness.nativeCapabilities);
	expect(result.captureSucceeded).toBe(false);
	expect(result.backgroundInputSucceeded).toBeNull();
	expect(harness.executedCode).toEqual([]);
});
```

- [ ] **Step 2: Run the focused test and confirm the contract is absent**

Run: `bun test packages/coding-agent/test/sdk-computer-tool-toggle.test.ts packages/coding-agent/test/tools/computer.test.ts`

Expected: FAIL because `setComputerUse`, `computerUseState`, and `ComputerController.probe` do not exist.

- [ ] **Step 3: Add the policy types and session methods**

Use these exact public shapes:

```ts
export type ComputerForegroundPolicy = "allow" | "require-handoff";

export interface ComputerUseState {
	enabled: boolean;
	foregroundPolicy: ComputerForegroundPolicy;
}

// SessionTools
#computerForegroundPolicy: ComputerForegroundPolicy = "allow";

async setComputerUse(options: ComputerUseState): Promise<boolean> {
	this.#computerForegroundPolicy = options.foregroundPolicy;
	return await this.setComputerToolEnabled(options.enabled);
}

computerUseState(): ComputerUseState {
	return {
		enabled: this.getEnabledToolNames().includes("computer"),
		foregroundPolicy: this.#computerForegroundPolicy,
	};
}
```

Expose forwarding methods from `AgentSession`. Add `getComputerForegroundPolicy?: () => ComputerForegroundPolicy` to `ToolSession`, bind it to `SessionTools.computerUseState()`, and add `foregroundPolicy` to `ComputerSessionSnapshot` so `ComputerTool.execute` freezes it for the run.

Add the model-free capability probe on the same worker/native identity:

```ts
export interface ComputerProbeResult {
	capabilities: DesktopCapabilities;
	captureSucceeded: boolean;
	backgroundInputSucceeded: boolean | null;
}

// ComputerWorkerInbound
| {
		type: "probe";
		id: string;
		session: ComputerSessionSnapshot;
		target?: string;
		verificationText?: string;
	}

// ComputerWorkerOutbound
| { type: "probe-result"; id: string; ok: true; result: ComputerProbeResult }
| { type: "probe-result"; id: string; ok: false; error: RunErrorPayload }

// ComputerController
probe(
	snapshot: ComputerSessionSnapshot,
	options?: { target?: string; verificationText?: string; signal?: AbortSignal },
): Promise<ComputerProbeResult>;
```

The worker handles `probe` by calling `#ensureSession(snapshot)`. With no target it returns capabilities only. With a target it captures that window; when `verificationText` is present, it queries the target's first editable text field, uses background `axSetValue`, reads the value back, and reports the comparison. It never raises, focuses, sends foreground input, or runs JavaScript. `ComputerTool.probe()` builds the same frozen snapshot as `execute`, with mutation allowed only for the optional owned-window value check, and `AgentSession.probeComputerUse()` delegates to it. Tests use a fake target and assert the exact capture/query/set/read sequence.

- [ ] **Step 4: Write failing RPC command tests**

Add command-loop assertions using the existing RPC fixture:

```ts
test("set_computer_use returns the effective session state", async () => {
	const response = await rpc.command({
		id: "computer-on",
		type: "set_computer_use",
		enabled: true,
		foregroundPolicy: "require-handoff",
	});
	expect(response).toMatchObject({
		id: "computer-on",
		command: "set_computer_use",
		success: true,
		data: { enabled: true, foregroundPolicy: "require-handoff" },
	});
});
```

- [ ] **Step 5: Run the RPC test and confirm the command is rejected**

Run: `bun test packages/coding-agent/test/rpc.test.ts -t "set_computer_use"`

Expected: FAIL with an unknown command or missing response type.

- [ ] **Step 6: Add typed RPC commands, responses, and state**

Add these unions in `rpc-types.ts` and matching cases in `rpc-mode.ts`:

```ts
| { id?: string; type: "set_computer_use"; enabled: boolean; foregroundPolicy: ComputerForegroundPolicy }
| { id?: string; type: "get_computer_use" }
| { id?: string; type: "probe_computer_use"; target?: string; verificationText?: string }

| {
		id?: string;
		type: "response";
		command: "set_computer_use" | "get_computer_use";
		success: true;
		data: ComputerUseState;
	}
| {
		id?: string;
		type: "response";
		command: "probe_computer_use";
		success: true;
		data: ComputerProbeResult;
	}
```

```ts
case "set_computer_use": {
	if (command.foregroundPolicy !== "allow" && command.foregroundPolicy !== "require-handoff") {
		return error(id, command.type, "Invalid computer foreground policy");
	}
	const available = await session.setComputerUse(command);
	if (command.enabled && !available) return error(id, command.type, "Computer tool is unavailable");
	return success(id, command.type, session.computerUseState());
}
case "get_computer_use":
	return success(id, command.type, session.computerUseState());
case "probe_computer_use":
	return success(id, command.type, await session.probeComputerUse({
		target: command.target,
		verificationText: command.verificationText,
	}));
```

Include `computerUse: session.computerUseState()` in `get_state` so reconnecting clients can reconcile without replaying enablement.

- [ ] **Step 7: Run focused tests**

Run: `bun test packages/coding-agent/test/sdk-computer-tool-toggle.test.ts packages/coding-agent/test/tools/computer.test.ts packages/coding-agent/test/rpc.test.ts`

Expected: PASS.

- [ ] **Step 8: Commit the session contract**

```bash
git add packages/coding-agent/src/tools/computer/protocol.ts packages/coding-agent/src/tools/computer.ts packages/coding-agent/src/tools/computer/worker.ts packages/coding-agent/src/tools/computer/supervisor.ts packages/coding-agent/src/tools/index.ts packages/coding-agent/src/session/session-tools.ts packages/coding-agent/src/session/agent-session.ts packages/coding-agent/src/modes/rpc/rpc-types.ts packages/coding-agent/src/modes/rpc/rpc-mode.ts packages/coding-agent/test/sdk-computer-tool-toggle.test.ts packages/coding-agent/test/tools/computer.test.ts packages/coding-agent/test/rpc.test.ts
git commit -m "feat(computer): add session foreground policy"
```

### Task 2: Pre-Side-Effect Worker Gate

**Files:**
- Modify: `packages/coding-agent/src/tools/computer/protocol.ts`
- Modify: `packages/coding-agent/src/tools/computer/worker.ts`
- Modify: `packages/coding-agent/src/tools/computer/supervisor.ts`
- Modify: `packages/coding-agent/src/tools/computer.ts`
- Test: `packages/coding-agent/test/tools/computer.test.ts`

**Interfaces:**
- Consumes: `ComputerSessionSnapshot.foregroundPolicy: ComputerForegroundPolicy` from Task 1.
- Produces: `ComputerForegroundHandoffRequest`, worker `foreground-handoff`/`foreground-reply` messages, and `ComputerRunOptions.requestForegroundHandoff`.

- [ ] **Step 1: Write failing worker tests for every gated action class**

Use the existing fake native session to assert no native call happens before approval:

```ts
test.each([
	["foreground-input", `await desktop.windows()[0].type("secret", { delivery: "foreground" })`],
	["pointer-move", `await desktop.windows()[0].move(40, 40)`],
	["window-raise", `await desktop.windows()[0].raise()`],
	["accessibility-focus", `await (await desktop.windows()[0].find({ role: "button" }))[0].focus()`],
])("suspends %s before the native side effect", async (_action, code) => {
	const run = harness.run(code, { foregroundPolicy: "require-handoff" });
	const request = await harness.nextForegroundRequest();
	expect(harness.nativeCalls).toEqual([]);
	harness.replyForeground(request.id, false);
	await expect(run).rejects.toThrow("Foreground operation cancelled");
	expect(harness.nativeCalls).toEqual([]);
});
```

- [ ] **Step 2: Run the worker tests and verify they fail before implementation**

Run: `bun test packages/coding-agent/test/tools/computer.test.ts -t "suspends"`

Expected: FAIL because the native calls execute and no foreground request is emitted.

- [ ] **Step 3: Add clone-safe request and message types**

```ts
export type ComputerForegroundAction =
	| "foreground-input"
	| "pointer-move"
	| "window-raise"
	| "accessibility-focus";

export interface ComputerForegroundHandoffRequest {
	id: string;
	runId: string;
	target: string;
	action: ComputerForegroundAction;
	reason: string;
}

// ComputerWorkerOutbound
| { type: "foreground-handoff"; request: ComputerForegroundHandoffRequest }

// ComputerWorkerInbound
| { type: "foreground-reply"; id: string; approved: boolean }
```

- [ ] **Step 4: Implement one-operation gating inside the worker**

Keep approvals in an operation-local promise; never cache them:

```ts
async function requireForegroundHandoff(
	context: ComputerRunContext,
	target: string,
	action: ComputerForegroundAction,
	reason: string,
): Promise<void> {
	if (context.snapshot.foregroundPolicy !== "require-handoff") return;
	const id = `foreground-${Snowflake.next()}`;
	const approved = await context.requestForegroundHandoff({ id, runId: context.runId, target, action, reason });
	throwIfAborted(context.signal);
	if (!approved) throw new ToolError("Foreground operation cancelled");
}
```

Call it immediately before `typeText`, `keyChord`, `click`, `drag`, or `scroll` when `deliveryMode === "foreground"`; always before `moveMouse`, `raiseWindow`, and `axFocus`; and before `axPerform` only for normalized actions `focus` or `raise`. Then call the native method once.

- [ ] **Step 5: Bridge requests through the supervisor**

Extend the controller call without breaking existing factories:

```ts
export interface ComputerRunOptions {
	signal?: AbortSignal;
	requestForegroundHandoff?: (
		request: Omit<ComputerForegroundHandoffRequest, "id" | "runId">,
		signal?: AbortSignal,
	) => Promise<boolean>;
}
```

Track pending foreground requests under the run. On `foreground-handoff`, invoke the callback with the parent signal and send one `foreground-reply`. When no callback exists, reply `approved: false`. Abort and `#terminate` must settle all pending requests as false before clearing the run.

- [ ] **Step 6: Pass the active tool UI callback from `ComputerTool.execute`**

```ts
const run = await this.#controller.run(params.code, timeoutSeconds * 1000, snapshot, {
	signal,
	requestForegroundHandoff: (request, requestSignal) =>
		this.session.requestComputerForegroundHandoff?.(request, requestSignal) ?? Promise.resolve(false),
});
```

Add the callback to `ToolSession`; Task 3 supplies the RPC implementation.

- [ ] **Step 7: Add single-use and abort race tests**

```ts
test("one approval does not authorize the next operation", async () => {
	const run = harness.run(twoForegroundClicks, { foregroundPolicy: "require-handoff" });
	const first = await harness.nextForegroundRequest();
	harness.replyForeground(first.id, true);
	const second = await harness.nextForegroundRequest();
	expect(second.id).not.toBe(first.id);
	harness.abort();
	await expect(run).rejects.toHaveProperty("name", "ToolAbortError");
	expect(harness.nativeCalls).toHaveLength(1);
});
```

- [ ] **Step 8: Run all computer tests**

Run: `bun test packages/coding-agent/test/tools/computer.test.ts`

Expected: PASS, including worker crash/recovery tests.

- [ ] **Step 9: Commit the enforcement gate**

```bash
git add packages/coding-agent/src/tools/computer/protocol.ts packages/coding-agent/src/tools/computer/worker.ts packages/coding-agent/src/tools/computer/supervisor.ts packages/coding-agent/src/tools/computer.ts packages/coding-agent/src/tools/index.ts packages/coding-agent/test/tools/computer.test.ts
git commit -m "feat(computer): gate foreground desktop actions"
```

### Task 3: Blocking RPC Handoff UI

**Files:**
- Modify: `packages/coding-agent/src/modes/rpc/rpc-types.ts`
- Modify: `packages/coding-agent/src/modes/rpc/rpc-mode.ts`
- Modify: `packages/coding-agent/src/session/agent-session.ts`
- Test: `packages/coding-agent/test/rpc-extension-ui.test.ts`
- Test: `packages/coding-agent/test/tools/computer.test.ts`

**Interfaces:**
- Consumes: `ToolSession.requestComputerForegroundHandoff` and `ComputerForegroundHandoffRequest` from Task 2.
- Produces: extension UI method `computer_foreground_handoff` with response `{ approved: boolean }`.

- [ ] **Step 1: Write the failing RPC frame test**

```ts
test("foreground handoff is blocking and carries sanitized operation context", async () => {
	const pending = requestComputerForegroundHandoff({
		target: "window:42",
		action: "foreground-input",
		reason: "The application rejected background keyboard delivery",
	});
	const frame = await rpc.nextFrame();
	expect(frame).toMatchObject({
		type: "extension_ui_request",
		method: "computer_foreground_handoff",
		target: "window:42",
		action: "foreground-input",
	});
	expect(await Promise.race([pending, Promise.resolve("still-pending")])).toBe("still-pending");
	rpc.send({ type: "extension_ui_response", id: frame.id, approved: true });
	await expect(pending).resolves.toBe(true);
});
```

- [ ] **Step 2: Run the focused extension UI test**

Run: `bun test packages/coding-agent/test/rpc-extension-ui.test.ts -t "foreground handoff"`

Expected: FAIL because the method and response shape are unknown.

- [ ] **Step 3: Add typed request and response variants**

```ts
export interface RpcComputerForegroundHandoffRequest {
	type: "extension_ui_request";
	id: string;
	method: "computer_foreground_handoff";
	target: string;
	action: ComputerForegroundAction;
	reason: string;
}

export type RpcComputerForegroundHandoffResponse = {
	type: "extension_ui_response";
	id: string;
	approved: boolean;
};
```

Add the request to `RpcExtensionUIRequest` and the response to `RpcExtensionUIResponse`.

- [ ] **Step 4: Implement the blocking request through the existing pending map**

```ts
function requestRpcComputerForegroundHandoff(
	pendingRequests: Map<string, PendingExtensionRequest>,
	output: RpcOutput,
	request: Omit<ComputerForegroundHandoffRequest, "id" | "runId">,
	signal?: AbortSignal,
): Promise<boolean> {
	return requestRpcDialog(
		pendingRequests,
		output,
		{ signal },
		false,
		{ method: "computer_foreground_handoff", ...request },
		response => "approved" in response && response.approved === true,
	);
}
```

Bind it to the session's `ToolSession.requestComputerForegroundHandoff` when RPC mode starts. Non-RPC hosts must default to denial unless they explicitly provide the same callback.

- [ ] **Step 5: Test cancellation, disconnect, and late approval**

```ts
test("disconnect denies the foreground operation and ignores a late approval", async () => {
	const operation = rpc.requestForegroundHandoff();
	const frame = await rpc.nextFrame();
	rpc.disconnect();
	await expect(operation).resolves.toBe(false);
	expect(() => rpc.resolvePending(frame.id, { approved: true })).not.toThrow();
	expect(nativeDesktop.calls).toEqual([]);
});
```

- [ ] **Step 6: Run extension and computer suites**

Run: `bun test packages/coding-agent/test/rpc-extension-ui.test.ts packages/coding-agent/test/tools/computer.test.ts`

Expected: PASS.

- [ ] **Step 7: Commit the RPC bridge**

```bash
git add packages/coding-agent/src/modes/rpc/rpc-types.ts packages/coding-agent/src/modes/rpc/rpc-mode.ts packages/coding-agent/src/session/agent-session.ts packages/coding-agent/test/rpc-extension-ui.test.ts packages/coding-agent/test/tools/computer.test.ts
git commit -m "feat(rpc): bridge computer foreground handoff"
```

### Task 4: Public Contract and OMP Verification

**Files:**
- Modify: `docs/rpc.md`
- Modify: `docs/tools/computer.md`
- Test: `packages/coding-agent/test/rpc.test.ts`
- Test: `packages/coding-agent/test/rpc-extension-ui.test.ts`
- Test: `packages/coding-agent/test/tools/computer.test.ts`

**Interfaces:**
- Consumes: all Task 1-3 public commands, state, and extension UI frames.
- Produces: a versioned contract that 10x can feature-detect and implement.

- [ ] **Step 1: Add an end-to-end RPC contract test**

```ts
test("require-handoff remains enabled across get_state and disables cleanly", async () => {
	await rpc.command({ type: "set_computer_use", enabled: true, foregroundPolicy: "require-handoff" });
	const probe = await rpc.command({ type: "probe_computer_use" });
	expect(probe.data.capabilities).toMatchObject({ backend: expect.any(String) });
	const state = await rpc.command({ type: "get_state" });
	expect(state.data.computerUse).toEqual({ enabled: true, foregroundPolicy: "require-handoff" });
	const disabled = await rpc.command({
		type: "set_computer_use",
		enabled: false,
		foregroundPolicy: "require-handoff",
	});
	expect(disabled.data.enabled).toBe(false);
});
```

- [ ] **Step 2: Run the end-to-end test**

Run: `bun test packages/coding-agent/test/rpc.test.ts -t "require-handoff remains"`

Expected: PASS.

- [ ] **Step 3: Document exact wire examples**

Add these examples to `docs/rpc.md`:

```json
{"id":"1","type":"set_computer_use","enabled":true,"foregroundPolicy":"require-handoff"}
{"id":"1","type":"response","command":"set_computer_use","success":true,"data":{"enabled":true,"foregroundPolicy":"require-handoff"}}
{"id":"2","type":"probe_computer_use","target":"window:42","verificationText":"10x-probe-a1b2"}
{"id":"2","type":"response","command":"probe_computer_use","success":true,"data":{"capabilities":{"backend":"macos","capturePermission":"granted","inputPermission":"granted","axPermission":"granted"},"captureSucceeded":true,"backgroundInputSucceeded":true}}
{"type":"extension_ui_request","id":"h1","method":"computer_foreground_handoff","target":"window:42","action":"foreground-input","reason":"Background keyboard delivery is unavailable"}
{"type":"extension_ui_response","id":"h1","approved":true}
```

Document that old RPC servers lack `computerUse` in `get_state` and reject `set_computer_use`; clients must treat that as best-effort background mode, never as the non-interruption guarantee.

- [ ] **Step 4: Document computer-tool semantics**

In `docs/tools/computer.md`, state that `require-handoff` gates foreground delivery, physical pointer movement, `raise()`, `focus()`, and AX focus/raise actions before execution; approval is single-operation; and cancellation denies without a native call.

- [ ] **Step 5: Run formatting, types, focused tests, then the package suite**

Run:

```bash
bunx biome check --write packages/coding-agent/src/tools/computer packages/coding-agent/src/tools/computer.ts packages/coding-agent/src/tools/index.ts packages/coding-agent/src/session/session-tools.ts packages/coding-agent/src/session/agent-session.ts packages/coding-agent/src/modes/rpc/rpc-types.ts packages/coding-agent/src/modes/rpc/rpc-mode.ts packages/coding-agent/test/tools/computer.test.ts packages/coding-agent/test/sdk-computer-tool-toggle.test.ts packages/coding-agent/test/rpc-extension-ui.test.ts packages/coding-agent/test/rpc.test.ts
bun run --cwd packages/coding-agent check:types
bun test packages/coding-agent/test/tools/computer.test.ts packages/coding-agent/test/sdk-computer-tool-toggle.test.ts packages/coding-agent/test/rpc-extension-ui.test.ts packages/coding-agent/test/rpc.test.ts
bun run --cwd packages/coding-agent test
```

Expected: every command exits 0.

- [ ] **Step 6: Commit documentation and verification**

```bash
git add docs/rpc.md docs/tools/computer.md
git commit -m "docs(computer): define foreground handoff contract"
```

## OMP completion gate

- [ ] `get_state.computerUse` and `get_computer_use` report the same effective state.
- [ ] A denied or cancelled request produces zero corresponding native calls.
- [ ] One approval produces exactly one corresponding native call.
- [ ] A second foreground operation emits a second request.
- [ ] Abort, worker termination, and RPC disconnect release every waiter.
- [ ] Existing `allow` behavior and existing approvals remain unchanged.
- [ ] The coding-agent type check and complete package test suite pass.
- [ ] The OMP change is released or 10x is pointed at a locally built OMP containing it before the complete safety contract is claimed.
