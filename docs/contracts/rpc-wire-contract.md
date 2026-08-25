<!-- Extracted 2026-08-24 from oh-my-pi v18.0.4 checkout (github.com/can1357/oh-my-pi). Regenerate on omp version bumps. -->

# OMP RPC Wire Contract

Reference for a Swift Codable port of the oh-my-pi (`@oh-my-pi/pi-coding-agent` v18.0.4) headless RPC protocol. Source of truth: `packages/coding-agent/src/modes/rpc/` (`rpc-types.ts`, `rpc-frame.ts`, `rpc-mode.ts`, `rpc-messages.ts`, `rpc-input.ts`, `rpc-client.ts`, `host-tools.ts`, `host-uris.ts`). All quotes below are verbatim from that checkout.

Transport model (from the `rpc-types.ts` header comment):

```ts
/**
 * RPC protocol types for headless operation.
 *
 * Commands are sent as JSON lines on stdin.
 * Responses and events are emitted as JSON lines on stdout.
 */
```

Frames are newline-delimited JSON objects (JSONL). Every frame is discriminated by a string `type` field. Command ordering: `bash` is dispatched in the background; all other commands are serialized. Per the dispatch doc comment in `rpc-mode.ts`: "Response correlation is preserved via each command's `id`; ordering across concurrent commands is not guaranteed and clients MUST match on `id`."

---

## 1. RpcCommand (stdin, host → agent)

Verbatim union from `rpc-types.ts`:

```ts
export type RpcCommand =
	// Protocol
	| { id?: string; type: "negotiate_protocol"; protocolVersion: number }

	// Prompting
	| { id?: string; type: "prompt"; message: string; images?: ImageContent[]; streamingBehavior?: "steer" | "followUp" }
	| { id?: string; type: "steer"; message: string; images?: ImageContent[] }
	| { id?: string; type: "follow_up"; message: string; images?: ImageContent[] }
	| { id?: string; type: "abort" }
	| { id?: string; type: "abort_and_prompt"; message: string; images?: ImageContent[] }
	| { id?: string; type: "new_session"; parentSession?: string }

	// State
	| { id?: string; type: "get_state" }
	| { id?: string; type: "set_fast_mode"; enabled: boolean }
	| { id?: string; type: "get_available_commands" }
	| { id?: string; type: "set_todos"; phases: TodoPhase[] }
	| { id?: string; type: "set_host_tools"; tools: RpcHostToolDefinition[] }
	| { id?: string; type: "set_host_uri_schemes"; schemes: RpcHostUriSchemeDefinition[] }
	| { id?: string; type: "set_subagent_subscription"; level: RpcSubagentSubscriptionLevel }
	| { id?: string; type: "get_subagents" }
	| { id?: string; type: "get_subagent_messages"; subagentId?: string; sessionFile?: string; fromByte?: number }

	// Model
	| { id?: string; type: "set_model"; provider: string; modelId: string }
	| { id?: string; type: "cycle_model" }
	| { id?: string; type: "get_available_models" }

	// Thinking
	| { id?: string; type: "set_thinking_level"; level: ThinkingLevel }
	| { id?: string; type: "cycle_thinking_level" }

	// Queue modes
	| { id?: string; type: "set_steering_mode"; mode: "all" | "one-at-a-time" }
	| { id?: string; type: "set_follow_up_mode"; mode: "all" | "one-at-a-time" }
	| { id?: string; type: "set_interrupt_mode"; mode: "immediate" | "wait" }

	// Compaction
	| { id?: string; type: "compact"; customInstructions?: string }
	| { id?: string; type: "set_auto_compaction"; enabled: boolean }

	// Retry
	| { id?: string; type: "set_auto_retry"; enabled: boolean }
	| { id?: string; type: "abort_retry" }

	// Bash
	| { id?: string; type: "bash"; command: string }
	| { id?: string; type: "abort_bash" }

	// Session
	| { id?: string; type: "get_session_stats" }
	| { id?: string; type: "export_html"; outputPath?: string }
	| { id?: string; type: "switch_session"; sessionPath: string }
	| { id?: string; type: "branch"; entryId: string }
	| { id?: string; type: "get_branch_messages" }
	| { id?: string; type: "get_last_assistant_text" }
	| { id?: string; type: "set_session_name"; name: string }
	| { id?: string; type: "handoff"; customInstructions?: string }

	// Messages
	| { id?: string; type: "get_messages" }
	| { id?: string; type: "get_messages_page"; cursor?: string; limit?: number }

	// Login
	| { id?: string; type: "get_login_providers" }
	| { id?: string; type: "login"; providerId: string };
```

Compact table (every variant carries optional `id?: string` for response correlation; omitted below):

| `type` | Extra fields (`?` = optional) |
|---|---|
| `negotiate_protocol` | `protocolVersion: number` (server only accepts `2`) |
| `prompt` | `message: string`, `images?: ImageContent[]`, `streamingBehavior?: "steer" \| "followUp"` |
| `steer` | `message: string`, `images?: ImageContent[]` |
| `follow_up` | `message: string`, `images?: ImageContent[]` |
| `abort` | — |
| `abort_and_prompt` | `message: string`, `images?: ImageContent[]` |
| `new_session` | `parentSession?: string` |
| `get_state` | — |
| `set_fast_mode` | `enabled: boolean` |
| `get_available_commands` | — |
| `set_todos` | `phases: TodoPhase[]` |
| `set_host_tools` | `tools: RpcHostToolDefinition[]` |
| `set_host_uri_schemes` | `schemes: RpcHostUriSchemeDefinition[]` |
| `set_subagent_subscription` | `level: "off" \| "progress" \| "events"` |
| `get_subagents` | — |
| `get_subagent_messages` | `subagentId?: string`, `sessionFile?: string`, `fromByte?: number` |
| `set_model` | `provider: string`, `modelId: string` |
| `cycle_model` | — |
| `get_available_models` | — |
| `set_thinking_level` | `level: ThinkingLevel` (`"inherit" \| "off" \| "minimal" \| "low" \| "medium" \| "high" \| "xhigh" \| "max"`) |
| `cycle_thinking_level` | — |
| `set_steering_mode` | `mode: "all" \| "one-at-a-time"` |
| `set_follow_up_mode` | `mode: "all" \| "one-at-a-time"` |
| `set_interrupt_mode` | `mode: "immediate" \| "wait"` |
| `compact` | `customInstructions?: string` |
| `set_auto_compaction` | `enabled: boolean` |
| `set_auto_retry` | `enabled: boolean` |
| `abort_retry` | — |
| `bash` | `command: string` |
| `abort_bash` | — |
| `get_session_stats` | — |
| `export_html` | `outputPath?: string` |
| `switch_session` | `sessionPath: string` |
| `branch` | `entryId: string` |
| `get_branch_messages` | — |
| `get_last_assistant_text` | — |
| `set_session_name` | `name: string` |
| `handoff` | `customInstructions?: string` |
| `get_messages` | — |
| `get_messages_page` | `cursor?: string`, `limit?: number` (1–256, default 100) |
| `get_login_providers` | — |
| `login` | `providerId: string` |

Unknown `type` values get an error response: `` return error(undefined, unknownCommand.type, `Unknown command: ${unknownCommand.type}`); `` (`rpc-mode.ts` `default` arm — note `id` is `undefined` there even if the command carried one).

---

## 2. RpcResponse, ready frame, rpc_chunk frame

### 2.1 RpcResponse (stdout)

Every response has `type: "response"`, echoes `command`, and carries `success: boolean`. Verbatim union from `rpc-types.ts`:

```ts
// Success responses with data
export type RpcResponse =
	// Protocol
	| {
			id?: string;
			type: "response";
			command: "negotiate_protocol";
			success: true;
			data: { protocolVersion: 2 };
	  }

	// Prompting (async - events follow)
	| { id?: string; type: "response"; command: "prompt"; success: true; data?: { agentInvoked: boolean } }
	| { id?: string; type: "response"; command: "steer"; success: true }
	| { id?: string; type: "response"; command: "follow_up"; success: true }
	| { id?: string; type: "response"; command: "abort"; success: true }
	| { id?: string; type: "response"; command: "abort_and_prompt"; success: true }
	| { id?: string; type: "response"; command: "new_session"; success: true; data: { cancelled: boolean } }

	// State
	| { id?: string; type: "response"; command: "get_state"; success: true; data: RpcSessionState }
	| {
			id?: string;
			type: "response";
			command: "set_fast_mode";
			success: true;
			data: { enabled: boolean; active: boolean };
	  }
	| {
			id?: string;
			type: "response";
			command: "get_available_commands";
			success: true;
			data: { commands: RpcAvailableSlashCommand[] };
	  }
	| { id?: string; type: "response"; command: "set_todos"; success: true; data: { todoPhases: TodoPhase[] } }
	| { id?: string; type: "response"; command: "set_host_tools"; success: true; data: { toolNames: string[] } }
	| { id?: string; type: "response"; command: "set_host_uri_schemes"; success: true; data: { schemes: string[] } }
	| {
			id?: string;
			type: "response";
			command: "set_subagent_subscription";
			success: true;
			data: { level: RpcSubagentSubscriptionLevel };
	  }
	| {
			id?: string;
			type: "response";
			command: "get_subagents";
			success: true;
			data: { subagents: RpcSubagentSnapshot[] };
	  }
	| {
			id?: string;
			type: "response";
			command: "get_subagent_messages";
			success: true;
			data: RpcSubagentMessagesResult;
	  }

	// Model
	| {
			id?: string;
			type: "response";
			command: "set_model";
			success: true;
			data: Model;
	  }
	| {
			id?: string;
			type: "response";
			command: "cycle_model";
			success: true;
			data: { model: Model; thinkingLevel: ThinkingLevel | undefined; isScoped: boolean } | null;
	  }
	| {
			id?: string;
			type: "response";
			command: "get_available_models";
			success: true;
			data: { models: Model[] };
	  }

	// Thinking
	| { id?: string; type: "response"; command: "set_thinking_level"; success: true }
	| {
			id?: string;
			type: "response";
			command: "cycle_thinking_level";
			success: true;
			data: { level: Effort } | null;
	  }

	// Queue modes
	| { id?: string; type: "response"; command: "set_steering_mode"; success: true }
	| { id?: string; type: "response"; command: "set_follow_up_mode"; success: true }
	| { id?: string; type: "response"; command: "set_interrupt_mode"; success: true }

	// Compaction
	| { id?: string; type: "response"; command: "compact"; success: true; data: CompactionResult }
	| { id?: string; type: "response"; command: "set_auto_compaction"; success: true }

	// Retry
	| { id?: string; type: "response"; command: "set_auto_retry"; success: true }
	| { id?: string; type: "response"; command: "abort_retry"; success: true }

	// Bash
	| { id?: string; type: "response"; command: "bash"; success: true; data: BashResult }
	| { id?: string; type: "response"; command: "abort_bash"; success: true }

	// Session
	| { id?: string; type: "response"; command: "get_session_stats"; success: true; data: SessionStats }
	| { id?: string; type: "response"; command: "export_html"; success: true; data: { path: string } }
	| { id?: string; type: "response"; command: "switch_session"; success: true; data: { cancelled: boolean } }
	| { id?: string; type: "response"; command: "branch"; success: true; data: { text: string; cancelled: boolean } }
	| {
			id?: string;
			type: "response";
			command: "get_branch_messages";
			success: true;
			data: { messages: Array<{ entryId: string; text: string }> };
	  }
	| {
			id?: string;
			type: "response";
			command: "get_last_assistant_text";
			success: true;
			data: { text: string | null };
	  }
	| { id?: string; type: "response"; command: "set_session_name"; success: true }
	| { id?: string; type: "response"; command: "handoff"; success: true; data: RpcHandoffResult | null }

	// Messages
	| { id?: string; type: "response"; command: "get_messages"; success: true; data: { messages: AgentMessage[] } }
	| { id?: string; type: "response"; command: "get_messages_page"; success: true; data: RpcMessagesPage }

	// Login
	| {
			id?: string;
			type: "response";
			command: "get_login_providers";
			success: true;
			data: { providers: Array<{ id: string; name: string; available: boolean; authenticated: boolean }> };
	  }
	| { id?: string; type: "response"; command: "login"; success: true; data: { providerId: string } }

	// Error response (any command can fail); `code` is an optional machine-readable reason.
	| { id?: string; type: "response"; command: string; success: false; error: string; code?: string };
```

Error responses are built by (`rpc-mode.ts`):

```ts
const error = (id: string | undefined, command: string, message: string, code?: string): RpcResponse => {
	return { id, type: "response", command, success: false, error: message, ...(code ? { code } : {}) };
};
```

Known `code` values, from `rpc-messages.ts` (used by `get_messages_page` failures):

```ts
/** Machine-readable reasons a `get_messages_page` request can fail; carried as `code` on the error response. */
export type RpcMessagesPageErrorCode = "session_busy" | "stale_cursor";
```

The reference client's response guard (`rpc-client.ts`) — minimum a Swift decoder must accept:

```ts
function isRpcResponse(value: unknown): value is RpcResponse {
	if (!isRecord(value)) return false;
	if (value.type !== "response") return false;
	if (typeof value.command !== "string") return false;
	if (typeof value.success !== "boolean") return false;
	if (value.id !== undefined && typeof value.id !== "string") return false;
	if (value.success === false) {
		return typeof value.error === "string";
	}
	return true;
}
```

Supporting response payload types (verbatim, `rpc-types.ts` unless noted):

```ts
export interface RpcSessionState {
	model?: Model;
	thinkingLevel: ThinkingLevel | undefined;
	isStreaming: boolean;
	isCompacting: boolean;
	steeringMode: "all" | "one-at-a-time";
	followUpMode: "all" | "one-at-a-time";
	interruptMode: "immediate" | "wait";
	sessionFile?: string;
	sessionId: string;
	sessionName?: string;
	autoCompactionEnabled: boolean;
	fastModeEnabled: boolean;
	fastModeActive: boolean;
	tokensPerSecond: number | null;
	messageCount: number;
	queuedMessageCount: number;
	todoPhases: TodoPhase[];
	/** For session dump / export (plain-text parity with /dump). */
	systemPrompt?: string[];
	dumpTools?: Array<{ name: string; description: string; parameters: unknown; examples?: readonly ToolExample[] }>;
	/** Current context window usage. */
	contextUsage?: ContextUsage;
}

export interface RpcAvailableSlashCommand {
	name: string;
	aliases?: string[];
	description?: string;
	input?: { hint?: string };
	subcommands?: Array<{ name: string; description?: string; usage?: string }>;
	source: AvailableSlashCommandSource;
}

export interface RpcHandoffResult {
	savedPath?: string;
}

export type RpcSubagentSubscriptionLevel = "off" | "progress" | "events";

export interface RpcSubagentSnapshot {
	id: string;
	index: number;
	agent: string;
	agentSource: AgentProgress["agentSource"];
	description?: string;
	status: AgentProgress["status"];
	task?: string;
	assignment?: string;
	sessionFile?: string;
	lastUpdate: number;
	progress?: AgentProgress;
	parentToolCallId?: string;
}

export interface RpcSubagentMessagesResult {
	sessionFile: string;
	fromByte: number;
	nextByte: number;
	reset: boolean;
	entries: FileEntry[];
	messages: AgentMessage[];
}
```

```ts
// rpc-messages.ts
export interface RpcMessagesPage {
	messages: AgentMessage[];
	nextCursor?: string;
	totalMessages: number;
}
```

`get_messages_page` cursor rules (`rpc-messages.ts`): cursor is opaque base64url (charset `[A-Za-z0-9_-]`, max 2048 chars); `limit` must be a safe integer 1–256 (default 100); page byte budget 768 KiB (`MAX_RPC_MESSAGE_PAGE_BYTES = 768 * 1024`); a cursor minted against a different session snapshot fails with `code: "stale_cursor"`.

### 2.2 Ready frame

Declared type and actual emission differ in one respect: the interface pins `protocolVersion: 1` and the server emits exactly that.

```ts
export interface RpcReadyFrame {
	type: "ready";
	protocolVersion: 1;
	supportedProtocolVersions: [1, 2];
	maxFrameBytes: number;
	maxReassembledFrameBytes: number;
}
```

Emission (`rpc-mode.ts`):

```ts
writeFrames(
	frameEncoder.encodeFrames({
		type: "ready",
		protocolVersion: 1,
		supportedProtocolVersions: [1, 2],
		maxFrameBytes: MAX_RPC_FRAME_BYTES,
		maxReassembledFrameBytes: MAX_RPC_REASSEMBLED_BYTES,
	}),
);
```

The reference client only upgrades to v2 when the ready frame matches its own constants EXACTLY (`rpc-client.ts`):

```ts
function supportsRpcProtocolV2(value: Record<string, unknown>): boolean {
	return (
		value.type === "ready" &&
		Array.isArray(value.supportedProtocolVersions) &&
		value.supportedProtocolVersions.includes(2) &&
		value.maxFrameBytes === MAX_RPC_FRAME_BYTES &&
		value.maxReassembledFrameBytes === MAX_RPC_REASSEMBLED_BYTES
	);
}
```

v2 is activated on the server only after a successful `negotiate_protocol` response is written; the server rejects any `protocolVersion !== 2`:

```ts
case "negotiate_protocol": {
	if (command.protocolVersion !== 2)
		return error(id, "negotiate_protocol", `Unsupported RPC protocol version: ${command.protocolVersion}`);
	return success(id, "negotiate_protocol", { protocolVersion: 2 });
}
```

### 2.3 rpc_chunk frame (protocol v2 only)

```ts
export interface RpcChunkFrame {
	type: "rpc_chunk";
	chunkId: string;
	index: number;
	count: number;
	byteLength: number;
	data: string;
}
```

`data` is standard base64 (`+/` alphabet with `=` padding) of a slice of the UTF-8 bytes of the logical frame's JSON; `byteLength` is the total UTF-8 byte length of the reassembled JSON; `index` is 0-based; `count` is total chunks. The reference client refuses chunk frames before negotiation: `if (isRecord(line) && line.type === "rpc_chunk" && !protocolV2Enabled) throw new Error("RPC chunk received before protocol negotiation");` (`rpc-client.ts`).

---

## 3. Extension UI: RpcExtensionUIRequest / RpcExtensionUIResponse

### 3.1 Request union (stdout, agent → host) — verbatim from `rpc-types.ts`

```ts
/** Positional presentation metadata for an RPC select option. */
export interface RpcExtensionUISelectOptionDetail {
	description?: string;
}

/** Emitted when an extension needs user input */
export type RpcExtensionUIRequest =
	| {
			type: "extension_ui_request";
			id: string;
			method: "select";
			title: string;
			options: string[];
			optionDetails?: RpcExtensionUISelectOptionDetail[];
			timeout?: number;
	  }
	| { type: "extension_ui_request"; id: string; method: "confirm"; title: string; message: string; timeout?: number }
	| {
			type: "extension_ui_request";
			id: string;
			method: "input";
			title: string;
			placeholder?: string;
			timeout?: number;
	  }
	| {
			type: "extension_ui_request";
			id: string;
			method: "editor";
			title: string;
			prefill?: string;
			promptStyle?: boolean;
	  }
	| { type: "extension_ui_request"; id: string; method: "cancel"; targetId: string }
	| {
			type: "extension_ui_request";
			id: string;
			method: "notify";
			message: string;
			notifyType?: "info" | "warning" | "error";
	  }
	| {
			type: "extension_ui_request";
			id: string;
			method: "setStatus";
			statusKey: string;
			statusText: string | undefined;
	  }
	| {
			type: "extension_ui_request";
			id: string;
			method: "setWidget";
			widgetKey: string;
			widgetLines: string[] | undefined;
			widgetPlacement?: "aboveEditor" | "belowEditor";
	  }
	| { type: "extension_ui_request"; id: string; method: "setTitle"; title: string }
	| { type: "extension_ui_request"; id: string; method: "set_editor_text"; text: string }
	| {
			type: "extension_ui_request";
			id: string;
			method: "open_url";
			url: string;
			/**
			 * Short loopback URL that 302-redirects to {@link url}. When present,
			 * hosts SHOULD surface it as the copy target so terminal viewport
			 * truncation cannot corrupt OAuth query parameters on the full URL.
			 */
			launchUrl?: string;
			instructions?: string;
	  };
```

### 3.2 Which methods REQUIRE a host response vs fire-and-forget

Determined from the `RpcExtensionUIContext` implementation in `rpc-mode.ts` (methods that register a `PendingExtensionRequest` and await an `extension_ui_response`, vs methods with explicit "Fire and forget" comments):

| Method | Host MUST respond? | Notes |
|---|---|---|
| `select` | **YES** — `extension_ui_response` with `value` (chosen option label) or `cancelled: true` | `optionDetails`, when present, is positionally aligned with `options` |
| `confirm` | **YES** — `extension_ui_response` with `confirmed: boolean` or `cancelled: true` | `cancelled` parses to `false` |
| `input` | **YES** — `extension_ui_response` with `value` or `cancelled: true` | `cancelled` parses to `undefined` |
| `editor` | **YES** — `extension_ui_response` with `value` or `cancelled: true` | no `timeout` field on this frame |
| `notify` | no — fire-and-forget | source comment: `// Fire and forget - no response needed` |
| `setStatus` | no — fire-and-forget | `statusText` may be absent (TS `undefined` — cleared status) |
| `setWidget` | no — fire-and-forget | server only forwards string-array or undefined content; component factories are silently dropped |
| `setTitle` | no — fire-and-forget | ONLY emitted when env `PI_RPC_EMIT_TITLE` is truthy (`1`/`true`/`yes`/`on`) |
| `set_editor_text` | no — fire-and-forget | also used as the fallback for `pasteToEditor` |
| `open_url` | no — fire-and-forget | emitted during `login` OAuth flow |
| `cancel` | no — server → host notification | `targetId` names the earlier request `id` the host should dismiss; the server has already resolved it |

Timeout semantics: the `timeout` field on `select`/`confirm`/`input` frames is advisory display metadata — the SERVER enforces the timeout itself (`requestRpcDialog` sets `setTimeout(... resolve(defaultValue) ...)`) and simply stops waiting; a late host response for a timed-out/cancelled id is ignored (the pending entry was deleted). When a dialog's abort signal fires, the server emits a `cancel` frame with a FRESH `id` and the original request's id in `targetId`:

```ts
const onAbort = () => {
	output({
		type: "extension_ui_request",
		id: Snowflake.next() as string,
		method: "cancel",
		targetId: id,
	} as RpcExtensionUIRequest);
	cleanup();
	resolve(defaultValue);
};
```

### 3.3 Response union (stdin, host → agent) — verbatim

```ts
/** Response to an extension UI request */
export type RpcExtensionUIResponse =
	| { type: "extension_ui_response"; id: string; value: string }
	| { type: "extension_ui_response"; id: string; confirmed: boolean }
	| { type: "extension_ui_response"; id: string; cancelled: true; timedOut?: boolean };
```

Server-side inbound guard is intentionally loose (payload validated at the read site):

```ts
function isRpcExtensionUIResponse(value: unknown): value is RpcExtensionUIResponse {
	if (!isRecord(value)) return false;
	return value.type === "extension_ui_response" && typeof value.id === "string";
}
```

Response parsing per method: `confirm` — `cancelled` → `false`, else `confirmed`; `select`/`input`/`editor` — `cancelled` → `undefined`, else `value` (missing both → `undefined`). `timedOut: true` on a `cancelled` response triggers the dialog's `onTimeout` callback server-side. Extension UI responses (and host tool/URI result frames) are control frames dispatched immediately, bypassing the serialized command queue.

---

## 4. RpcFrameDecoder validation rules (rpc-frame.ts)

Constants (verbatim):

```ts
/** Maximum UTF-8 size of one newline-delimited RPC frame, including the newline. */
export const MAX_RPC_FRAME_BYTES = 1024 * 1024;
/** Maximum UTF-8 size of one logical frame reassembled by protocol v2. */
export const MAX_RPC_REASSEMBLED_BYTES = 64 * 1024 * 1024;

const RPC_CHUNK_PAYLOAD_BYTES = 256 * 1024;
```

Base64 strictness — regex AND round-trip check:

```ts
function decodeBase64(data: unknown): Buffer {
	if (
		typeof data !== "string" ||
		data.length === 0 ||
		!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(data)
	)
		throw new Error("invalid rpc chunk data");
	const bytes = Buffer.from(data, "base64");
	if (bytes.toString("base64") !== data) throw new Error("invalid rpc chunk data");
	return bytes;
}
```

The decoder, verbatim and in full:

```ts
/** Reassemble protocol v2 chunk frames after each JSONL line has been parsed. */
export class RpcFrameDecoder {
	#pending?: PendingRpcChunks;

	push(value: unknown): object | undefined {
		if (!isRpcChunkFrame(value)) {
			if (this.#pending) throw new Error("rpc chunk sequence interrupted");
			if (!isRecord(value)) throw new Error("rpc frame must be an object");
			return value;
		}
		const { chunkId, index, count, byteLength } = value;
		if (
			typeof chunkId !== "string" ||
			chunkId.length === 0 ||
			chunkId.length > 128 ||
			!Number.isSafeInteger(index) ||
			!Number.isSafeInteger(count) ||
			!Number.isSafeInteger(byteLength) ||
			index < 0 ||
			count < 2 ||
			count > Math.ceil(MAX_RPC_REASSEMBLED_BYTES / RPC_CHUNK_PAYLOAD_BYTES) ||
			index >= count ||
			byteLength < MAX_RPC_FRAME_BYTES ||
			byteLength > MAX_RPC_REASSEMBLED_BYTES
		)
			throw new Error("invalid rpc chunk metadata");
		const bytes = decodeBase64(value.data);
		if (bytes.byteLength > RPC_CHUNK_PAYLOAD_BYTES) throw new Error("rpc chunk payload exceeds the transport limit");

		if (!this.#pending) {
			if (index !== 0) throw new Error("rpc chunk sequence must start at index 0");
			this.#pending = { chunkId, count, byteLength, nextIndex: 0, chunks: [], receivedBytes: 0 };
		}
		const pending = this.#pending;
		if (
			pending.chunkId !== chunkId ||
			pending.count !== count ||
			pending.byteLength !== byteLength ||
			pending.nextIndex !== index
		)
			throw new Error("rpc chunk sequence mismatch");
		pending.chunks.push(bytes);
		pending.receivedBytes += bytes.byteLength;
		pending.nextIndex++;
		if (pending.receivedBytes > pending.byteLength) throw new Error("rpc chunk sequence exceeds declared length");
		if (pending.nextIndex < pending.count) return undefined;
		if (pending.receivedBytes !== pending.byteLength) throw new Error("rpc chunk sequence length mismatch");

		this.#pending = undefined;
		const decoded = new TextDecoder("utf-8", { fatal: true }).decode(Buffer.concat(pending.chunks));
		const frame: unknown = JSON.parse(decoded);
		if (!isRecord(frame)) throw new Error("rpc frame must be an object");
		return frame;
	}
}
```

A chunk frame is anything with `type === "rpc_chunk"` (`isRpcChunkFrame`). Derived facts a Swift port must reproduce:

- **Metadata bounds:** `chunkId` non-empty string ≤ 128 chars; `index`, `count`, `byteLength` safe integers; `0 <= index < count`; `count >= 2` and `count <= ceil(64 MiB / 256 KiB) = 256`; `MAX_RPC_FRAME_BYTES (1 MiB) <= byteLength <= MAX_RPC_REASSEMBLED_BYTES (64 MiB)`. A logical frame that fits in one physical line is NEVER chunked — a single-chunk (`count: 1`) or small-`byteLength` sequence is invalid by construction.
- **Per-chunk payload cap:** decoded bytes ≤ 256 KiB (`RPC_CHUNK_PAYLOAD_BYTES`), enforced AFTER strict base64 decode.
- **Sequencing:** first chunk of a sequence must have `index: 0`; every subsequent chunk must match the pending sequence's `chunkId`, `count`, `byteLength` exactly and arrive with `index === nextIndex` (strictly in order, no interleaving of sequences).
- **What aborts a sequence (throws):** any non-chunk frame while a sequence is pending ("rpc chunk sequence interrupted"); metadata out of bounds; base64 regex/round-trip failure; oversized chunk payload; chunkId/count/byteLength/index mismatch; accumulated bytes exceeding `byteLength`; final total not exactly `byteLength`; reassembled bytes not valid UTF-8 (`TextDecoder("utf-8", { fatal: true })` — lone surrogates/invalid sequences are fatal, not replaced); reassembled JSON not parsing, or parsing to a non-object.
- **Errors are terminal, not recoverable:** on throw, `#pending` is NOT cleared. The reference client treats any decoder throw as fatal to the connection (`reapAfterOutputFailure`: abort all pending requests, kill the child). A port should tear down or poison the decoder on error, never resume pushing.
- **Non-chunk frames:** passed through unchanged, but must be JSON objects (`isRecord`), else throw.

Input framing (`rpc-input.ts` `readRpcInputFrames`): lines are trimmed; blank lines skipped; a line that fails `JSON.parse` produces a parse-error callback (server answers with `{ id: undefined, type: "response", command: "parse", success: false, error: "Failed to parse command: ..." }`) and does NOT stop the stream. Note the asymmetry: unparsable stdin lines are survivable; decoder-level chunk violations are not.

Encoder-side context (server → client, `rpc-frame.ts`): under v1, an oversized frame is progressively degraded (compact `agent_end` messages, then 7 shrink passes eliding strings/arrays/objects, then an `overflowFrame` replacement — for `response` frames that is `success: false, error: "RPC response exceeded the transport limit"`; for other frames `{ type: "rpc_frame_error", originalType, error: "RPC frame exceeded the transport limit" }`). Under v2, frames larger than 1 MiB are chunked instead; only frames whose JSON exceeds 64 MiB still get the overflow replacement. Chunk ids are generated as `` `rpc-${++this.#chunkCounter}` ``.

---

## 5. Side-channel frames

### 5.1 command_output / session_info_update / config_update (stdout)

These three have NO declared interface in `rpc-types.ts` — they are inline object literals in `rpc-mode.ts` (slash-command execution context inside the `prompt` handler). Verbatim emit sites:

```ts
output: text => output({ type: "command_output", text }),
```

```ts
notifyTitleChanged: async () => {
	output({ type: "session_info_update", title: session.sessionName, sessionId: session.sessionId });
},
notifyConfigChanged: async () => {
	output({ type: "config_update", model: session.model, thinkingLevel: session.thinkingLevel });
},
```

Effective wire shapes:

| Frame | Fields |
|---|---|
| `command_output` | `text: string` |
| `session_info_update` | `title: string \| undefined` (absent when session unnamed), `sessionId: string` |
| `config_update` | `model: Model \| undefined`, `thinkingLevel: ThinkingLevel \| undefined` |

(Swift: treat `title`, `model`, `thinkingLevel` as optional — `JSON.stringify` drops `undefined` object properties, so they are simply absent keys.)

### 5.2 prompt_result (stdout)

```ts
export interface RpcPromptResultFrame {
	type: "prompt_result";
	id?: string;
	agentInvoked: boolean;
}
```

Emitted (with the originating command's `id`) only when a `prompt` resolved WITHOUT invoking the agent (local-only slash command) and no extension scheduled agent work: `input.output({ type: "prompt_result", id: input.id, agentInvoked: false });` (`rpc-mode.ts` `reportLocalOnlyPromptResult`). When the agent IS invoked, no `prompt_result` follows — session events stream instead.

### 5.3 available_commands_update (stdout)

```ts
export interface RpcAvailableCommandsUpdateFrame {
	type: "available_commands_update";
	commands: RpcAvailableSlashCommand[];
}
```

Emitted once at startup and again whenever command metadata changes. Client guard: `value.type === "available_commands_update" && Array.isArray(value.commands)`.

### 5.4 notice (stdout, part of the AgentSessionEvent stream)

Declared in `session/agent-session-events.ts` (not rpc-types.ts):

```ts
| { type: "notice"; level: "info" | "warning" | "error"; message: string; source?: string }
```

### 5.5 host_tool_call / host_tool_cancel (stdout) and their stdin replies

```ts
export interface RpcHostToolDefinition {
	name: string;
	label?: string;
	description: string;
	parameters: Record<string, unknown>;
	hidden?: boolean;
	/** How this host tool is presented when enabled; omission normalizes to `"discoverable"` at the adapter boundary. */
	loadMode?: ToolLoadMode;
}

/** Emitted by the RPC server when it needs the host to execute a registered tool. */
export interface RpcHostToolCallRequest {
	type: "host_tool_call";
	id: string;
	toolCallId: string;
	toolName: string;
	arguments: Record<string, unknown>;
}

/** Emitted by the RPC server when a pending host tool call should be aborted. */
export interface RpcHostToolCancelRequest {
	type: "host_tool_cancel";
	id: string;
	targetId: string;
}

/** Sent by the host to stream partial tool updates back to the RPC server. */
export interface RpcHostToolUpdate {
	type: "host_tool_update";
	id: string;
	partialResult: AgentToolResult<unknown>;
}

/** Sent by the host to complete a pending tool call. */
export interface RpcHostToolResult {
	type: "host_tool_result";
	id: string;
	result: AgentToolResult<unknown>;
	isError?: boolean;
}
```

Contract details (`host-tools.ts`): `host_tool_call` REQUIRES exactly one eventual `host_tool_result` correlated by `id` (not `toolCallId`); zero or more `host_tool_update` frames may precede it. Like `cancel`/`host_uri_cancel`, `host_tool_cancel` carries its own fresh `id` — correlation is via `targetId`; after cancel, a late result is ignored. Inbound guards require `result.content` / `partialResult.content` to be an array (`isAgentToolResult`). On `isError: true`, the server joins the `text`-type content items into the thrown error message (fallback `"Host tool execution failed"`). `set_host_tools` validation: non-empty trimmed `name` and `description`, `parameters` a non-array object, else the command errors.

### 5.6 host_uri_request / host_uri_cancel (stdout) and host_uri_result (stdin)

```ts
export interface RpcHostUriSchemeDefinition {
	/** URL scheme without trailing `://` (e.g. `db`, `notion`). */
	scheme: string;
	/** Optional human-readable description for logs/diagnostics. */
	description?: string;
	/** When true, the write tool is allowed to dispatch writes to this scheme. */
	writable?: boolean;
	/** When true, downstream callers suppress hashline anchors for resolved content. */
	immutable?: boolean;
}

export type RpcHostUriOperation = "read" | "write";

/** Emitted by the RPC server when it needs the host to satisfy a URI operation. */
export interface RpcHostUriRequest {
	type: "host_uri_request";
	id: string;
	operation: RpcHostUriOperation;
	url: string;
	/** Present for write operations. */
	content?: string;
}

/** Emitted by the RPC server when a pending URI request should be aborted. */
export interface RpcHostUriCancelRequest {
	type: "host_uri_cancel";
	id: string;
	targetId: string;
}

/** Sent by the host to complete a pending URI request. */
export interface RpcHostUriResult {
	type: "host_uri_result";
	id: string;
	/**
	 * Required for successful `read` results. Ignored for `write` success.
	 * Set on errors when a textual explanation accompanies `isError`.
	 */
	content?: string;
	/** Defaults to `text/plain` when omitted. */
	contentType?: "text/markdown" | "application/json" | "text/plain";
	/** Optional resolution notes propagated to the read tool. */
	notes?: string[];
	/** Overrides the scheme-level `immutable` flag for this single resolution. */
	immutable?: boolean;
	/** When true, surface the result content as an error to the caller. */
	isError?: boolean;
	/** Optional error message; preferred over `content` for error surfacing. */
	error?: string;
}
```

Contract details (`host-uris.ts`): schemes are normalized to lowercase and must match `/^[a-z][a-z0-9+.-]*$/`; the `security` scheme is reserved and rejected. Inbound guard checks only `type === "host_uri_result"` and string `id`. On error results the thrown message prefers `error`, then `content`, then a generic fallback. `host_uri_request` with `operation: "write"` always carries `content` (defaulted to `""`).

### 5.7 Subagent frames (stdout, when subscribed via set_subagent_subscription)

```ts
export interface RpcSubagentLifecycleFrame {
	type: "subagent_lifecycle";
	payload: SubagentLifecyclePayload;
}

export interface RpcSubagentProgressFrame {
	type: "subagent_progress";
	payload: SubagentProgressPayload;
}

export interface RpcSubagentEventFrame {
	type: "subagent_event";
	payload: SubagentEventPayload;
}
```

---

## Extraction caveats

Opaque referenced types NOT expanded (import them or treat as raw JSON in Swift; source modules): `Model`, `ImageContent`, `ToolExample`, `Effort` — `@oh-my-pi/pi-ai` (`Effort` verified this extraction from `packages/catalog/src/effort.ts`: a TS `const enum` with inlined string values `"minimal" | "low" | "medium" | "high" | "xhigh" | "max"`); `AgentMessage`, `AgentToolResult`, `ThinkingLevel`, `ToolLoadMode` — `@oh-my-pi/pi-agent-core` (`ThinkingLevel` verified from `packages/agent/src/thinking.ts`: `"inherit" | "off" |` the six Effort values); `CompactionResult` — `pi-agent-core/compaction`; `BashResult` — `src/exec/bash-executor`; `ContextUsage` — `src/extensibility/extensions/types`; `AgentSessionEvent`, `SessionStats` — `src/session/agent-session`; `FileEntry` — `src/session/session-entries`; `AvailableSlashCommandSource` — `src/slash-commands/available-commands`; `AgentProgress`, `SubagentLifecyclePayload`, `SubagentProgressPayload`, `SubagentEventPayload` — `src/task`; `TodoPhase` — `src/tools/todo`. Verify each shape at the source before hard-typing in Swift.

`command_output`, `session_info_update`, and `config_update` have NO TypeScript interface in `rpc-types.ts` — only inline emits in `rpc-mode.ts` (quoted in 5.1), so their shapes can drift silently between versions; the optionality of `title`/`model`/`thinkingLevel` is inferred from the session fields at the emit sites, not from a declared type.

The full `AgentSessionEvent` stream shares stdout with everything above (client-recognized types: `agent_start`, `agent_end`, `turn_start`, `turn_end`, `message_start`, `message_update`, `message_end`, `tool_execution_start`, `tool_execution_update`, `tool_execution_end`, `auto_compaction_start`, `auto_compaction_end`, `auto_retry_start`, `auto_retry_end`, `retry_fallback_applied`, `retry_fallback_succeeded`, `ttsr_triggered`, `todo_reminder`, `todo_auto_clear`, `irc_message`, `notice`, `thinking_level_changed`, `model_changed`, `goal_updated` — per the `sessionEventTypes` set in `rpc-client.ts`); only `notice` is expanded here — the rest are documented in the sibling event-stream reference, not this file. A Swift decoder must tolerate unknown `type` values on stdout without failing.

Version caveat: shapes reflect the v18.0.4 checkout at the scratchpad path on 2026-08-24. The strict-equality v2 handshake (`supportsRpcProtocolV2` compares `maxFrameBytes`/`maxReassembledFrameBytes` exactly against the client's own constants) means any build that changes `MAX_RPC_FRAME_BYTES` or `MAX_RPC_REASSEMBLED_BYTES` silently falls back to protocol v1 against the reference client.
