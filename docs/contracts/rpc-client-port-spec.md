<!-- Extracted 2026-08-24 from oh-my-pi v18.0.4 checkout (github.com/can1357/oh-my-pi). Regenerate on omp version bumps. Verified against OmpKit tests 2026-08-24. -->

# omp-rpc `RpcClient` — Swift Port Specification

Source of truth: `/private/tmp/claude-501/-Users-tannerpham-CS-Projects/c47436ce-aa27-45cc-8fdd-87aaa0fecbfb/scratchpad/oh-my-pi/python/omp-rpc/src/omp_rpc/client.py` (2155 lines) and `.../tests/test_client.py` (1692 lines), read in full. The Swift port is an `actor RpcClient`; this document describes the Python reference's observable semantics. Python's threading mechanics (background reader threads, per-request queues, worker threads) are described so the actor can preserve the *semantics*, not the mechanics.

---

## 0. Module constants (quote these exactly)

| Constant | Value |
|---|---|
| `_ASYNC_COMMANDS` | `{"prompt", "abort_and_prompt"}` |
| `_DEFAULT_ERROR_HISTORY_LIMIT` | `128` |
| `_TODO_STATUS_VALUES` | `{"pending", "in_progress", "completed", "abandoned"}` |
| `_MAX_RPC_FRAME_BYTES` | `1024 * 1024` = 1,048,576 |
| `_MAX_RPC_REASSEMBLED_BYTES` | `64 * 1024 * 1024` = 67,108,864 |
| `_RPC_CHUNK_PAYLOAD_BYTES` | `256 * 1024` = 262,144 |
| `_RPC_MESSAGES_PAGE_BUSY_ERROR` | `"Cannot page messages while the session is changing"` |
| `_RPC_MESSAGES_PAGE_STALE_ERROR` | `"RPC message cursor is stale"` |
| `_RPC_MESSAGES_PAGE_FALLBACK_CODES` | `{"session_busy", "stale_cursor"}` |
| derived `max_chunk_count` | `(67108864 + 262144 - 1) // 262144` = **256** |
| default `_wait_for_agent_end` timeout | **60.0 s** (when caller passes `timeout=None`) |
| request id format | `"req_{n}"`, n starts at 1, monotonically increasing per client |

---

## 1. Public API surface

### 1.1 Error types (class hierarchy)

```
RpcError(RuntimeError)                 — base for everything below
├── RpcTimeoutError                    — server did not respond before a timeout
├── RpcProcessExitError                — process exited / transport died while work pending
├── RpcConcurrencyError                — overlapping prompt-lifecycle collectors
├── RpcCommandError                    — server returned success:false
│     fields: command: str, error: str, code: str|nil
│     message: f"{command}: {error}"
└── RpcProtocolError                   — unmatched RPC error response (recorded, rarely raised)
      fields: payload (dict copy), command: str|nil, request_id: str|nil, remote_error: str|nil
      message: fragments ["Received unmatched RPC error response", "for {command}"?, "(id={request_id})"?, ": {remote_error}"?] joined with " " — NOTE the space-join puts a space BEFORE the colon fragment, e.g. "Received unmatched RPC error response for prompt (id=req_1) : late failure"
```

`ValueError` is raised from the constructor for `max_event_history`/`max_stderr_chunks` `<= 0` (message `"{name} must be greater than zero"`; `None` = unbounded).

### 1.2 Value types

**`ListenerErrorEvent`** (frozen): `listener_kind: str`, `source_type: str|nil`, `listener: callable`, `error: exception`.

**`PromptTurn`** (frozen):
- `events: tuple[RpcAgentEvent, ...]` — every agent event observed for the run
- `messages: tuple[AgentMessage, ...]` — final message list (possibly reconstructed, see §1.13)
- `assistant_message: AssistantMessage|nil`
- `assistant_text: str|nil`
- `require_assistant_text() -> str` — raises `RpcError("Prompt completed without a text assistant message")` when `assistant_text` is nil.

**Type aliases**: `TodoSeed = str | TodoItem | Mapping`, `TodoPhaseSeed = TodoPhase | Mapping`. Listener aliases are `Callable[[EventType], None]` per event type (see §1.8).

### 1.3 Constructor (all keyword-only; defaults must be preserved)

```python
RpcClient(*,
  command: Sequence[str] | None = None,     # exact argv override; when set, _build_command returns it verbatim
  executable: str = "omp",
  provider: str | None = None,
  model: str | None = None,
  session_dir: str | Path | None = None,
  cwd: str | Path | None = None,             # working dir for the child; NOT part of argv
  env: Mapping[str, str] | None = None,      # overlaid on os.environ at spawn
  user: int | str | None = None,             # POSIX privilege drop, passed to Popen
  group: int | str | None = None,
  extra_groups: Sequence[int | str] | None = None,
  thinking: ThinkingLevel | None = None,
  append_system_prompt: str | None = None,
  provider_session_id: str | None = None,
  tools: Sequence[str] | None = None,        # () → --no-tools; non-empty → --tools a,b,c
  custom_tools: Sequence[HostTool] | None = None,   # default () after normalization
  host_uris: Sequence[HostUri] | None = None,       # default ()
  no_session: bool = False,
  no_skills: bool = False,
  no_rules: bool = False,
  no_title: bool | None = None,              # None = follow rpc_defaults
  rpc_defaults: bool = True,
  extra_args: Sequence[str] = (),
  startup_timeout: float = 30.0,
  request_timeout: float = 30.0,
  max_event_history: int | None = 10_000,
  max_stderr_chunks: int | None = 512,
)
```

### 1.4 Command builder (`command` property / `_build_command`)

If `command` was given → return it as a tuple, ignoring everything else. Otherwise build, in this exact order:

1. `executable`, `"--mode"`, `"rpc"`
2. `--provider {provider}` if provider truthy
3. `--model {model}` if model truthy
4. `--session-dir {session_dir}` if set
5. `--thinking {thinking}` if set
6. `--append-system-prompt {append_system_prompt}` if set
7. `--provider-session-id {provider_session_id}` if set
8. tools: if `tools is not None`: empty → `--no-tools`; else `--tools` + comma-joined names
9. `--no-session` / `--no-skills` / `--no-rules` if the corresponding flag is True
10. `--no-title` if (`no_title` is True) or (`no_title` is None and `rpc_defaults` is True)
11. all `extra_args` appended verbatim

Note `cwd`, `env`, `user`, `group`, `extra_groups` affect the spawn, not argv.

### 1.5 Properties

- `stderr: str` — concatenation of retained stderr chunks (bounded history, joined; thread-safe snapshot).
- `command: tuple[str, ...]` — see §1.4.
- `protocol_errors: tuple[RpcProtocolError, ...]` — snapshot of the bounded (128) protocol-error history.
- `listener_errors: tuple[ListenerErrorEvent, ...]` — snapshot of the bounded (128) listener-error history.

### 1.6 Lifecycle: `start()` (also `__enter__`) and `stop()` (also `__exit__`)

**`start() -> self`**, exact sequence:

1. If already started (`process` non-nil) → `RpcError("RPC client is already started")`.
2. Reset all session state: clear ready flag; `stopping=False`; `closed_error=None`; `ready_received=False`; `ready_event=None`; `protocol_version=1`; `protocol_v2_enabled=False`; **fresh chunk decoder**; clear event history, async-error history; `scheduled_agent_runs=0`; `completed_agent_runs=0`; `last_schedule_async_error_index=0`; fresh UI-request queue; clear stderr chunks; clear protocol-error and listener-error histories. (Registered listeners persist across restarts.)
3. Spawn subprocess: argv from §1.4; `cwd`; env = parent environment overlaid with the `env` mapping; `user`/`group`/`extra_groups` forwarded; stdin/stdout/stderr all pipes; **text mode, UTF-8, `errors="replace"`, line-buffered (`bufsize=1`)**; **`start_new_session=True`** (child leads its own session/process group).
4. Capture the child's process-group id immediately (`os.getpgid(pid)`, nil when unavailable or on `OSError`) — needed later because `getpgid` fails on a reaped pid.
5. Start two daemon reader threads: `"omp-rpc-stdout"` and `"omp-rpc-stderr"` (§3).
6. Wait for the ready signal up to `startup_timeout`. On timeout: capture `stderr`, call `stop()`, raise `RpcTimeoutError(f"Timed out waiting for RPC ready signal. Stderr: {stderr}")`.
7. If the wait was released but no ready frame was received (i.e., the transport closed first): let `error = closed_error`; capture stderr; `stop()`; then:
   - if `error` is an `RpcError` → re-raise it as-is (this is how a malformed startup frame surfaces, see test 30);
   - elif `error` non-nil → raise `RpcProcessExitError(f"RPC process stopped before ready: {error}. Stderr: {stderr}")` chained from it;
   - else → `RpcTimeoutError(f"Timed out waiting for RPC ready signal. Stderr: {stderr}")`.
8. **Protocol v2 negotiation** — triggered only when ALL of:
   - `ready_event.supported_protocol_versions` is non-nil and **contains 2**, and
   - `ready_event.max_frame_bytes == 1_048_576` (exact equality), and
   - `ready_event.max_reassembled_frame_bytes == 67_108_864` (exact equality).

   Then: set `_protocol_v2_enabled = True` **before** sending the request (this gates chunk acceptance in the reader — the negotiation *response itself* may arrive chunked); send `_request("negotiate_protocol", protocolVersion=2)`; if the response's `protocolVersion != 2` → `RpcError("RPC protocol v2 negotiation failed")`. Any exception in this block → `stop()` then re-raise. On success set `_protocol_version = 2` (this gates `get_messages` pagination).
9. If `custom_tools` non-empty → `set_custom_tools(...)` (registers with the server). If `host_uris` non-empty → `set_host_uris(...)`.
10. Return self.

**`stop() -> None`** (idempotent; safe to call repeatedly):

1. No-op if not started.
2. `stopping = True`; set the cancel event of every pending host-tool call and host-URI request.
3. Close child stdin (ignore `OSError`) — the graceful-exit signal.
4. `_terminate_process_group(process, pgid)`:
   - **POSIX (killpg available, pgid captured)**: `killpg(pgid, SIGTERM)` ignoring `OSError` (ESRCH = group already empty, teardown is best-effort); `wait(timeout=1.0)` swallowing timeout; `killpg(pgid, SIGKILL)` ignoring `OSError`; `wait(timeout=1.0)` swallowing timeout. Signals the *whole group* so grandchildren (e.g. a `bun test` run spawned by the agent's bash tool) die with the leader — even when the leader already exited via the stdin-close path.
   - **Fallback (no killpg / no pgid, e.g. Windows)**: if leader alive: `terminate()`, `wait(1.0)`; on timeout `kill()`, `wait(1.0)`; swallow the final timeout.
5. In a `finally` block: close stdout and stderr pipes (ignore `OSError`); **call `_mark_closed(RpcProcessExitError("RPC process stopped"))` directly** — this is a deliberate fix: the stdout reader skips its own EOF `_mark_closed` when `stopping` is set, so without this call a thread blocked in `_wait_for_agent_end` would sleep until its full timeout (regression test 32). `_mark_closed` is idempotent. Then clear pending host-tool-call map, dispatch-name map, host-URI map; nil the process and pgid; join both reader threads with 1.0 s timeouts; nil the thread refs.

### 1.7 Request/response correlation (`_request`, `request_raw`)

`request_raw(command_type: str, **payload) -> JsonObject` is the public raw escape hatch; every typed command below goes through the same `_request`:

1. Require a live process, else `RpcError("RPC client is not started")`.
2. Allocate id `"req_{n}"`.
3. Envelope = `{"id": id, "type": command_type}` plus every payload key whose value is **not None** (None-valued keys are omitted; **`False`/`0`/`""` are kept** — test 4 depends on `enabled=False` surviving).
4. Register a pending entry `{command, single-slot response queue}` keyed by id.
5. Write the envelope (§3.2). On any write error: unregister the pending entry, re-raise.
6. Block on the response queue up to `request_timeout`. On timeout: unregister, raise `RpcTimeoutError(f"Timed out waiting for response to {command_type}. Stderr: {stderr}")`. (A response arriving later finds no pending entry and flows into the unmatched-response path §4.3.)
7. If the queue delivered an exception (transport death via `_fail_pending`) → raise it.
8. If `response["success"]` is falsy → `RpcCommandError(command=str(response.get("command", command_type)), error=str(response.get("error", "")), code=code if isinstance(code, str) else None)`.
9. `data` absent/None → return `{}`. Else deep-clone via `_clone_json_object`:
   - non-dict top level → `RpcError("RPC response payload must be an object")`
   - any non-string dict key → `RpcError("RPC payload objects must use string keys")`
   - any non-JSON value → `RpcError("RPC payload must be JSON-serializable")`

**Incoming `type:"response"` frames** are matched: (a) by `id` against the pending map — pop and deliver; (b) failing that, *error responses only* (`success` falsy, `command` is a string) are correlated to a pending request when **exactly one** pending request has that command — special case: `command == "parse"` matches when exactly one request of any command is pending (test 26: server replies without ids); (c) otherwise → unmatched-response handling (§4.3). Unmatched **successful** responses are silently dropped.

### 1.8 Event subscription

All `on_*` registrars return an **unsubscribe closure**; unsubscribing twice is a no-op (removal errors swallowed). Dispatch iterates a *copy* of the listener list; a listener that throws is recorded as a `ListenerErrorEvent` (bounded 128) and forwarded to `on_listener_error` listeners (whose own exceptions are swallowed) — a throwing listener never stops the client (test 28).

| Registrar | Fires for |
|---|---|
| `on_event(l)` | every parsed agent event |
| `on_notification(l)` | every parsed notification of any kind (fires before the type-specific routing, including for ready/UI/extension/unknown) |
| `on_ready(l)` | `ReadyEvent` |
| `on_agent_start` / `on_agent_end` / `on_turn_start` / `on_turn_end` / `on_message_start` / `on_message_update` / `on_message_end` / `on_tool_execution_start` / `on_tool_execution_update` / `on_tool_execution_end` / `on_auto_compaction_start` / `on_auto_compaction_end` / `on_auto_retry_start` / `on_auto_retry_end` / `on_retry_fallback_applied` / `on_retry_fallback_succeeded` / `on_ttsr_triggered` / `on_todo_reminder` / `on_todo_auto_clear` | typed listeners keyed by wire event-type string (`"agent_start"` … `"todo_auto_clear"`) — 19 typed registrars |
| `on_ui_request(l)` | `ExtensionUiRequest` (also enqueued to the UI-request queue) |
| `on_extension_error(l)` | `ExtensionError` |
| `on_unknown_notification(l)` | `UnknownNotification` (unrecognized type OR parse failure; carries `payload` + `parse_error`) |
| `on_protocol_error(l)` | recorded `RpcProtocolError`s (§4.3) |
| `on_listener_error(l)` | `ListenerErrorEvent`s |

Listener-kind strings used in `ListenerErrorEvent.listener_kind`: `"notification"`, `"ready"`, `"ui_request"`, `"extension_error"`, `"unknown_notification"`, `"event"`, `"typed_event"`, `"protocol_error"`, `"headless_ui_request"`.

### 1.9 Extension-UI plumbing

- `next_ui_request(timeout=None) -> ExtensionUiRequest` — blocking pop from the UI queue; empty after timeout → `RpcTimeoutError("Timed out waiting for an extension UI request")`.
- `send_ui_value(request_id, value)` → notification `{"type": "extension_ui_response", "id": request_id, "value": value}`.
- `send_ui_confirmation(request_id, confirmed)` → `{"type": "extension_ui_response", "id": ..., "confirmed": bool}`.
- `cancel_ui_request(request_id, *, timed_out=False)` → `{"type": "extension_ui_response", "id": ..., "cancelled": true}` plus `"timedOut": true` when `timed_out`.
- `install_headless_ui(*, on_request=None, confirm=False, select_value=None, input_value=None, editor_value=None) -> unsubscribe` — registers a `on_ui_request` handler that: first invokes `on_request` if given (exceptions recorded as listener errors with kind `"headless_ui_request"` and `source_type = request.type`); then routes by `request.method`:
  - `"cancel"` or `request.is_passive()` → ignore;
  - `"confirm"` → `send_ui_confirmation(request.id, confirm)` (default **False**);
  - `"select"` / `"input"` / `"editor"` → send the corresponding provided value, else `cancel_ui_request(request.id)`.

### 1.10 Typed commands (each is `_request` + response parsing)

| Method | RPC command | Payload keys sent | Returns / notes |
|---|---|---|---|
| `get_state()` | `get_state` | — | `SessionState` via `parse_session_state` |
| `set_fast_mode(enabled)` | `set_fast_mode` | `enabled` (bool, False kept) | `FastModeResult` |
| `set_model(provider, model_id)` | `set_model` | `provider`, `modelId` | `ModelInfo`; empty parse → `RpcError("set_model returned an empty payload")` |
| `cycle_model()` | `cycle_model` | — | `ModelCycleResult|nil` |
| `get_available_models()` | `get_available_models` | — | tuple of `ModelInfo` from `data.models`; absent/null/empty `models` coerces to `[]` (Python `payload.get("models") or []`), unparseable entries filtered out |
| `set_thinking_level(level)` | `set_thinking_level` | `level` | None |
| `cycle_thinking_level()` | `cycle_thinking_level` | — | `ThinkingLevelCycleResult|nil` |
| `set_steering_mode(mode)` | `set_steering_mode` | `mode` | None |
| `set_follow_up_mode(mode)` | `set_follow_up_mode` | `mode` | None |
| `set_interrupt_mode(mode)` | `set_interrupt_mode` | `mode` | None |
| `compact(custom_instructions=None)` | `compact` | `customInstructions` (omitted when None) | `CompactionResult` |
| `set_auto_compaction(enabled)` | `set_auto_compaction` | `enabled` | None |
| `set_auto_retry(enabled)` | `set_auto_retry` | `enabled` | None |
| `abort_retry()` | `abort_retry` | — | None |
| `bash(command)` | `bash` | `command` | `BashResult` |
| `abort_bash()` | `abort_bash` | — | None |
| `get_session_stats()` | `get_session_stats` | — | `SessionStats` |
| `export_html(output_path=None)` | `export_html` | `outputPath` (str or omitted) | `Path(str(data["path"]))` |
| `new_session(parent_session=None)` | `new_session` | `parentSession` | `CancellationResult` |
| `switch_session(session_path)` | `switch_session` | `sessionPath` (str) | `CancellationResult` |
| `branch(entry_id)` | `branch` | `entryId` | `BranchResult` |
| `get_branch_messages()` | `get_branch_messages` | — | tuple of `BranchMessage` |
| `get_last_assistant_text()` | `get_last_assistant_text` | — | `data.text` if str else nil |
| `set_session_name(name)` | `set_session_name` | `name` | None |
| `get_todos()` | (none — delegates) | — | `get_state().todo_phases` |
| `set_todos(todos)` | `set_todos` | `phases` (normalized, §1.14) | `parse_todo_phases(data.todoPhases)` |
| `clear_todos()` | — | — | `set_todos(())` |
| `get_messages()` | see §1.11 | — | tuple of `AgentMessage` |
| `get_messages_page(*, cursor=None, limit=None)` | `get_messages_page` | `cursor`, `limit` (None omitted) | `MessagesPage`; invalid `totalMessages` (non-int / bool / negative) → `RpcError("get_messages_page response has an invalid totalMessages")`; `nextCursor` non-nil non-str → `RpcError("get_messages_page response has an invalid nextCursor")` |
| `set_custom_tools(tools)` | `set_host_tools` | `tools`: list of `{name, label, description, parameters, hidden}` | stores the tuple; if not started, returns names without RPC. Response coercion is `payload.get("toolNames") or []` — an absent/null/empty `toolNames` becomes `[]` and returns `()` with NO error; `RpcError("set_host_tools response did not include toolNames")` fires only when the value is present, truthy, and not a list. Returns names stringified |
| `set_host_uris(host_uris)` | `set_host_uri_schemes` | `schemes`: list of `{scheme, writable, immutable}` + optional `description` | same not-started shortcut (returns schemes); same coercion: `payload.get("schemes") or []` — absent/null/empty → `()` with no error; `RpcError("set_host_uri_schemes response did not include schemes")` only for a truthy non-list |

### 1.11 `get_messages()` — v2 pagination with fallback

- **Protocol v1**: single `get_messages` request; parse `data.messages`.
- **Protocol v2** (`_protocol_version == 2`): page walk with `get_messages_page(cursor=cursor, limit=256)`:
  - track `total_messages` across pages; any page disagreeing → `RpcError("RPC message pagination returned an inconsistent total")`;
  - accumulate messages; `next_cursor == nil` → done; a cursor seen before → `RpcError("RPC message pagination repeated a cursor")`;
  - after the walk, `len(messages) != total_messages` → `RpcError("RPC message pagination ended before the advertised total")`.
  - **Fallback**: if the walk raises `RpcCommandError` where `error.command == "get_messages_page"` AND (`error.code ∈ {"session_busy", "stale_cursor"}` OR `error.error` equals one of the two exact strings `"Cannot page messages while the session is changing"` / `"RPC message cursor is stale"`) → discard the partial walk and fall through to the plain v1 `get_messages` request. Any other `RpcCommandError` → re-raise. (Note the internal `RpcError`s above are *not* caught — they propagate.)

### 1.12 Prompt / steering commands and run accounting

- `prompt(message, *, images=None, streaming_behavior=None)` — `_request("prompt", message=..., images=list|omitted, streamingBehavior=...)`, then **mark a run scheduled**: `scheduled_agent_runs += 1` and record `last_schedule_async_error_index = async_errors.current_index()`.
- `abort_and_prompt(message, *, images=None)` — same pattern (command `abort_and_prompt`), also marks a run scheduled.
- `steer(message, *, images=None)` / `follow_up(message, *, images=None)` — plain requests (`steer`/`follow_up`), no run accounting.
- `abort()` — plain `abort` request.
- A run **completes** when a terminal `agent_end` arrives: raw payload `type == "agent_end"` and `payload["isTerminal"] is not False` (absent counts as terminal). Completion increments `completed_agent_runs` and wakes waiters. A terminal `agent_end` that *fails to parse* also completes the run, additionally appending async error `RpcError(f"Failed to parse terminal agent_end: {exc}")` (test 22). A late error response for `prompt`/`abort_and_prompt` (§4.3) also completes the run.
- `_is_agent_idle()` ⇔ `scheduled_agent_runs == completed_agent_runs`.

**Single-flight lifecycle collectors** — `prompt_and_wait`, `wait_for_idle`, `collect_events` share a coordinator: at most one may be collecting at a time; a second concurrent call raises `RpcConcurrencyError(f"Cannot start {operation} while {active_operation} is already collecting prompt lifecycle events")`. Release only clears the slot if it still holds the same operation name.

- `prompt_and_wait(message, *, images=None, streaming_behavior=None, timeout=None) -> PromptTurn`: acquire `"prompt_and_wait"`; snapshot current event index and async-error index; `prompt(...)`; `_wait_for_agent_end(...)`; build `PromptTurn` (§1.13); release in `finally`.
- `wait_for_idle(timeout=None)`: acquire `"wait_for_idle"`; if idle → check async errors recorded since the last scheduled run (raise the first, if any) and return; else wait for agent end from the current indices; release in `finally`.
- `collect_events(timeout=None) -> tuple[RpcAgentEvent, ...]`: acquire `"collect_events"`; wait for agent end from current indices; release in `finally`.

**`_wait_for_agent_end(start_index, start_async_error_index, timeout)`** — deadline = now + (timeout ?? **60.0**); loop under the event condition:

1. `closed_error` set → raise `RpcProcessExitError(str(closed_error))`.
2. `start_index < events.offset` (history trimmed past our snapshot) → `RpcError("Event history limit was exceeded while waiting for agent_end. Increase max_event_history to retain more streamed events.")`.
3. `start_async_error_index < async_errors.offset` → `RpcError("Async error history limit was exceeded while waiting for agent_end. Increase max_event_history if your host needs to retain more background failures.")`.
4. Any async errors appended since the snapshot → raise the first one.
5. Snapshot the raw event payloads since `start_index`; if any has `type == "agent_end"` with `isTerminal is not False` → **re-parse every snapshot payload** through `parse_notification` and return them as the events tuple. (Returning freshly parsed copies is what makes listener mutation of streamed events harmless — test 25.)
6. Otherwise: remaining time ≤ 0 → `RpcTimeoutError(f"Timed out waiting for agent_end. Stderr: {stderr}")`; else wait on the condition for the remaining time.

Note the event history stores **cloned raw JSON payloads** of agent events only (ready/UI/extension-error/unknown notifications are not appended).

### 1.13 `PromptTurn` construction and compacted-terminal reconstruction

`_build_prompt_turn(events)`:
1. Scan `events` backwards for the last `AgentEndEvent`; `final_messages = _complete_agent_end_messages(events_before_it, terminal)`.
2. `assistant_message` = last message in `final_messages` whose `role == "assistant"`; if none, fall back to scanning `events` backwards for any event with a `message` attribute whose dict has `role == "assistant"`.
3. `assistant_text = assistant_text(assistant_message)` when present.

`_complete_agent_end_messages(events, terminal)`:
- If `terminal.message_count` is nil or `<= len(terminal.messages)` → return `terminal.messages` unchanged.
- Else the agent_end was compacted: find the run start (index just after the last `AgentStartEvent` in `events`; 0 if none); collect `streamed_messages` = the `message` of every `MessageEndEvent` at/after run start; `streamed_prefix_count = terminal.message_count - len(terminal.messages)`; if `streamed_prefix_count > len(streamed_messages)` → `RpcError("Compacted agent_end references {streamed_prefix_count} streamed messages, but only {len(streamed_messages)} were retained")`; return `streamed_messages[:streamed_prefix_count] + terminal.messages`.

### 1.14 Todo normalization (`set_todos` input)

Input is a sequence of flat todo seeds and/or phase seeds. A seed **is a phase** when it is a `TodoPhase` instance, or a Mapping containing `"tasks"`, or a Mapping containing `"name"` but not `"content"`.

- Mixing: if *any* seed is a phase, *all* must be → else `RpcError("Cannot mix flat todo items with todo phases in one set_todos() call")`.
- Empty input → `[]`.
- All-flat input → wrapped in a single phase `{"id": "phase-1", "name": "Todos", "tasks": [...]}`.
- Task ids auto-generated as `"task-1"`, `"task-2"`, … from a single counter shared across the whole call; phase ids default to `"phase-{index}"` (1-based position).
- Flat item normalization:
  - `str` → `{"id": auto, "content": s, "status": "pending"}`.
  - `TodoItem` → status must be in `_TODO_STATUS_VALUES` else `RpcError(f"Unsupported todo status: {status}")`; `{"id": item.id or auto, "content", "status", "notes", "details", "blocker"}`.
  - Mapping → `content` must be a non-empty (after strip) string else `RpcError("Todo items must provide a non-empty 'content' value")`; status defaults `"pending"`, validated as above; `id` used only when a non-empty string, else auto; `notes`/`details`/`blocker` kept only when strings, else nil.
- Phase normalization:
  - `TodoPhase` → `{"id": phase.id or "phase-{index}", "name": phase.name, "tasks": normalized}`.
  - Mapping → `name` must be a non-empty (after strip) string else `RpcError("Todo phases must provide a non-empty 'name' value")`; `tasks` defaults `()`; must be a sequence and not str/bytes else `RpcError("Todo phase 'tasks' must be a sequence")`; `id` non-empty string or `"phase-{index}"`.

### 1.15 Host tools (server → client callbacks)

Incoming `host_tool_call` frame: `{id, toolName, toolCallId, arguments}`.

1. If `id`/`toolName`/`toolCallId` are not all strings → silently ignore the frame.
2. **Record `toolCallId → toolName` in the dispatch-name map BEFORE argument validation.** This map powers event renaming (below).
3. `arguments` not a Mapping → reply `{"type": "host_tool_result", "id": id, "result": {"content": [{"type": "text", "text": "Host tool arguments must be an object"}], "details": {}}, "isError": true}` and stop.
4. Tool name not among registered `custom_tools` → same error shape with text `'Host tool "{toolName}" is not registered'`.
5. Otherwise register a pending call (with a cancel event) keyed by `id`, and run the tool on a background worker (thread name `"omp-rpc-host-tool:{toolName}"`):
   - `params = tool.parse_params(arguments)`; context exposes `tool_call_id`, the cancel event, and `send_update(result)` which emits `{"type": "host_tool_update", "id": id, "partialResult": result}`.
   - On success (and not cancelled): `{"type": "host_tool_result", "id": id, "result": normalize(result)}` where normalize maps `str → {"content": [{"type": "text", "text": s}]}`, Mapping → shallow dict copy, anything else → `RpcError("Host tool handlers must return a string or a result mapping")` (caught by the worker's error path).
   - On exception (and not cancelled): error result `{"content": [{"type": "text", "text": str(exc)}], "details": {}}` with `"isError": true`.
   - If cancelled at completion time: send nothing.
   - Always unregister the pending call.

`host_tool_cancel` frame `{targetId}`: string targetId → set that pending call's cancel event (no reply).

**Event renaming** (`tool_execution_update` / `tool_execution_end` frames, applied before notification parsing): with a string `toolCallId`, look it up in the dispatch-name map — `tool_execution_end` **pops** the entry, `tool_execution_update` **peeks** — and when found, overwrite the frame's `toolName` with the host tool's name. Rationale: with `tools.xdev` the agent invokes custom tools through the transport tool `write` (`xd://` device), so wire events carry `write`; the `host_tool_call` frame carries the outer `toolCallId`, letting update/end events be renamed to the executed host tool. `tool_execution_start` precedes `host_tool_call` on the wire and therefore **keeps the transport name** (tests 7, 8).

### 1.16 Host URIs (server → client callbacks)

Incoming `host_uri_request` frame: `{id, operation, url, content?}`.

1. `id`/`operation`/`url` not all strings → silently ignore.
2. `operation` not `"read"`/`"write"` → error reply `{"type": "host_uri_result", "id": id, "error": f"Unsupported host URI operation: {operation}", "isError": true}`.
3. Parse the URL; on parse failure → error `f"Could not parse host URI: {url}"`.
4. Match lowercased scheme against registered `host_uris`; none → error `'Host URI scheme "{scheme}://" is not registered'`.
5. `write` with no write handler → error `'Host URI scheme "{scheme}://" was not registered with a write handler'`.
6. Else register a pending request (cancel event) and run on a worker (`"omp-rpc-host-uri:{scheme}:{operation}"`):
   - `read`: `uri.read(url, ctx)` → if not cancelled, reply `{"type": "host_uri_result", "id": id, **normalize_read_result(value)}`.
   - `write`: content = `str(raw_content)` when the frame's `content` is present and non-null, else `""` (an explicit empty string stays `""`); `uri.write(url, content, ctx)` → if not cancelled, reply `{"type": "host_uri_result", "id": id}`.
   - Exception (not cancelled) → error reply with `str(exc)`. Always unregister.

`host_uri_cancel` `{targetId}` → set that pending request's cancel event.

---

## 2. Chunk-reassembly algorithm (`_RpcFrameDecoder`) — exact pseudocode

One decoder instance per client session (recreated on every `start()`). State: `pending: Optional<PendingChunks>` where `PendingChunks = { chunk_id: String, count: Int, byte_length: Int, next_index: Int = 0, chunks: [Bytes], received_bytes: Int = 0 }`.

Every failure below raises `RpcError(<quoted message>)`. Because `push` is called from the stdout reader loop, **any decoder failure is terminal for the client** (the reader's exception handler calls `_mark_closed`). The decoder does not reset `pending` on failure — irrelevant in practice since the client dies.

```
CONST MAX_FRAME       = 1_048_576        // _MAX_RPC_FRAME_BYTES
CONST MAX_REASSEMBLED = 67_108_864       // _MAX_RPC_REASSEMBLED_BYTES
CONST CHUNK_PAYLOAD   = 262_144          // _RPC_CHUNK_PAYLOAD_BYTES
CONST MAX_CHUNK_COUNT = ceil(MAX_REASSEMBLED / CHUNK_PAYLOAD)   // = 256

func push(value: Any) -> JsonObject?     // nil = "sequence in progress, keep feeding"

  // ---- Non-chunk frame path ----
  if value is not a JSON object OR value["type"] != "rpc_chunk":
      if pending != nil:
          FAIL "RPC chunk sequence was interrupted"
          // any ordinary frame arriving mid-sequence aborts the client
      if value is not a JSON object:
          FAIL "RPC frame must be a JSON object"
      return value                       // complete single frame, passed through untouched

  // ---- Chunk frame path ----
  chunk_id    = value["chunkId"]
  index       = value["index"]
  count       = value["count"]
  byte_length = value["byteLength"]
  data        = value["data"]

  // Metadata validation — ALL must hold, single combined check:
  //   chunk_id: String, non-empty, length <= 128
  //   index:    Int (Python: reject bool masquerading as int), >= 0
  //   count:    Int (reject bool), >= 2, <= MAX_CHUNK_COUNT (256)
  //   index < count
  //   byte_length: Int (reject bool),
  //                >= MAX_FRAME  (!! chunking is only legal for logical frames
  //                               AT LEAST as large as the 1 MiB single-frame cap;
  //                               byteLength of exactly 1_048_576 is ACCEPTED —
  //                               that is the boundary test),
  //                <= MAX_REASSEMBLED
  //   data: String, non-empty
  if any check fails:
      FAIL "Invalid RPC chunk metadata"

  // Payload validation:
  chunk = base64_decode_strict(data)     // strict alphabet/padding validation
  if decode failed:
      FAIL "Invalid RPC chunk data"
  if base64_encode(chunk) != data:       // canonical-form round-trip check:
      FAIL "Invalid RPC chunk data"      // non-canonical encodings are rejected
  if len(chunk) > CHUNK_PAYLOAD:
      FAIL "RPC chunk payload exceeds the transport limit"

  // Sequence start:
  if pending == nil:
      if index != 0:
          FAIL "RPC chunk sequence must start at index 0"
      pending = PendingChunks(chunk_id, count, byte_length)   // next_index=0, empty

  // Continuation consistency (also trivially passes for the chunk that
  // just created `pending`):
  if pending.chunk_id != chunk_id
     OR pending.count != count
     OR pending.byte_length != byte_length
     OR pending.next_index != index:     // strictly sequential, no gaps/repeats
      FAIL "RPC chunk sequence mismatch"

  pending.chunks.append(chunk)
  pending.received_bytes += len(chunk)
  pending.next_index += 1

  if pending.received_bytes > pending.byte_length:
      FAIL "RPC chunk sequence exceeds its declared length"

  if pending.next_index < pending.count:
      return nil                         // sequence continues

  // Final chunk:
  if pending.received_bytes != pending.byte_length:
      FAIL "RPC chunk sequence length mismatch"

  completed = pending
  pending = nil                          // state reset BEFORE the decode attempt
  bytes = concat(completed.chunks)
  text  = utf8_decode(bytes)             // strict
  frame = json_parse(text)
  if utf8 decode or JSON parse failed:
      FAIL "Failed to decode reassembled RPC frame"
  if frame is not a JSON object:
      FAIL "RPC frame must be a JSON object"
  return frame
```

**Pre-decoder gate (lives in the reader loop, NOT the decoder):** a frame with `type == "rpc_chunk"` arriving while `_protocol_v2_enabled` is False raises `RpcError("RPC chunk received before protocol negotiation")` — terminal. (`_protocol_v2_enabled` flips True just before the `negotiate_protocol` request is sent, so the negotiation response itself may be chunked.)

Summary of the state machine:
- **Starts** a sequence: a valid chunk frame with `index == 0` while no sequence is pending.
- **Continues**: a valid chunk frame with identical `chunkId`/`count`/`byteLength` and `index == next expected`.
- **Completes**: continuation where `next_index` reaches `count` and accumulated bytes equal `byteLength` exactly; the joined bytes must UTF-8-decode and JSON-parse to an object.
- **Aborts (all terminal)**: any non-chunk frame mid-sequence; any metadata/validation failure; a first chunk with `index != 0`; any field mismatch or out-of-order index; over-length accumulation; final length mismatch; decode/parse failure of the reassembled frame.

---

## 3. Framing, buffering, decoding, process lifecycle

### 3.1 Spawn parameters

`subprocess.Popen(argv, cwd=..., env={**os.environ, **user_env}, user=..., group=..., extra_groups=..., stdin=PIPE, stdout=PIPE, stderr=PIPE, text=True, encoding="utf-8", errors="replace", bufsize=1, start_new_session=True)`.

Consequences the port must reproduce:
- The protocol is **newline-delimited JSON, UTF-8** in both directions.
- Invalid UTF-8 bytes from the child are **replaced** (U+FFFD), never fatal at the decode layer (malformed *JSON* is fatal, malformed *UTF-8* becomes replacement chars that then usually fail JSON parsing).
- `bufsize=1` = line-buffered writes on our side.
- `start_new_session=True`: the child leads a new session/process group; its pgid is captured immediately after spawn (before the child can be reaped) for group-wide teardown.

### 3.2 Writes (requests and notifications)

`_write_json(process, payload)`: serialize with `json.dumps`, write, write `"\n"`, flush — all under a **write lock** (one frame at a time; concurrent host-tool workers also write). `stdin` nil → `RpcProcessExitError("RPC process stdin is unavailable")`. `BrokenPipeError`/`OSError` → `RpcProcessExitError(f"Failed to write RPC command: {exc}")`.

`_send_notification(payload)` = require process + `_write_json` (no id, no response expected).

### 3.3 stdout reader loop (thread `"omp-rpc-stdout"`) — per-line dispatch order

```
line_number = 0
for line in stdout:                       # line iteration, text mode
    line_number += 1
    stripped = line.strip()
    if empty: continue                    # blank lines skipped silently
    raw = json.loads(stripped)
      on JSONDecodeError:
        snippet = stripped truncated to 240 chars (first 237 + "...")
        raise RpcError(f"Failed to decode RPC output on line {line_number}: {exc}. Frame: {snippet!r}")
        # escapes the loop -> _mark_closed -> TERMINAL
    if raw is dict AND raw["type"] == "rpc_chunk" AND not protocol_v2_enabled:
        raise RpcError("RPC chunk received before protocol negotiation")   # TERMINAL
    payload = frame_decoder.push(raw)     # may raise (TERMINAL)
    if payload is nil: continue           # chunk sequence in progress
    switch payload["type"]:
      "response"          -> _handle_response(payload); continue        # §1.7 / §4.3
      "host_tool_call"    -> _handle_host_tool_call(payload); continue  # §1.15
      "host_tool_cancel"  -> _handle_host_tool_cancel(payload); continue
      "host_uri_request"  -> _handle_host_uri_request(payload); continue  # §1.16
      "host_uri_cancel"   -> _handle_host_uri_cancel(payload); continue
    if type in ("tool_execution_update", "tool_execution_end"):
        rename toolName from dispatch map (§1.15)
    notification = parse_notification(payload)
      on TypeError/ValueError exc:
        notification = UnknownNotification(clone(payload), parse_error=str(exc))
        if type == "agent_end" AND payload["isTerminal"] is not False:
            append async error RpcError(f"Failed to parse terminal agent_end: {exc}")
            mark agent run completed          # wakes waiters with the async error
    dispatch "notification" listeners (all notifications, every kind)
    if ReadyEvent:        store it; ready_received = True; release the ready gate;
                          dispatch "ready" listeners; continue      # NOT appended to event history
    if ExtensionUiRequest: enqueue to UI queue; dispatch "ui_request" listeners; continue
    if ExtensionError:     dispatch "extension_error" listeners; continue
    if UnknownNotification: dispatch "unknown_notification" listeners; continue
    # remaining: an agent event
    append CLONED RAW PAYLOAD to event history (+ notify waiters)
    if AgentEndEvent AND event.is_terminal is not False:
        mark agent run completed
    dispatch "event" listeners (parsed event)
    dispatch "typed_event" listeners for event.type
# loop exit paths:
on exception exc:  _mark_closed(exc)                                  # TERMINAL
on clean EOF, if not stopping:
    exit_code = poll();  if nil -> wait(1.0)
      on wait timeout: _mark_closed(RpcProcessExitError("RPC process stdout closed before the process exited")); return
    _mark_closed(RpcProcessExitError(f"RPC process exited with code {exit_code}. Stderr: {stderr}"))
on clean EOF while stopping: do nothing (stop() already called _mark_closed)
```

### 3.4 stderr reader loop (thread `"omp-rpc-stderr"`)

Iterate stderr lines, appending each chunk to the bounded stderr history under the state lock. On exception while not stopping → `_mark_closed(RpcError(f"Failed to read RPC stderr: {exc}"))`.

### 3.5 `_mark_closed(error)` — the single terminal transition

Idempotent (first error wins; later calls return immediately). Effects: store `closed_error`; release the ready gate (so a `start()` blocked on ready proceeds to its failure branch); **fail every pending request** by delivering the error into its response queue and clearing the pending map; notify the event condition (waking `_wait_for_agent_end`, which then raises `RpcProcessExitError(str(closed_error))`).

### 3.6 Bounded histories (`_BoundedHistory`)

Ring-like list with `limit` (nil = unbounded), `items`, and `offset` (count of items trimmed from the front). `append` trims oldest items past the limit, incrementing `offset`. `current_index() = offset + len(items)` — a stable monotonically increasing logical index. `snapshot_from(start) = items[start - offset:]`. Consumers detect data loss by comparing their saved start index against `offset` (see §1.12 steps 2–3). Instances: event history (limit `max_event_history`, default 10,000), async errors (128), protocol errors (128), listener errors (128), stderr chunks (limit `max_stderr_chunks`, default 512).

### 3.7 What happens on…

| Situation | Behavior |
|---|---|
| **EOF on stdout** (child exited or closed the pipe) | Reader drains, then (unless stopping): reap exit code (wait ≤ 1.0 s) and `_mark_closed(RpcProcessExitError("RPC process exited with code {code}. Stderr: {stderr}"))`, or `"RPC process stdout closed before the process exited"` if the process lingers. All pending requests fail with that error; waiters wake. |
| **Child killed externally** | Same as EOF path once the pipe closes. |
| **Malformed (non-JSON) line** | Terminal: `RpcError("Failed to decode RPC output on line {n}: {err}. Frame: {snippet!r}")`, snippet capped at 240 chars. During startup this becomes the `start()` failure (test 30). |
| **Blank line** | Skipped silently. |
| **Unknown notification type / parse-failed notification** | Non-fatal: becomes `UnknownNotification` with `parse_error`; reader continues (tests 20, 21). Exception: a *terminal agent_end* that fails to parse also records an async error and completes the run (test 22). |
| **Write to dead child** | `RpcProcessExitError("Failed to write RPC command: {exc}")` from the calling method. |
| **`stop()` while a waiter is blocked** | Waiter raises `RpcProcessExitError` immediately (from `_mark_closed(RpcProcessExitError("RPC process stopped"))` called inside `stop()`), not after its timeout (test 32). |
| **`stop()` with live grandchildren** | Whole process group signalled (SIGTERM → SIGKILL); grandchildren die with the leader (test 33). |

---

## 4. Timeout and error taxonomy

### 4.1 Timeouts

| Timeout | Default | Applies to | On expiry |
|---|---|---|---|
| `startup_timeout` | 30.0 s | ready-signal wait in `start()` | `stop()` + `RpcTimeoutError("Timed out waiting for RPC ready signal. Stderr: {stderr}")` — client not started |
| `request_timeout` | 30.0 s | every `_request` response wait | pending entry removed; `RpcTimeoutError("Timed out waiting for response to {command}. Stderr: {stderr}")`; **client stays alive** |
| `prompt_and_wait` / `wait_for_idle` / `collect_events` `timeout` param | `None` → **60.0 s** | `_wait_for_agent_end` | `RpcTimeoutError("Timed out waiting for agent_end. Stderr: {stderr}")`; client stays alive |
| `next_ui_request(timeout)` | `None` = block forever | UI queue pop | `RpcTimeoutError("Timed out waiting for an extension UI request")` |
| internal 1.0 s waits | fixed | process reaping in teardown/EOF, reader-thread joins | best-effort escalation/skip |

### 4.2 Recoverable vs terminal

**Recoverable** (the client remains usable):
- `RpcCommandError` — a single command failed (`success: false`). Includes late async prompt failures surfaced through the async-error channel.
- `RpcTimeoutError` from `_request` / `_wait_for_agent_end` / `next_ui_request` — that call gave up; transport still alive. (A stale response arriving after a request timeout flows into the unmatched path §4.3.)
- `RpcConcurrencyError` — the second collector is refused; the first proceeds.
- `RpcError` from input validation (`set_todos` seeds, history-limit config `ValueError`, mixed phases, response-shape validation like `"set_host_tools response did not include toolNames"`, pagination consistency errors).
- Listener exceptions — recorded as `ListenerErrorEvent` + forwarded; never propagate (test 28).
- Unknown/unparseable notifications — demoted to `UnknownNotification`; reader continues (tests 20, 21).
- Async `RpcError("Failed to parse terminal agent_end: …")` — raised to the current waiter; the client itself lives (test 22).
- `RpcProtocolError` — recorded and dispatched to listeners, never raised into user calls.

**Terminal** (routed through `_mark_closed`; every pending request fails, every waiter raises `RpcProcessExitError`, only remedy is `stop()` + fresh `start()`):
- Malformed JSON line on stdout.
- Any `_RpcFrameDecoder` failure (all §2 FAIL messages).
- `"RPC chunk received before protocol negotiation"`.
- Process EOF / exit (`"RPC process exited with code {n}. Stderr: …"`, `"RPC process stdout closed before the process exited"`).
- stderr read failure (`"Failed to read RPC stderr: {exc}"`).
- Write failure (`RpcProcessExitError` raised at the call site; the reader will independently observe the dead pipe).
- `stop()` itself (`"RPC process stopped"`).
- Startup failures: ready timeout, pre-ready process death, v2 negotiation failure (all leave the client stopped).

### 4.3 Unmatched error-response handling (the `RpcProtocolError` path)

For an incoming `type:"response"` frame that matches no pending id:

1. If `success` is falsy and `command` is a string and **exactly one** pending request has that command → deliver the error response to it (it will raise `RpcCommandError` in the caller). Special case: `command == "parse"` matches when exactly one request (of any command) is pending. (Covers servers that reply without echoing ids — test 26.)
2. Otherwise, if the frame is a failure response, build an `RpcProtocolError` from it.
3. If its `command ∈ {"prompt", "abort_and_prompt"}` and it carries a string `error`: append async `RpcCommandError(command, remote_error)` **and mark the agent run completed** — this is how a "success then late failure" prompt surfaces as an `RpcCommandError` raised from `prompt_and_wait` (test 27).
4. Record the `RpcProtocolError` (bounded history, `protocol_errors` property) and dispatch `on_protocol_error` listeners.
5. Unmatched **successful** responses are dropped silently.

---

## 5. Test inventory — `tests/test_client.py` (33 tests, mirror all in Swift)

Common fixture: `make_client(server=FAKE_SERVER, **kwargs)` = `RpcClient(command=[sys.executable, "-u", "-c", server], startup_timeout=2.0, request_timeout=2.0, **kwargs)`. The fake servers are inline Python scripts; the Swift test suite must either spawn the same scripts via `python3 -u -c` or reimplement them byte-compatibly. FAKE_SERVER magic prompt strings: `"slow"` (0.3 s delay mid-turn), `"all events"` (emits every event type), `"compacted turn"` (agent_end with `messageCount: 2`, one message), `"notifications"` (extension_error + unknown event before the turn), `"needs ui"`/`"needs confirm"`/`"needs cancel"` (UI requests: input/confirm/editor; any `extension_ui_response` triggers a `"ui acknowledged"` turn), `"needs host tool"`/`"needs xd host tool"` (host-tool dispatch, direct vs via `write` transport). Every normal turn answers `"pong"`.

Porter quirks to know: FAKE_SERVER has a duplicate dead `set_host_tools` elif branch (first wins). `INVALID_JSON_SERVER` (a server emitting `{"type":"broken"` after ready) is **defined but referenced by no test** — port it or drop it knowingly.

| # | Test | Server / setup | Exact behavior asserted |
|---|---|---|---|
| 1 | `test_protocol_v2_decoder_accepts_exact_logical_boundary` | No subprocess; a bare `_RpcFrameDecoder`. Builds a response frame padded so its compact JSON encoding is exactly 1,048,576 bytes; splits into 256 KiB chunks (4 chunks, `chunkId "exact-boundary"`). | Feeding all chunks returns the original frame dict (`byteLength == 1 MiB` exactly is accepted — lower boundary of the chunk path). |
| 2 | `test_command_builder_supports_common_rpc_options` | No start. Client with `executable="omp"`, model, `cwd="/tmp/workspace"`, `thinking="high"`, `append_system_prompt`, `provider_session_id`, `tools=("read","edit","write")`, `no_session/no_skills/no_rules=True`, `extra_args=("--foo","bar")`. | `.command` equals the exact tuple `("omp","--mode","rpc","--model",…,"--tools","read,edit,write","--no-session","--no-skills","--no-rules","--no-title","--foo","bar")`. Note `cwd` absent from argv; `--no-title` implied by `rpc_defaults=True`. |
| 3 | `test_get_state_and_bash` | FAKE_SERVER. | `get_state()`: `session_id=="fake-session"`, `model.id=="claude-sonnet-4-5"`, `fast_mode_enabled` False, `fast_mode_active` True, `tokens_per_second==7.25`. `bash("echo hello")`: `output=="hello\n"`, `exit_code==0`. |
| 4 | `test_set_fast_mode_preserves_provider_tier_state` | FAKE_SERVER (server errors unless `enabled` arrives as a real bool). | `set_fast_mode(False)` → `result.enabled` False, `result.active` True. Proves `False` is not dropped from the request envelope (only `None` is omitted). |
| 5 | `test_prompt_and_wait_returns_assistant_text` | FAKE_SERVER. | `prompt_and_wait("say hello", timeout=2.0)`: `require_assistant_text()=="pong"`; `len(turn.events) >= 3`. |
| 6 | `test_prompt_and_wait_reconstructs_compacted_terminal_messages` | FAKE_SERVER, prompt `"compacted turn"` (agent_end has `messages=[terminal]`, `messageCount=2`). | `turn.messages` texts `== ["pong", "terminal"]` (streamed message_end prefix + terminal messages); `require_assistant_text()=="terminal"`. |
| 7 | `test_custom_tools_are_registered_and_executed_via_rpc` | FAKE_SERVER; `custom_tools=(host_tool "echo_host")` whose execute calls `context.send_update(f"working:{msg}")` then returns `f"host:{msg}"`. Prompt `"needs host tool"`. | `get_state().dump_tools[-1].name == "echo_host"` (registration reached the server). Turn has exactly 1 `tool_execution_update` with `partial_result["content"][0]["text"]=="working:hello"` and exactly 1 `tool_execution_end` with `result["content"][0]["text"]=="host:hello"` (full round trip: host_tool_call → update/result notifications → server echoes tool events + agent_end). |
| 8 | `test_xd_dispatched_custom_tool_events_carry_host_tool_name` | Same tool; prompt `"needs xd host tool"` — server emits `tool_execution_start` (toolName `"write"`, toolCallId `"toolu_write_1"`) *then* `host_tool_call` (toolName `"echo_host"`, same toolCallId). | Start names `== ["write"]` (start precedes host_tool_call — keeps transport name); update names `== ["echo_host"]`; end names `== ["echo_host"]` (renamed via dispatch map); `end.tool_call_id=="toolu_write_1"`; end result text `"host:hello"`. |
| 9 | `test_extension_ui_round_trip` | FAKE_SERVER; prompt `"needs ui"`. | `next_ui_request(2.0).method=="input"`; `send_ui_value(id,"approved")`; `wait_for_idle(2.0)` completes (server answers any UI response with a full turn). |
| 10 | `test_install_headless_ui_cancels_interactive_requests` | FAKE_SERVER; `install_headless_ui(on_request=collect method)`. `prompt_and_wait("needs ui", 2.0)`. | `seen_methods == ["input"]`; the input request was auto-cancelled (no `input_value` given), the resulting turn completed the wait. |
| 11 | `test_ready_and_typed_event_listeners` | FAKE_SERVER; register `on_ready`, `on_notification`, `on_turn_start`, `on_message_update`, `on_agent_end` **before** `start()`. Then start + `prompt_and_wait("say hello")` + stop. | `ready_types == ["ready"]`; typed order exactly `["turn_start","message_update","agent_end"]`; notification listener saw `"ready"`, `"turn_start"`, `"agent_end"` (membership). |
| 12 | `test_set_todos_supports_flat_items` | FAKE_SERVER. | `set_todos(["Map tools","Exercise edits"])` → 1 phase named `"Todos"`; `tasks[0].content=="Map tools"`; `tasks[1].status=="pending"`. `get_state().todo_phases[0].tasks[1].content=="Exercise edits"` (round-trips through server state). |
| 13 | `test_model_mode_and_session_commands` | FAKE_SERVER. | `set_model("anthropic","claude-sonnet-4-6").id=="claude-sonnet-4-6"`; `cycle_model().model.id=="claude-sonnet-4-5"`; `get_available_models()` ids `== ["claude-sonnet-4-5","claude-sonnet-4-6"]`; `set_thinking_level("high")` then state `.thinking_level=="high"`; `cycle_thinking_level().level=="low"`; after `set_steering_mode("all")`/`set_follow_up_mode("all")`/`set_interrupt_mode("wait")`/`set_auto_compaction(False)`/`set_auto_retry(False)`/`set_session_name("Renamed")` the state reflects all (steering `"all"`, follow-up `"all"`, interrupt `"wait"`, auto-compaction False, name `"Renamed"`); `compact().summary=="trimmed"`; `get_session_stats()`: `session_id=="fake-session"`, `tokens.total==15`; `export_html("/tmp/custom.html")` returns that exact path; `new_session()`/`switch_session("/tmp/session.jsonl")` both `cancelled` False; `branch("entry-9").text=="branch created"`; `get_branch_messages()[0].entry_id=="entry-9"`. |
| 14 | `test_message_and_control_commands` | FAKE_SERVER. | `prompt_and_wait("say hello")` → `"pong"`; `get_last_assistant_text()=="pong"`; `get_messages()` → 1 message, role `"assistant"`; `clear_todos()` then `get_todos()==()`; `steer`/`follow_up`/`abort`/`abort_retry`/`abort_bash` all succeed; `abort_and_prompt("say hello")` + `wait_for_idle(2.0)` then `get_last_assistant_text()=="pong"`. |
| 15 | `test_protocol_v2_reassembles_chunked_message_pages` | V2_MESSAGES_SERVER (advertises `supportedProtocolVersions [1,2]`, `maxFrameBytes` 1 MiB, `maxReassembledFrameBytes` 64 MiB; chunks any response > 1 MiB into 256 KiB `rpc_chunk` frames, `chunkId "test-page"`). | `get_messages()` returns 1 message whose text is exactly `1024*1024` chars — negotiation + chunked page reassembly end-to-end. |
| 16 | `test_protocol_v2_get_messages_falls_back_to_streaming_snapshot` | V2 server, `env={"V2_MESSAGES_BUSY": "1"}` (every `get_messages_page` fails with code `"session_busy"`, error = the busy string). | Direct `get_messages_page()` raises `RpcCommandError` matching `"Cannot page messages while the session is changing"`; then `get_messages()` succeeds via v1 fallback → 1 message with text `"streaming snapshot"`. |
| 17 | `test_protocol_v2_get_messages_discards_stale_page_walk` | V2 server, `env={"V2_MESSAGES_STALE": "1"}` (cursor-less page returns `nextCursor "page-two"`, `totalMessages 2`; any cursor-bearing page fails `"stale_cursor"`). | Direct `get_messages_page(cursor="page-two")` raises `RpcCommandError` matching `"RPC message cursor is stale"`; `get_messages()` walks page 1, hits stale on page 2, discards the partial walk, falls back → `"streaming snapshot"`. |
| 18 | `test_collect_events_returns_turn_events` | FAKE_SERVER; `prompt("slow")` then `collect_events(2.0)`. | `len(events) >= 1`; `events[-1].type == "agent_end"`. |
| 19 | `test_all_typed_event_listeners_receive_eventful_prompt` | FAKE_SERVER; register `on_event` + 16 typed listeners; `prompt_and_wait("all events")`. | Text `"pong"`; `seen` contains each of: `agent_start`, `message_start`, `message_end`, `turn_end`, `tool_execution_start`, `tool_execution_update`, `tool_execution_end`, `auto_compaction_start`, `auto_compaction_end`, `auto_retry_start`, `auto_retry_end`, `retry_fallback_applied`, `retry_fallback_succeeded`, `ttsr_triggered`, `todo_reminder`, `todo_auto_clear`. |
| 20 | `test_extension_and_unknown_notification_listeners` | FAKE_SERVER; prompt `"notifications"` (server emits `extension_error` error `"boom"` and `{"type":"unknown_future_event","value":1}` before the turn). | `seen_extension_errors == ["boom"]`; unknown types `== ["unknown_future_event"]`. |
| 21 | `test_additive_notification_values_do_not_stop_the_reader` | FORWARD_COMPAT_SERVER; prompt `"forward compatible"` — server emits `auto_compaction_start` with unknown enum values (fails parse), then `agent_end isTerminal:false`, then 0.15 s later `agent_end isTerminal:true`. | Wait survives the non-terminal agent_end: terminal-flag sequence of `AgentEndEvent`s in the turn `== [False, True]`; exactly 1 unknown notification whose `parse_error` contains `"auto_compaction_start.reason"`. |
| 22 | `test_malformed_terminal_agent_end_wakes_waiter` | FORWARD_COMPAT_SERVER; prompt `"malformed terminal"` — terminal `agent_end` with `messages [{"role":"future_role"}]` (unparseable), then the server sleeps 2 s. | `prompt_and_wait(..., timeout=1.0)` raises `RpcError` matching `"Failed to parse terminal agent_end"` (async-error wake, NOT a timeout); 1 unknown notification with `parse_error` containing `"messages[0].role"`. |
| 23 | `test_ui_confirmation_and_cancel_round_trip` | FAKE_SERVER. | `"needs confirm"` → request method `"confirm"`, `send_ui_confirmation(id, True)`, `wait_for_idle` OK; `"needs cancel"` → method `"editor"`, `cancel_ui_request(id)`, `wait_for_idle` OK. |
| 24 | `test_prompt_lifecycle_collectors_are_single_flight` | FAKE_SERVER; background thread runs `prompt_and_wait("slow", 2.0)`; main thread polls (≤ 1.0 s) until the coordinator's active operation is `"prompt_and_wait"`. | While active, `collect_events(1.0)` raises `RpcConcurrencyError`; background thread finishes within 2 s with result `"pong"` and no errors. |
| 25 | `test_listener_mutation_does_not_change_retained_turn` | FAKE_SERVER; `on_message_end` listener mutates `event.message["content"][0]` to text `"mutated"`. | `prompt_and_wait("say hello")` text still `"pong"` and `get_messages()[0]` text still `"pong"` — retained turn events are re-parsed from stored raw clones, so listener-visible copies are isolated. |
| 26 | `test_id_less_error_responses_are_correlated` | IDLESS_ERROR_SERVER (responds to unknown commands with `success:false` and **no id**). | `request_raw("unknown")` raises `RpcCommandError` with `command=="unknown"`, `error=="unsupported: unknown"` — correlation by unique pending command. |
| 27 | `test_prompt_and_wait_raises_for_late_prompt_failure` | LATE_PROMPT_FAILURE_SERVER (answers `prompt` with `success:true` then immediately a second response for the same id with `success:false`, error `"late failure"`); `on_protocol_error` registered. | `prompt_and_wait("say hello", 2.0)` raises `RpcCommandError` with `command=="prompt"`, `error=="late failure"` (async-command late failure completes the run and surfaces to the waiter); exactly 1 protocol error dispatched, message containing `"late failure"`; `client.protocol_errors` length 1. |
| 28 | `test_listener_exceptions_are_reported_without_stopping_client` | FAKE_SERVER; a notification listener throws `RuntimeError("boom")` on `turn_start`; `on_listener_error` registered. | Prompt still completes with `"pong"`; captured listener errors `== [("notification", "turn_start", "boom")]`; `client.listener_errors` length 1 with kind `"notification"`. |
| 29 | `test_stderr_history_is_bounded` | STDERR_SERVER (writes `"first\n"` then `"second\n"` to stderr before ready); `max_stderr_chunks=1`. | After start/stop, `client.stderr == "second\n"` (oldest chunk trimmed). |
| 30 | `test_broken_startup_frame_is_reported` | BROKEN_STARTUP_SERVER (writes `not-json\n`, never a ready frame). | `start()` raises `RpcError` whose message contains `"Frame: 'not-json'"` (reader decode failure re-raised by start's pre-ready failure branch). |
| 31 | `test_event_history_limit_reports_overflow` | FAKE_SERVER; `max_event_history=2`. | `prompt_and_wait("say hello", 2.0)` raises `RpcError` whose message contains `"max_event_history"` (the waiter's snapshot start fell behind the trimmed history). |
| 32 | `StopUnblocksPromptAndWaitTests.test_stop_during_prompt_unblocks_waiter` | HANGING_SERVER (acks the prompt, never emits agent_end, blocks on stdin). Background thread: `prompt_and_wait("hang", timeout=30.0)`; main waits until the collector is active (≤ 2 s), then calls `stop()`. | Thread joins within 2 s; measured elapsed from `stop()` `< 2.0` s; exactly one captured error, an `RpcProcessExitError`. Regression for: `stop()` must invoke `_mark_closed` itself (the reader skips it when `stopping`). Trailing `stop()` in cleanup asserts idempotence. |
| 33 | `TerminatesProcessGroupTests.test_stop_kills_grandchild_spawned_by_server` | POSIX-only (`skipUnless hasattr(os, "killpg")`). Fake server spawns a grandchild that writes a heartbeat file every 20 ms; server idles past stdin EOF (sleep 30). | Grandchild alive before teardown (`kill(pid, 0)`); after `stop()`, heartbeat file contents identical across a 0.2 s + 0.3 s window — the whole process group was killed, not just the leader. Cleanup reaps a leaked grandchild defensively. |

---

## 6. Explicit port notes

1. **Concurrency model translation.** Python uses: two daemon reader threads, a write lock, a state lock, a condition variable over the event/async-error histories, one single-slot queue per request, one worker thread per host-tool/host-URI invocation, and a lock-guarded lifecycle coordinator. The Swift actor should preserve the observable contracts: (a) requests are concurrent-safe and individually timed out; (b) event waiters observe events by logical index with trim detection; (c) host-tool execution must not block the reader; (d) writes are serialized frame-at-a-time; (e) `stop()` from any context wakes all waiters immediately.
2. **Python-specific type guards** to reproduce deliberately: `isinstance(x, bool)` rejection wherever an int is required (chunk `index`/`count`/`byteLength`, `totalMessages`) — in Swift this falls out naturally from typed decoding but must not silently coerce; `payload.get("isTerminal") is not False` means *absent or true or non-false ⇒ terminal* (only an explicit JSON `false` is non-terminal).
3. **POSIX-only surface**: `start_new_session`, `killpg` group teardown, `user`/`group`/`extra_groups`. The leader-only terminate/kill fallback is the documented non-POSIX behavior.
4. **Out of scope of this spec** (not read): `protocol.py` (`parse_notification` and all event/message dataclasses, `assistant_text`, `is_passive`), `host_tools.py` (`HostTool.parse_params`, `host_tool` factory), `host_uris.py` (`normalize_read_result`). Each needs its own spec pass; this document treats them as black boxes with the call contracts shown above.

---

## Extraction caveats

1. Sibling modules NOT read (out of task scope, but the Swift port cannot be completed without them): protocol.py (parse_notification's validation rules and error-message formats like "auto_compaction_start.reason" / "messages[0].role", every event/message dataclass's field set, assistant_text(), ExtensionUiRequest.is_passive()), host_tools.py (HostTool.parse_params, the host_tool factory used in tests), host_uris.py (normalize_read_result's output fields). Each needs its own spec pass. 2. POSIX-only behavior must be translated deliberately: start_new_session/setsid, killpg group teardown (SIGTERM→SIGKILL with 1.0 s waits), and the user/group/extra_groups spawn parameters; the leader-only terminate/kill path is the documented non-POSIX fallback. 3. Python type quirks encoded as validation rules: bool-masquerading-as-int rejection (chunk index/count/byteLength, totalMessages) and `isTerminal is not False` (absent ⇒ terminal) — Swift typed decoding must not silently coerce these. 4. The spec describes Python's threading as observable semantics; the actor port must preserve contracts (non-blocking reader, per-request timeout, immediate stop() wakeup), not mechanics. 5. Test-suite fakes are inline Python scripts spawned via `python3 -u -c`; the Swift tests must either reuse them verbatim or reimplement byte-compatible fakes. INVALID_JSON_SERVER is defined but unused by any test (verified by grep); FAKE_SERVER contains a dead duplicate set_host_tools branch — both noted so the porter doesn't invent behavior. 6. Version-specific: spec matches the file at the scratchpad path as of 2026-08-24; re-verify against the repo before implementation if the checkout moves.
