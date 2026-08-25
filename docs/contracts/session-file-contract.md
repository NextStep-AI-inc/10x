<!-- Extracted 2026-08-24 from oh-my-pi v18.0.4 checkout (github.com/can1357/oh-my-pi). Regenerate on omp version bumps. Verified against OmpKit tests 2026-08-24. -->

# SESSION FILE CONTRACT (oh-my-pi coding-agent → Swift session-library)

Source of truth: `packages/coding-agent/src/session/{session-entries,session-paths,session-listing,session-loader,session-title-slot,session-manager,session-migrations,session-storage}.ts` and `packages/coding-agent/src/cli/gc-cli.ts`, read 2026-08-24 from `/private/tmp/claude-501/-Users-tannerpham-CS-Projects/c47436ce-aa27-45cc-8fdd-87aaa0fecbfb/scratchpad/oh-my-pi`.

---

## 1. JSONL file layout

### 1.1 Locations and filenames

- Sessions root: `~/.omp/agent/sessions` (`getSessionsDir()` in `packages/utils/src/dirs.ts`; profile/XDG overrides possible via `PI_CODING_AGENT_DIR` / DirResolver).
- One bucket directory per cwd (encoding in §3): `<sessionsRoot>/<encodedCwd>/`.
- Session file name: `` `${fileSafeTimestamp(timestamp)}_${sessionId}.jsonl` `` where

```ts
function fileSafeTimestamp(iso: string): string {
	return iso.replace(/[:.]/g, "-");
}
```

so `2026-08-24T17:06:33.123Z` → `2026-08-24T17-06-33-123Z_<id>.jsonl`. Session ids are `Bun.randomUUIDv7()` (`mintSessionId()`). The id is recovered from a filename by taking everything after the **last** `_` (`sessionIdFromSessionPath`, session-listing.ts:644).
- Sibling artifacts directory: the session file path minus `.jsonl` (`artifactsDirectoryFor`). Subagent sessions nest inside it as `<parentStem>/<agentId>.jsonl` — these are deliberately **not** surfaced by directory listing (§4).
- Crash-recovery backups: `<name>.jsonl.<snowflake>.bak` in the same bucket (see §4, `recoverOrphanedBackups`).

### 1.2 Physical line 1 (optional): fixed-width title slot

The first physical line MAY be a **256-byte** (UTF-8, newline included) fixed-width title slot; legacy files start directly with the header. Constants (session-entries.ts):

```ts
export const CURRENT_SESSION_VERSION = 3;
export const SESSION_TITLE_SLOT_BYTES = 256;
export const SESSION_TITLE_SLOT_ENTRY_TYPE = "title";
```

Shape:

```ts
/** Fixed-width first-line slot carrying the mutable current session title. */
export interface SessionTitleSlotEntry {
	type: "title";
	v: 1;
	title: string;
	source?: "auto" | "user";   // SessionTitleSource; omitted when unset
	updatedAt: string;          // ISO timestamp
	pad: string;                // spaces; sized so JSON line + "\n" == exactly 256 bytes
}
```

`serializeTitleSlot` binary-searches a title truncation (by code points) so `JSON.stringify(slot) + "\n"` is exactly 256 UTF-8 bytes, padding with spaces in `pad`. Title updates rewrite ONLY these 256 bytes in place via `fs.openSync(path, "r+")` + `fs.writeSync(fd, buf, …, offset=0)` (`FileSessionStorage.updateSessionTitle`) — file **size is unchanged, mtime bumps** (this matters for cache invalidation, §4).

Parsing rules (`parseTitleSlotLine` / `parseSessionContent` / `visitEntriesFromFileStream`):
- Read up to the first `\n`; try JSON parse; accept only `{type:"title", v:1, title:string, updatedAt:string, pad:string}` with optional valid `source`. Anything else ⇒ no slot, the line is a real entry (the header).
- When a slot exists, loaders strip it and **fold it into the header**: non-empty `slot.title` overrides `header.title`; empty title **deletes** `header.title`; same for `titleSource` (`applyTitleSlot`, session-loader.ts:51). The slot is authoritative over the header's stale `title` field.

### 1.3 Header line (first logical entry)

```ts
export interface SessionHeader {
	type: "session";
	version?: number; // v1 sessions don't have this
	id: string;
	title?: string; // Auto-generated title from first message
	titleSource?: SessionTitleSource;        // "auto" | "user"
	timestamp: string;                        // ISO creation time
	cwd: string;                              // absolute, resolved
	additionalDirectories?: string[];         // multi-root workspace; absent on legacy
	parentSession?: string;                   // PATH to parent session file (fork), not an id
	previousSessionFiles?: string[];          // prior absolute JSONL locations from session moves
	providerPromptCacheKey?: string;          // prompt-cache identity inherited by exact-route full forks
}
```

A fresh empty file is exactly (session-manager.ts:2660):

```ts
storage.writeTextSync(file, `${serializeTitleSlot({ updatedAt: timestamp })}${JSON.stringify(header)}\n`);
```

i.e. `title-slot(256B)\n{"type":"session","version":3,"id":…,"timestamp":…,"cwd":…}\n`. Full rewrites use the same order: slot, header, then every entry (`#fileBody()`).

**Validity rule:** after slot-strip, if the first parsed entry is not `type:"session"` with a string `id`, the whole file is treated as invalid — `loadWithKnownSize` returns `entries: []` (session-loader.ts:257).

### 1.4 Entry lines

Every subsequent line is one JSON object, `JSON.stringify(...)` + `"\n"` (so every line starts with `{`; writes are newline-terminated — only the **last** line can be a partial fragment after a crash). Malformed interior lines are skipped leniently (`parseJsonlLenient`; the streaming path counts them via `onMalformedRecord`). Large strings are truncated at persist time to 500k chars with a `"\n\n[Session persistence truncated large content]"` suffix; images ≥1024 base64 chars are externalized to `blob:sha256:<64hex>` refs into `~/.omp/agent/blobs` (session-persistence.ts, blob-store).

Common base:

```ts
export interface SessionEntryBase {
	type: string;
	id: string;              // 8 hex chars normally (see §2), opaque string in general
	parentId: string | null; // null = root of the tree
	timestamp: string;       // ISO
}
```

The full union (session-entries.ts:272) — **15 variants**:

```ts
export type SessionEntry =
	| SessionMessageEntry | ThinkingLevelChangeEntry | ModelChangeEntry
	| ServiceTierChangeEntry | CompactionEntry | BranchSummaryEntry
	| CustomEntry | CustomMessageEntry | LabelEntry | TitleChangeEntry
	| TtsrInjectionEntry | SessionInitEntry | ModeChangeEntry
	| CredentialPinEntry | ResetBoundaryEntry;
```

Exact fields per variant (all extend `SessionEntryBase`):

| type | extra fields |
|---|---|
| `"message"` | `message: AgentMessage` (external type from `@oh-my-pi/pi-agent-core`; fields the session layer itself relies on: `role` ∈ `"user" \| "assistant" \| "toolResult" \| "custom"`, `stopReason?` ∈ `"error" \| "aborted" \| "length" \| …`, `content: string \| Block[]` where blocks carry `type` incl. `"text"` (`.text`), `"toolCall"`, `"thinking"`, `"image"` (`.data`, `.mimeType`), plus optional `providerPayload`) |
| `"thinking_level_change"` | `thinkingLevel?: string \| null`, `configured?: string \| null` (`"auto"` when auto mode; absent on old entries → fall back to `thinkingLevel`) |
| `"model_change"` | `model: string` ("provider/modelId"), `role?: string` (undefined ⇒ "default"), `resolvedModelIsFallback?: boolean` |
| `"service_tier_change"` | `serviceTier: ServiceTierByFamily \| null` |
| `"compaction"` | `summary: string`, `shortSummary?: string`, `firstKeptEntryId: string`, `tokensBefore: number`, `tokensAfter?: number`, `method?: CompactionMethod`, `providerReplayThroughEntryId?: string`, `details?: T`, `preserveData?: Record<string, unknown>`, `fromExtension?: boolean`, `warning?: string` |
| `"branch_summary"` | `fromId: string`, `summary: string`, `details?: T`, `fromExtension?: boolean` |
| `"custom"` | `customType: string`, `data?: T` (never in LLM context) |
| `"custom_message"` | `customType: string`, `content: string \| (TextContent \| ImageContent)[]`, `details?: T`, `display: boolean`, `attribution?: MessageAttribution` (IS in LLM context) |
| `"label"` | `targetId: string`, `label: string \| undefined` (undefined ⇒ delete the label; last write wins) |
| `"title_change"` | `title: string`, `previousTitle?: string`, `source: "auto"\|"user"`, `trigger?: string` (append-only audit; current title lives in the slot) |
| `"ttsr_injection"` | `injectedRules: string[]` |
| `"session_init"` | `systemPrompt: string`, `task: string`, `tools: string[]`, `agent?`, `modelRole?`, `resolvedModel?`, `readOnly?`, `outputSchema?`, `outputSchemaMode?`, `restrictToolNames?`, `spawns?: string`, `readSummarize?: boolean`, `advisor?: string` (subagent sessions only) |
| `"mode_change"` | `mode: string` ("none" = exiting), `data?: Record<string, unknown>` |
| `"credential_pin"` | `provider: string`, `hash: string` (sha-256 of account+scope tuple; pseudonymous) |
| `"reset_boundary"` | *(no payload — durable `/clear` marker; context rebuild starts after it, disk keeps full history)* |

The Swift `SessionFileParser` exposes transcript-relevant metadata as typed
values: model selection (including role/fallback), configured and effective
thinking, mode changes, compaction counts/warnings, branch summaries, and a
display-safe subset of `session_init`. The `session_init.systemPrompt` and
execution schemas deliberately remain outside that typed display model; unknown
entry kinds are still retained as raw values.

### 1.5 Versioning

`version` on the header: absent ⇒ v1, else 2 or 3. `CURRENT_SESSION_VERSION = 3`. Migrations (`session-migrations.ts`, run in-memory on load — files on disk may remain old-version until rewritten):
- **v1→v2**: entries had no ids; assign `entry.id = generateId(ids)`, `entry.parentId = prevId` in file order (a pure chain), and convert compaction `firstKeptEntryIndex: number` → `firstKeptEntryId`.
- **v2→v3**: message role `"hookMessage"` → `"custom"`.

A Swift reader targeting read-only display should implement both migrations (or at minimum v1's id synthesis, since the tree walk needs ids).

---

## 2. id/parentId tree + leaf pointer

- Entry ids: `generateId` = last 8 hex chars of `crypto.randomUUID()`, collision-checked against the live id set, `Snowflake.next()` fallback. Treat ids as opaque strings.
- Every appended entry gets `parentId = current leaf id` (`#freshEntryFields()`), so linear conversation = a chain. **Branching** = appending an entry whose `parentId` points at an *earlier* entry (navigation/branch commands call `setLeaf` first); the old tail becomes a sibling branch.
- **There is no on-disk leaf field.** The persisted leaf is *the last entry line in the file*. In memory, `SessionEntryIndex.insert` sets `#leaf = entry.id` unconditionally on every insert, and the read-only transcript loader documents "the persisted leaf path (last entry)" (`loadSessionMessagesReadOnly`). A file created by `createBranchedSession` contains only one root-to-leaf path.

Reconstructing the active path for display (mirrors `buildSessionContext` / `SessionEntryIndex.pathTo`):

```
load file  → strip title slot → header + entries[]  (skip malformed lines)
byId = { e.id: e  for e in entries }          // header excluded

leaf:
  if explicit leafId == null:   path = []      // navigated before first entry
  else if explicit leafId:      leaf = byId[leafId]
  if leaf is nil:               leaf = entries.last   // the persisted leaf
  if leaf is nil:               path = []             // header-only file

// Walk leaf → root; cycle-guard mandatory (corrupt files can contain parent cycles)
path = []; seen = {}
cur = leaf
while cur != nil && !seen.contains(cur.id):
    seen.insert(cur.id); path.append(cur)
    cur = cur.parentId != nil ? byId[cur.parentId] : nil
path.reverse()
```

Display modifiers along the path: the newest `compaction` entry collapses everything before `firstKeptEntryId` behind its `summary`; `label` entries apply last-write-wins per `targetId` (`label: undefined` deletes); settings entries (`model_change`, `thinking_level_change`, `service_tier_change`, `mode_change`) are folded by scanning the path in order. Assistant messages whose `toolCall` blocks have no paired result *on the resolved path* get those blocks stripped for display with a `strippedToolCalls` count marker.

---

## 3. cwd → bucket directory encoding (session-paths.ts)

Verbatim algorithm (`getDefaultSessionDirName`, lines 62-88):

```ts
const resolvedCwd = path.resolve(cwd);
const canonicalCwd = resolveEquivalentPath(resolvedCwd);      // symlink/alias canonicalization
const canonicalHome = resolveEquivalentPath(os.homedir());
const canonicalTempRoot = resolveEquivalentPath(os.tmpdir());
const homeRelative = path.relative(canonicalHome, canonicalCwd);
const tempRelative = path.relative(canonicalTempRoot, canonicalCwd);
let encodedDirName: string;
if (homeRelative === "" || (!homeRelative.startsWith("..") && !path.isAbsolute(homeRelative))) {
	encodedDirName = encodeRelativeSessionDirName("-", homeRelative);        // HOME-RELATIVE
} else if (tempRelative === "" || (!tempRelative.startsWith("..") && !path.isAbsolute(tempRelative))) {
	encodedDirName = encodeRelativeSessionDirName("-tmp", tempRelative);     // TMP-RELATIVE
} else {
	encodedDirName = encodeLegacyAbsoluteSessionDirName(canonicalCwd);       // ABSOLUTE
}
```

with:

```ts
function encodeLegacyAbsoluteSessionDirName(cwd: string): string {
	const resolvedCwd = path.resolve(cwd);
	return `--${resolvedCwd.replace(/^[/\\]/, "").replace(/[/\\:]/g, "-")}--`;
}
function encodeRelativeSessionDirName(prefix: string, relative: string): string {
	const encoded = relative.replace(/[/\\:]/g, "-");
	return encoded ? (prefix.endsWith("-") ? `${prefix}${encoded}` : `${prefix}-${encoded}`) : prefix;
}
```

Resulting forms:
- **Home-relative**: `-<rel with / \ : → ->`; home itself ⇒ exactly `-`. E.g. `~/CS Projects/foo` → `-CS Projects-foo`.
- **Tmp-relative**: `-tmp` for tmpdir itself, else `-tmp-<rel encoded>`.
- **Absolute (outside home & tmp)**: `--<abs path minus leading slash, / \ : → ->--` (double-dash sandwich). E.g. `/Volumes/X/repo` → `--Volumes-X-repo--`.

**DECODING a bucket name back to a cwd is impossible.** `/`, `\`, and `:` all collapse to `-`, so a literal `-` in a path component is indistinguishable from a separator (`-CS Projects-foo` could be `~/CS Projects/foo` or `~/CS Projects-foo`). The codebase never decodes: `resolveManagedSessionRoot` **re-encodes a known cwd and string-compares** against the dir name. A Swift library must read the header's `cwd` field (first ~4KB, §5) to learn a session's real cwd — the listing scanner does exactly this (`SessionInfo.cwd` comes from the header, empty string when absent).

Legacy/migration dir forms a reader may still encounter (migrated best-effort on first write access, but a read-only library should tolerate them): old home form `--<home-encoded>-<rel>--`, and the reverted 17.2.5-17.2.8 hashed form `<scope>-<readable>-<sha256hex>` where scope ∈ `home|tmp|abs`, readable = basename sanitized `[^a-zA-Z0-9._-]+`→`-`, digest = SHA-256 hex of the canonical cwd with `\`→`/`.

Terminal breadcrumbs (for `--continue`): `~/.omp/agent/terminal-sessions/<terminalId>` containing 2-3 plain lines: `cwd\nsessionFile\n` plus optional third line `fresh` (lazy `/new` session whose JSONL may not exist yet).

---

## 4. Discovery and listing (session-listing.ts)

### listSessions / listAllSessions (full scan, per-file bounded reads)

- `listSessions(sessionDir)` → `recoverOrphanedBackups` first (promote newest `<primary>.jsonl.<snowflake>.bak` to `<primary>.jsonl` when the primary is missing), then glob `*.jsonl` in that one directory. `listSessionsReadOnly` skips the repair. `listAllSessions()` globs `*/*.jsonl` under the sessions root — **exactly depth 2, non-recursive**, so nested subagent sessions (`<stem>/<agentId>.jsonl` is depth 3 relative to root only when the stem dir is inside a bucket) never appear; do not "fix" this in Swift.
- Per file, `scanSessionFile` reads only two byte windows (never the whole file):

```ts
const SESSION_LIST_PREFIX_BYTES = 4096;
const SESSION_LIST_SUFFIX_BYTES = 32_768;   // tail, only when withStatus
```

- From the **4KB prefix**: lenient-JSONL-parse; fold optional title slot (slot title overrides header title, empty slot title clears it — `normalizeTitleOverride`); header fields `id`, `cwd`, `title`, `parentSession`, `timestamp` (a tolerant raw-string scanner `extractStringProperty` backstops when the prefix cuts a line mid-JSON); first user message text (`firstMessage`, falling back to developer/assistant text via `extractFirstDisplayMessageFromPrefix`); newest `compaction.shortSummary` seen in the prefix (used as title fallback); `messageCount = max(parsed message entries, count of "type":"message" markers in the prefix)` — **approximate, prefix-bounded**.
- From the **32KB suffix** (only for `withStatus` calls): walk lines backwards, skip any line not starting with `{` (rejects the leading partial fragment), find the last `type:"message"` and classify:

| last message | status |
|---|---|
| assistant, stopReason "error" | `error` |
| assistant, stopReason "aborted" | `aborted` |
| assistant, stopReason "length" | `interrupted` |
| assistant with trailing `toolCall` blocks | `interrupted` |
| assistant otherwise | `complete` |
| toolResult | `interrupted` |
| user | `pending` |
| none found / window too small | `unknown` |

- `SessionInfo` also carries `created` (header timestamp), `modified` (file mtime), `size` (bytes).
- **Sort order: `modified` (mtime) descending** — `sessions.sort((a, b) => b.modified.getTime() - a.modified.getTime())`.
- Scan results are memoized per path keyed on `(mtimeMs, size)` both matching (LRU, 4096 entries; separate cache keys for with/without status). This works because appends grow size, and in-place title-slot rewrites keep size but bump mtime. Negative (unparseable) results are cached too.
- Parallelism: single-pass ≤64 files, else strided workers `min(16, availableParallelism, ceil(n/64))`.

### getRecentSessions (welcome screen, cheap path)

Lists `*.jsonl`, stats each, sorts by `mtimeMs` desc, then for the newest `limit` (default 4): try the **history.db title index** (`lookupSessionTitle(idFromFilename)`) with zero file reads; on miss, do a prefix-only `scanSessionFile(file, storage, false)` (no tail/status) and backfill the index. Display name precedence: sanitized title → first user message → `"Untitled · <HH:MM>"`. Times formatted as `just now / Nm ago / Nh ago / Nd ago / locale date`.

### resolveResumableSession

Prefix-match (case-insensitive) the resume arg against: session `id`, filename without `.jsonl`, and the id segment after the last `_`. Local bucket first, then global `listAllSessions` fallback.

---

## 5. Minimal header-only metadata parse + gzip archive

### Minimal parse

Read the **first 4096 bytes** (the reference's `SESSION_LIST_PREFIX_BYTES`) and process the first one or two logical lines:

1. Line 1: if it parses as `{type:"title", v:1, …}` it is the 256-byte slot → capture `title`/`source`, continue to line 2; otherwise line 1 is the header.
2. Header line: require `type == "session"` and non-empty string `id`; extract `cwd`, `title`, `titleSource`, `parentSession`, `timestamp`, `version`, `additionalDirectories`, `previousSessionFiles` as needed. Slot title (when the slot exists) **overrides** the header's `title`, and an empty slot title means "no title".
3. Tolerate: CRLF, blank lines, a header line truncated by the 4KB window (fall back to raw string-property extraction if you want parity), and reject the file if the first non-slot line is not a valid header. gc-cli's `readSessionLineageHeader` is the minimal precedent: stream lines, skip one leading `type:"title"` line, parse the next as the header, give up after 2 lines.

Nothing else in the file is needed for identity/metadata. Status needs the 32KB tail (§4); message text needs a full parse.

### Gzip archive layout (present — written by `omp gc --archive`, cli/gc-cli.ts)

- Archive root: `path.join(path.dirname(getSessionsDir(agentDir)), "archive", "sessions")` → **`~/.omp/agent/archive/sessions`**.
- Cold sessions are moved to `<archiveRoot>/<relativePath>.gz` where `relativePath` is the path relative to the sessions root — i.e. the **bucket structure is preserved**: `<archiveRoot>/<encodedCwd>/<timestamp>_<id>.jsonl.gz` (`COMPRESSED_SESSION_SUFFIX = ".jsonl.gz"`).
- Content: the **entire session file gzipped whole** (`gzipSync(bytes, { level: 9 })`), title slot and all — after gunzip it is byte-identical to a live session file and parses under this same contract. Written via temp file + rename, then the source is unlinked.
- The artifacts directory moves alongside **uncompressed**: `sessionArtifactsPath` strips `.jsonl.gz` (or `.jsonl`) to get the stem, so `<archiveRoot>/<bucket>/<stem>/` holds the artifacts.
- Archived files are invisible to all live listing (`*.jsonl` globs never match `.jsonl.gz`); gc scans them with `**/*.jsonl.gz` and blob GC treats both roots as referencing blobs. Restore = gunzip back to the live path (`restoreGzipSessionFile`).
- Selection is age/retention-driven (`coldArchiveAfterDays`, `retainNewestGlobal`, `retainNewestPerCwd`); sessions with status ∈ {pending, interrupted, unknown} or live nested subagent sessions are skipped — a Swift library only needs the layout above, not the policy.


---

## Extraction caveats

1) AgentMessage is an external type (@oh-my-pi/pi-agent-core) and was NOT fully audited — the contract documents only the fields the session layer itself reads (role, stopReason, content blocks incl. toolCall/thinking/image, providerPayload); a Swift implementation that must render full message content should extract the complete AgentMessage schema separately. 2) ServiceTierByFamily, MessageAttribution, TextContent/ImageContent, and CompactionMethod shapes come from @oh-my-pi/pi-ai and ./compaction-methods and were not expanded. 3) Alternate storage backends (redis-session-storage.ts, sql-session-storage.ts, indexed-session-storage.ts) exist but are out of scope for the on-disk file contract; they synthesize the title slot semantically. 4) resolveEquivalentPath (symlink canonicalization) semantics live in pi-utils and were not read — Swift should canonicalize symlinks/aliases before classifying home/tmp/abs or bucket names will diverge from the reference for symlinked cwds. 5) The sessions root can be relocated by profiles/XDG/PI_CODING_AGENT_DIR; ~/.omp/agent/... is the default. 6) Legacy dir forms (old --home--, hashed 17.2.5-17.2.8) are migrated on write access by the reference; a read-only Swift library must tolerate them if it scans dirs the agent has not touched since. 7) Blob refs (blob:sha256:<hex>) in entries require the ~/.omp/agent/blobs store to resolve images; unresolved refs are safe to display as placeholders. 8) Version note: all quotes are from the repo snapshot in the scratchpad dated Aug 24 2026; verify CURRENT_SESSION_VERSION and slot size against the vendored commit before freezing the Swift contract.
