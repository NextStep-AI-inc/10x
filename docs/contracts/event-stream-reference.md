<!-- Extracted 2026-08-24 from oh-my-pi v18.0.4 checkout (github.com/can1357/oh-my-pi). Regenerate on omp version bumps. Verified against OmpKit tests 2026-08-24. -->

# oh-my-pi Event Stream Reference (for a Swift transcript engine)

All paths relative to `/private/tmp/claude-501/-Users-tannerpham-CS-Projects/c47436ce-aa27-45cc-8fdd-87aaa0fecbfb/scratchpad/oh-my-pi`.

## 0. Topology — where events come from

- **`packages/agent/src/types.ts`** defines the core `AgentEvent` union emitted by the agent loop (`packages/agent/src/agent-loop.ts`).
- **`packages/coding-agent/src/session/agent-session-events.ts`** defines `AgentSessionEvent` = core `AgentEvent` (with `agent_end` augmented) + session-level events (`model_changed`, `thinking_level_changed`, retries, compaction, …).
- **RPC mode forwards session events verbatim as JSON on stdout** (`packages/coding-agent/src/modes/rpc/rpc-mode.ts:978`):

```typescript
// Output all agent events as JSON
session.subscribe(event => {
	output(event);
});
```

- The stdout stream is **multiplexed**: `AgentSessionEvent` frames interleave with `response` frames, `subagent_lifecycle` / `subagent_progress` / `subagent_event`, `extension_ui_request`, `available_commands_update`, `extension_error`, etc. (`rpc-types.ts:365`: `type RpcSessionEventFrame = AgentSessionEvent | RpcSubagentFrame;`). **A Swift decoder must switch on `type` and silently skip unknown values, never fail.**

## 1. Event shapes

### 1.1 Core `AgentEvent` — `packages/agent/src/types.ts` (lines 864–885, verbatim)

```typescript
export type AgentEvent =
	// Agent lifecycle
	| { type: "agent_start" }
	| {
			type: "agent_end";
			messages: AgentMessage[];
			/** Present iff `AgentTelemetryConfig` was supplied on this run. */
			telemetry?: AgentRunSummary;
			coverage?: AgentRunCoverage;
	  }
	// Turn lifecycle - a turn is one assistant response + any tool calls/results
	| { type: "turn_start" }
	| { type: "turn_end"; message: AgentMessage; toolResults: ToolResultMessage[] }
	// Message lifecycle - emitted for user, assistant, and toolResult messages
	| { type: "message_start"; message: AgentMessage }
	// Only emitted for assistant messages during streaming
	| { type: "message_update"; message: AgentMessage; assistantMessageEvent: AssistantMessageEvent }
	| { type: "message_end"; message: AgentMessage }
	// Tool execution lifecycle
	| { type: "tool_execution_start"; toolCallId: string; toolName: string; args: any; intent?: string }
	| { type: "tool_execution_update"; toolCallId: string; toolName: string; args: any; partialResult: any }
	| { type: "tool_execution_end"; toolCallId: string; toolName: string; result: any; isError?: boolean };
```

`turn_end.message` is the assistant message that closed the turn; `toolResults` are that turn's `ToolResultMessage`s (already appended to context).

### 1.2 `AgentSessionEvent` — `packages/coding-agent/src/session/agent-session-events.ts` (full file, verbatim, minus imports)

```typescript
/** Session-specific events that extend the core AgentEvent. */
export type AgentSessionEvent =
	| Exclude<AgentEvent, { type: "agent_end" }>
	| (Extract<AgentEvent, { type: "agent_end" }> & {
			/** False when an async delivery will resume the session before its true final settle. */
			isTerminal?: boolean;
	  })
	| {
			type: "auto_compaction_start";
			reason: "threshold" | "overflow" | "idle" | "incomplete";
			action: "context-full" | "remote" | "handoff" | "shake" | "snapcompact";
	  }
	| {
			type: "auto_compaction_end";
			action: "context-full" | "remote" | "handoff" | "shake" | "snapcompact";
			result: CompactionResult | undefined;
			aborted: boolean;
			willRetry: boolean;
			errorMessage?: string;
			/** True when compaction was skipped for a benign reason. */
			skipped?: boolean;
	  }
	| {
			type: "auto_retry_start";
			attempt: number;
			maxAttempts: number;
			delayMs: number;
			errorMessage: string;
			errorId?: number;
	  }
	| {
			type: "auto_retry_end";
			success: boolean;
			attempt: number;
			finalError?: string;
			retryErrors?: RetryErrorUpdate[];
	  }
	| { type: "retry_fallback_applied"; from: string; to: string; role: string }
	| { type: "retry_fallback_succeeded"; model: string; role: string }
	| { type: "model_changed" }
	| { type: "ttsr_triggered"; rules: Rule[] }
	| { type: "todo_reminder"; todos: TodoItem[]; attempt: number; maxAttempts: number }
	| { type: "todo_auto_clear" }
	| { type: "irc_message"; message: CustomMessage }
	| { type: "notice"; level: "info" | "warning" | "error"; message: string; source?: string }
	| {
			type: "thinking_level_changed";
			thinkingLevel: ThinkingLevel | undefined;
			/** The user-configured selector when it differs from the effective level. */
			configured?: ConfiguredThinkingLevel;
			/** The level `auto` resolved to this turn, once classified. */
			resolved?: Effort;
	  }
	| { type: "goal_updated"; goal: Goal | null; state?: GoalModeState };
```

Key facts:

- **`model_changed` carries no payload.** `{ type: "model_changed" }` is the whole frame — the consumer must re-query session state (e.g. `get_state`) for the new model. Emitted via synchronous fan-out (`agent-session.ts:7549`, `:8290`, `:9600`).
- **`agent_end.isTerminal`**: added at the session layer, not the loop. `agent-session.ts:2884`:
  ```typescript
  await this.#emitSessionEvent({ ...event, isTerminal: !options?.willContinue });
  ```
  The field is optional. Rule for the reducer: **only an explicit `isTerminal: false` means "not final"** (an async delivery/scheduled continuation will resume the run); `true` or absent means the session settled. The session also holds `agent_end` until in-flight prompt count drops to 0 (`agent-session.ts:2146–2154`), so subscribers treat it as the "session is idle" signal.
- **`thinking_level_changed` supporting types**:
  - `Effort` (`packages/catalog/src/effort.ts`): `const enum Effort { Minimal = "minimal", Low = "low", Medium = "medium", High = "high", XHigh = "xhigh", Max = "max" }` — serializes as those string literals.
  - `ThinkingLevel` (`packages/agent/src/thinking.ts`): `"inherit" | "off" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max"`.
  - `ConfiguredThinkingLevel` (`packages/coding-agent/src/thinking.ts:138–141`): `ThinkingLevel | "auto"` (`AUTO_THINKING = "auto"`).

### 1.3 `AssistantMessageEvent` delta union — `packages/ai/src/types.ts` (lines 1283–1306, verbatim)

This rides inside `message_update.assistantMessageEvent`.

```typescript
export type AssistantMessageEvent =
	| { type: "start"; contentIndex?: undefined; partial: AssistantMessage }
	| { type: "text_start"; contentIndex: number; partial: AssistantMessage }
	| { type: "text_delta"; contentIndex: number; delta: string; partial: AssistantMessage }
	| { type: "text_end"; contentIndex: number; content: string; partial: AssistantMessage }
	| { type: "thinking_start"; contentIndex: number; partial: AssistantMessage }
	| { type: "thinking_delta"; contentIndex: number; delta: string; partial: AssistantMessage }
	| { type: "thinking_end"; contentIndex: number; content: string; partial: AssistantMessage }
	| { type: "image_end"; contentIndex: number; content: ImageContent; partial: AssistantMessage }
	| { type: "toolcall_start"; contentIndex: number; partial: AssistantMessage }
	| { type: "toolcall_delta"; contentIndex: number; delta: string; partial: AssistantMessage }
	| { type: "toolcall_end"; contentIndex: number; toolCall: ToolCall; partial: AssistantMessage }
	| {
			type: "done";
			contentIndex?: undefined;
			reason: Extract<StopReason, "stop" | "length" | "toolUse">;
			message: AssistantMessage;
	  }
	| {
			type: "error";
			contentIndex?: undefined;
			reason: Extract<StopReason, "aborted" | "error">;
			error: AssistantMessage;
	  };
```

Field-name notes: text/thinking/toolcall deltas all use `delta: string`; `text_end`/`thinking_end` use `content: string` (the finalized block text); `toolcall_end` uses `toolCall: ToolCall` (finalized, fully-parsed `arguments`); `image_end` uses `content: ImageContent`. `contentIndex` indexes into `partial.content`. Note: **`done`/`error` never reach `message_update` subscribers** — the loop consumes them and emits `message_end` instead (`agent-loop.ts:1817–1821`); the wrapped `assistantMessageEvent` you see is only `start` and the `*_start/_delta/_end` block events.

### 1.4 Tool execution events (payload details, from `agent-loop.ts`)

Emission order per call: `tool_execution_start` → zero or more `tool_execution_update` → `tool_execution_end` → then the paired tool-result message as back-to-back `message_start` + `message_end` (no updates for toolResult messages). From `agent-loop.ts:2488–2494` and `:2550–2558`:

```typescript
stream.push({
	type: "tool_execution_start",
	toolCallId: toolCall.id,
	toolName: toolCall.name,
	args: effectiveArgs,
	intent: toolCall.intent,
});
...
const rawResult = await tool.execute(
	toolCall.id, executionArgs, record.signal,
	partialResult => {
		stream.push({
			type: "tool_execution_update",
			toolCallId: toolCall.id,
			toolName: toolCall.name,
			args: executionArgs,
			partialResult: coerceToolResult(partialResult).result,
		});
	},
	toolContext,
);
```

`partialResult` and `tool_execution_end.result` are both coerced to `AgentToolResult` (`packages/agent/src/types.ts:678–690`):

```typescript
export interface AgentToolResult<T = any, _TInput = unknown> {
	// Content blocks supporting text and images
	content: (TextContent | ImageContent)[];
	// Details to be displayed in a UI or logged
	details?: T;
	// Marks a non-throwing failure ...
	isError?: boolean;
	/** Provider-native metadata that must survive into history replay unchanged. */
	providerMetadata?: ToolResultProviderMetadata;
	/** Marks the result as contextually useless ... */
	useless?: boolean;
}
```

Errors: on throw/blocked/validation failure, `tool_execution_end` is emitted with `isError: true` and `result.content = [{ type: "text", text: <error message> }]` (`agent-loop.ts:2565–2572`, `:2465–2475`). The streamed-output shape is therefore identical for partials and finals: incremental `content`/`details` snapshots, not deltas — each `tool_execution_update.partialResult` **replaces** the previous one.

## 2. `AgentMessage` — what `get_messages_page` returns

```typescript
// packages/agent/src/types.ts:660
export type AgentMessage = Message | CustomAgentMessages[keyof CustomAgentMessages];
// packages/ai/src/types.ts:1003
export type Message = UserMessage | DeveloperMessage | AssistantMessage | ToolResultMessage;
```

Discriminate on `role`. All from `packages/ai/src/types.ts`:

### 2.1 Role variants

```typescript
export interface UserMessage {
	role: "user";
	content: string | (TextContent | ImageContent)[];
	/** True if the message was injected by the system (e.g., auto-continue). */
	synthetic?: boolean;
	/** True when injected mid-turn as a steer ... */
	steering?: boolean;
	attribution?: MessageAttribution;        // "user" | "agent"
	providerPayload?: ProviderPayload;
	timestamp: number; // Unix timestamp in milliseconds
}

export interface DeveloperMessage {
	role: "developer";
	content: string | (TextContent | ImageContent)[];
	attribution?: MessageAttribution;
	providerPayload?: ProviderPayload;
	timestamp: number;
}

export interface AssistantMessage {
	role: "assistant";
	content: (
		| TextContent
		| ThinkingContent
		| RedactedThinkingContent
		| AnthropicFallbackContent
		| AnthropicServerToolContent
		| ImageContent
		| ToolCall
	)[];
	api: Api;
	provider: Provider;
	model: string;
	contextSnapshot?: ContextSnapshot;
	retryRecovery?: AssistantRetryRecovery;
	responseId?: string;
	upstreamProvider?: string;
	usage: Usage;
	stopReason: StopReason;   // "stop" | "length" | "toolUse" | "error" | "aborted"
	stopDetails?: StopDetails | null;   // { type: string; category?: string|null; explanation?: string|null }
	errorMessage?: string;
	errorClassificationMessage?: string;
	toolCallAbortMessages?: Record<string, string>;
	errorStatus?: number;
	errorId?: number;
	disabledFeatures?: string[];
	providerPayload?: ProviderPayload;
	timestamp: number;
	duration?: number; // Request duration in milliseconds
	ttft?: number;     // Time to first token in milliseconds
}

export interface ToolResultMessage<TDetails = unknown> {
	role: "toolResult";
	toolCallId: string;
	toolName: string;
	content: (TextContent | ImageContent)[]; // Supports text and images
	details?: TDetails;
	isError: boolean;
	attribution?: MessageAttribution;
	/** Timestamp when output was pruned (ms since epoch). Undefined if unpruned. */
	prunedAt?: number;
	providerMetadata?: ToolResultProviderMetadata;
	useless?: boolean;
	timestamp: number;
}
```

### 2.2 Content blocks

```typescript
export interface TextContent {
	type: "text";
	text: string;
	textSignature?: string;
}

export interface ThinkingContent {
	type: "thinking";
	thinking: string;
	thinkingSignature?: string;
	itemId?: string;
}

export interface RedactedThinkingContent {
	type: "redactedThinking";
	data: string;
}

export interface ImageContent {
	type: "image";
	data: string;      // base64 encoded image data
	mimeType: string;  // e.g., "image/jpeg", "image/png"
	detail?: "auto" | "low" | "high" | "original";
	providerFile?: ProviderFileReference;  // { provider: "openai"|"anthropic"|"google"; id?; uri?; expiresAt? }
	url?: string;
}

export interface ToolCall {
	type: "toolCall";
	id: string;
	name: string;
	arguments: Record<string, unknown>;
	[kStreamingPartialJson]?: string;   // Symbol key — NEVER appears in JSON
	thoughtSignature?: string;
	intent?: string;
	rawBlock?: string;
	customWireName?: string;
	providerMetadata?: ToolCallProviderMetadata;
}

// Anthropic-only blocks; safe for a transcript engine to render as opaque/skip:
export interface AnthropicFallbackContent { type: "fallback"; from: { model: string }; to: { model: string }; }
export interface AnthropicServerToolContent { type: "anthropicServerTool"; block: /* server_tool_use | web_search_tool_result | tool_search_tool_result */ ...; }
```

### 2.3 `Usage` (`packages/catalog/src/types.ts:95`)

```typescript
export interface Usage {
	input: number;        // non-cached input tokens
	output: number;       // total output tokens incl. thinking + tool-call args
	cacheRead: number;
	cacheWrite: number;
	totalTokens: number;  // input + output + cacheRead + cacheWrite (+ orchestration)
	contextTokens?: number;
	orchestration?: { input?: number; cacheRead?: number; output?: number };
	premiumRequests?: number;
	reasoningTokens?: number;  // undefined means unknown, NOT zero
	cttl?: { ephemeral5m?: number; ephemeral1h?: number };
	server?: { webSearch?: number; webFetch?: number };
	cost: { input: number; output: number; cacheRead: number; cacheWrite: number; total: number };
}
```

### 2.4 Custom roles the coding agent merges in (WILL appear in `get_messages_page`)

`packages/coding-agent/src/session/messages.ts:1004–1016`:

```typescript
declare module "@oh-my-pi/pi-agent-core" {
	interface CustomAgentMessages {
		bashExecution: BashExecutionMessage;
		pythonExecution: PythonExecutionMessage;
		custom: CustomMessage;
		hookMessage: HookMessage;
		branchSummary: BranchSummaryMessage;
		compactionSummary: CompactionSummaryMessage;
		fileMention: FileMentionMessage;
	}
}
```

Shapes (same file, plus `packages/agent/src/compaction/messages.ts` for the summary types):

```typescript
export interface BashExecutionMessage {
	role: "bashExecution";
	command: string;
	output: string;
	exitCode: number | undefined;
	cancelled: boolean;
	truncated: boolean;
	meta?: OutputMeta;
	timestamp: number;
	excludeFromContext?: boolean;
}
export interface PythonExecutionMessage {
	role: "pythonExecution";
	code: string;
	output: string;
	exitCode: number | undefined;
	cancelled: boolean;
	truncated: boolean;
	meta?: OutputMeta;
	timestamp: number;
	excludeFromContext?: boolean;
}
export interface CustomMessage<T = unknown> {
	role: "custom";
	customType: string;
	content: CustomMessageContent;   // string | (TextContent | ImageContent)[]
	display: boolean;
	details?: T;
	attribution?: MessageAttribution;
	timestamp: number;
}
// HookMessage: identical to CustomMessage but role: "hookMessage" (legacy)
export interface FileMentionMessage {
	role: "fileMention";
	files: Array<{
		path: string;
		content: string;
		lineCount?: number;
		byteSize?: number;
		skippedReason?: "tooLarge" | "binary";
		image?: ImageContent;
	}>;
	timestamp: number;
}
export interface BranchSummaryMessage {
	role: "branchSummary";
	summary: string;
	fromId: string;
	timestamp: number;
}
export interface CompactionSummaryMessage {
	role: "compactionSummary";
	summary: string;
	shortSummary?: string;
	tokensBefore: number;
	tokensAfter?: number;
	method?: string;
	providerPayload?: ProviderPayload;
	blocks?: (TextContent | ImageContent)[];
	images?: ImageContent[];
	warning?: string;
	timestamp: number;
}
```

Swift decoder rule: switch on `role` over 11 known values; treat unknown roles as opaque (render timestamp + raw JSON) rather than failing.

### 2.5 `get_messages_page` response — `packages/coding-agent/src/modes/rpc/rpc-messages.ts`

```typescript
export interface RpcMessagesPage {
	messages: AgentMessage[];
	nextCursor?: string;   // opaque base64url; absent on the last page
	totalMessages: number;
}
```

Page limit 1–256 (default 100), page byte budget 768 KiB. Failure `code`s on the error response (`rpc-messages.ts:13`): `"session_busy"` (retry later) and `"stale_cursor"` (session/leaf/messageCount changed — restart paging from no cursor).

## 3. How streaming deltas compose into a final message

### 3.1 What the loop guarantees

`agent-loop.ts:1831–1883`: the first stream event (`start`) produces `message_start` with the empty partial. Every subsequent block event produces `message_update` where **`event.message` and `event.assistantMessageEvent.partial` are the same immutable, deep-cloned snapshot** of the full partial message (comment at `agent-loop.ts:1837–1840`). Terminal `done`/`error` become `message_end` with the finalized message. RPC forwards these verbatim, so every `message_update` frame already contains the complete current message state.

### 3.2 Recommended Swift reducer: snapshot replacement

```
on message_start(m):            transcript.append(m); inflight = last index
on message_update(m, _):        transcript[inflight] = m        // full replace
on message_end(m):              transcript[inflight] = m; inflight = nil
```

This is correct, ordering-proof, and immune to every provider quirk. Use `assistantMessageEvent.type` + `contentIndex`/`delta` only for UI animation (e.g. typewriter append of `delta` to the visible text of block `contentIndex`).

### 3.3 Delta-accumulation reducer (if you must avoid re-parsing snapshots)

Semantics, verified against the Anthropic provider (`packages/ai/src/providers/anthropic.ts:2390–2560`):

```
state: msg = AssistantMessage(content: [])

start                 -> msg = event.partial  (adopt metadata: model/provider/usage/timestamp)
text_start(i)         -> ensure msg.content[i] = { type:"text", text:"" }
text_delta(i, d)      -> msg.content[i].text += d
text_end(i, content)  -> msg.content[i].text = content          // authoritative
thinking_start(i)     -> ensure msg.content[i] = { type:"thinking", thinking:"" }
thinking_delta(i, d)  -> msg.content[i].thinking += d
thinking_end(i, c)    -> msg.content[i].thinking = c            // signature arrives only in snapshots
toolcall_start(i)     -> ensure msg.content[i] = { type:"toolCall", id:"", name:"", arguments:{} }
                         // id/name are already set in event.partial.content[i] — copy from there
toolcall_delta(i, d)  -> partialJson[i] += d   // d is a raw JSON fragment of the arguments object
toolcall_end(i, tc)   -> msg.content[i] = tc                    // authoritative parsed arguments
image_end(i, img)     -> msg.content[i] = img
message_end(m)        -> msg = m   // ALWAYS take the final message wholesale: usage, stopReason,
                                   // errorMessage, signatures, macro rewrites land only here
```

**Caveats that make pure accumulation unsafe without the `ensure`/final-adopt steps:**

1. **Blocks can appear in `content` with no `*_start` event.** `redactedThinking` and `anthropicServerTool` blocks are pushed into the partial silently (`anthropic.ts:2421–2451`). So `contentIndex` must be applied against the actual `content` array of the latest partial, never against a count of `_start` events you observed. The `ensure` step should grow/patch from `event.partial.content` when the local array disagrees.
2. **Tool-call `arguments` during streaming are best-effort.** The accumulating raw JSON lives under a Symbol key (`kStreamingPartialJson`) that **never serializes to JSON**, and `arguments` in the partial is only refreshed at throttled parse points (`anthropic.ts:2537–2543`). Authoritative arguments arrive in `toolcall_end.toolCall.arguments` and in the `message_end` message. If you want live streaming args, accumulate `toolcall_delta.delta` yourself and best-effort-parse.
3. **Thinking signatures (`signature_delta`) mutate the partial without any dedicated outer event type** — another reason `message_end` must replace wholesale.
4. The loop may rewrite the final message after streaming (`transformAssistantMessage` macro expansion, `beforeToolCall` arg revisions are written back into the toolCall blocks before `message_end` — `agent-loop.ts:1794–1819`), so the `message_end` payload can differ from the sum of deltas. Final state always comes from `message_end`.
5. On abort/error mid-stream, incomplete trailing blocks may be dropped; the `message_end` message (stopReason `"aborted"`/`"error"`, possibly `errorMessage`, retained completed toolCalls) is the truth.

## 4. Subagent frames

### 4.1 Frame envelopes — `packages/coding-agent/src/modes/rpc/rpc-types.ts:348–365` (verbatim)

```typescript
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

export type RpcSubagentFrame = RpcSubagentLifecycleFrame | RpcSubagentProgressFrame | RpcSubagentEventFrame;

export type RpcSessionEventFrame = AgentSessionEvent | RpcSubagentFrame;
```

### 4.2 Payloads — `packages/coding-agent/src/task/types.ts:67–104` (this is the definition the RPC frames use; `rpc-subagents.ts` imports from `../../task`)

```typescript
/** Payload emitted on TASK_SUBAGENT_PROGRESS_CHANNEL */
export interface SubagentProgressPayload {
	index: number;
	agent: string;
	agentSource: AgentSource;            // "bundled" | "user" | "project"
	task: string;
	parentToolCallId?: string;
	assignment?: string;
	progress: AgentProgress;
	sessionFile?: string;
	detached?: boolean;
}

/** Payload emitted on TASK_SUBAGENT_EVENT_CHANNEL */
export interface SubagentEventPayload {
	id: string;
	event: AgentSessionEvent;            // the child's OWN full session event, recursively this same union
}

/** Payload emitted on TASK_SUBAGENT_LIFECYCLE_CHANNEL */
export interface SubagentLifecyclePayload {
	id: string;
	agent: string;
	agentSource: AgentSource;
	description?: string;
	status: "started" | "completed" | "failed" | "aborted";
	sessionFile?: string;
	parentToolCallId?: string;
	index: number;
	detached?: boolean;
}
```

`AgentProgress` (same file, lines 398–471) — the live gauge object; key fields: `index`, `id`, `agent`, `agentSource`, `status: "pending" | "running" | "completed" | "failed" | "aborted"`, `task`, `assignment?`, `description?`, `lastIntent?`, `currentTool?`, `currentToolArgs?`, `currentToolStartMs?`, `recentTools: Array<{ tool; args; endMs }>`, `recentOutput: string[]`, `toolCount`, `requests`, `tokens` (lifetime billing volume), `contextTokens?` (compare against `contextWindow?` for a fullness gauge), `cost` (USD), `durationMs`, `modelOverride?`, `modelRole?`, `resolvedModel?` (`<provider>/<id>[:<thinkingLevel>]`), `resolvedModelIsFallback?`, `extractedToolData?`, `retryState?: { attempt; maxAttempts; delayMs; errorMessage; startedAtMs }`, `retryFailure?: { attempt; errorMessage }`, `inflightTaskDetails?: TaskToolDetails`.

### 4.3 Gating — frames are OFF by default

`rpc-subagents.ts:210–246`: lifecycle + progress frames are emitted only when the subscription level is not `"off"`; `subagent_event` frames only at level `"events"`. Set it with the RPC command (`rpc-types.ts:47`, `:165`):

```typescript
| { id?: string; type: "set_subagent_subscription"; level: RpcSubagentSubscriptionLevel }
export type RpcSubagentSubscriptionLevel = "off" | "progress" | "events";
```

A transcript engine that never sends `set_subagent_subscription` receives no subagent frames. Correlate frames to the parent transcript via `parentToolCallId` (matches the `task` tool call's `toolCallId`); terminal lifecycle statuses are everything except `"started"`.

### 4.4 Wire-package mirror (collab guests only)

`packages/wire/src/index.ts:254–295` defines **trimmed** `SubagentProgressPayload` / `SubagentLifecyclePayload` / `AgentProgress` (no `agentSource`, no `detached`, no `retryState`/`extractedToolData`/`inflightTaskDetails`). These are the shapes mirrored to collab-web guests over the sealed frame channel, and guests only get `BusChannel = "task:subagent:progress" | "task:subagent:lifecycle"` — no `subagent_event`. For the RPC stdout stream, model the richer `task/types.ts` shapes; the wire shapes are a structural subset, so a decoder built for `task/types.ts` with all extra fields optional parses both.


---

## Extraction caveats

1) Two SubagentPayload definitions exist: packages/coding-agent/src/task/types.ts (rich; what rpc-subagents.ts imports and what rides RPC stdout frames) and packages/wire/src/index.ts (trimmed mirror for collab-web guests). I verified the rpc-subagents.ts import resolves to ../../task. Model the task/types.ts shapes with extra fields optional and both parse. 2) `tool_execution_*` payloads are typed `any` in the core union; the actual runtime shape is the coerced AgentToolResult quoted in §1.4 — `details` is tool-specific and should be decoded as opaque JSON per tool. 3) `Effort` is a TypeScript `const enum` — values serialize as the string literals shown ("minimal"…"max"). 4) `message_update` snapshot-sharing (event.message === assistantMessageEvent.partial) is an in-process aliasing detail; after JSON serialization they are two identical copies. 5) `AgentRunSummary`/`AgentRunCoverage` on agent_end (telemetry-gated, from packages/agent/src/run-collector.ts) were not expanded — absent unless telemetry is configured; treat as opaque. 6) The repo is a scratchpad checkout dated ~Aug 2026; verify against the pinned oh-my-pi version your Swift client will actually speak to, since these unions are not versioned on the wire beyond RPC protocolVersion 2. 7) `subagent_event.payload.event` recursively contains the child's full AgentSessionEvent — including its own message_update partials — so the same reducer applies per subagent id.
