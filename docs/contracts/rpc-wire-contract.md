<!-- Extracted 2026-08-24 from oh-my-pi v18.0.4 checkout (github.com/can1357/oh-my-pi). Regenerate on omp version bumps. -->

(see report field)

---

## Extraction caveats

Opaque referenced types NOT expanded (import them or treat as raw JSON in Swift; source modules): Model, ImageContent, ToolExample, Effort — @oh-my-pi/pi-ai (Effort verified as string enum "minimal"|"low"|"medium"|"high"|"xhigh"|"max" from packages/catalog/src/effort.ts; it is a TS `const enum`, values are inlined strings on the wire); AgentMessage, AgentToolResult, ThinkingLevel, ToolLoadMode — @oh-my-pi/pi-agent-core (ThinkingLevel verified from packages/agent/src/thinking.ts as "inherit"|"off"|Effort values); CompactionResult — pi-agent-core/compaction; BashResult — exec/bash-executor; ContextUsage — extensibility/extensions/types; SessionStats — session/agent-session; FileEntry — session/session-entries; AgentProgress/Subagent*Payload — src/task; TodoPhase/TodoItem — tools/todo. Verify each shape before hard-typing in Swift.

`config_update`/`session_info_update` optionality is inferred from the emit sites (`session.model` / `session.sessionName` may be undefined, matching `RpcSessionState.model?`/`sessionName?`) — not from a declared frame interface; these three side-channel frames (command_output, session_info_update, config_update) have NO TypeScript interface in rpc-types.ts, only inline emits in rpc-mode.ts, so their shapes could drift silently.

The full AgentSessionEvent stream (agent_start/agent_end/message_*/tool_execution_*/auto_compaction_*/auto_retry_*/ttsr_triggered/todo_reminder/todo_auto_clear/irc_message/thinking_level_changed/model_changed/goal_updated/retry_fallback_*) shares stdout with these frames; only `notice` was documented per the task scope. Host tool frames (host_tool_call/update/result/cancel) and host URI frames (host_uri_request/result/cancel) are declared in rpc-types.ts but were outside the five requested items; they are bidirectional and needed if the Swift host registers tools or URI schemes.

Version caveat: shapes reflect the checked-out snapshot at the scratchpad path on 2026-08-24; MAX limits and the strict-equality v2 handshake mean any fork that changes constants breaks negotiation with the reference client.
