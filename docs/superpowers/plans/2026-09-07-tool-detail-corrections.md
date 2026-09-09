# Useful tool details during and after a run

> Use superpowers:subagent-driven-development. One implementation worker owns Tasks 1–4 in sequence; the parent reviews and performs native Release verification in Task 5. No nested agents.

**Goal:** Make existing tool cards tell the truth about elapsed time, display current running output, open files through the selected editor, and expose supported child-session navigation.

**Scope:** The approved DETAILS audit item. Preserve current card layout, disclosure, source ordering, Stop behavior, and scroll policy. Do not add a file browser, terminal, agent workspace, new dependencies, or runtime patches. Base `ae2b135`, draft PR #41, stacked on Stop PR #36. Never modify another worktree.

**Evidence and decisions:** Live execution boundaries are already timestamped. OMP 18.1.10 also persists `customType: tool_execution_start` entries with `toolCallId` and `startedAt`; current history mapping ignores them and substitutes assistant-message timestamps. Unknown legacy timing should be omitted. Command payloads retain current output, but their presentation takes the first ten lines. Diff headers bypass the existing preferred-editor file reference. Nested child session files are reported by the runtime but omitted from the ordinary library list. Reuse these existing data and navigation paths.

## Task 1: Accurate, advancing tool durations

Owned paths: `App/Tools/ToolPresentation.swift`, `ToolCardScaffold.swift`, `ToolCardView.swift` if needed, `App/Sessions/TranscriptMessageNormalizer.swift`, `TranscriptHistoryMapper.swift`, `TranscriptTurnProjection.swift`, and their focused tests. Add a small duration view file only if required by existing one-component conventions.

- [ ] Write regressions before production edits: assistant timestamp 0, exact start marker 8, result timestamp 38 must display 30 seconds; absent or malformed exact marker must omit elapsed duration. Live elapsed time advances with an injected reference date, clamps negative intervals, and completed/interrupted durations stay fixed.
- [ ] Pre-index valid custom execution-start markers by tool call ID before history normalization. Use those starts when present. Keep the existing live start source reliable; add a defaulted reliability field or equivalent without rewriting all callers. Do not parse wall-time prose or fabricate persisted entries. Only accept the exact supported marker shape and finite valid dates.
- [ ] Expose a pure duration label at a supplied date. Use a one-second `TimelineView` only around running duration/status text; completed cards stay static. Preserve deterministic snapshots using existing stable fixture end times or a narrowly injected reference date, without a global testing flag.
- [ ] When deriving turn duration, do not treat a fabricated legacy tool start as exact. Preserve actual assistant/turn timestamps where independently known. Do not change source IDs or stopped phases.
- [ ] Run the relevant timing/history/turn tests with nonzero executed counts, then commit Task 1.

## Task 2: Current running command output

Owned paths: `App/Tools/ConsoleRenderPresentation.swift`, `ToolSurfaceView.swift`, `ToolCardView.swift`, and their focused tests; add a direct nested-surface phase call site if compilation requires it.

- [ ] Add a forty-line regression: a running console initially shows lines 31–40; update to 41 lines shows 32–41. Show more extends backward without losing the newest line. Copy retains the full available payload. Completed cards keep their current initial head view. Preserve the existing finite large-output ceiling.
- [ ] Pass the tool phase through the existing surface renderer. Add a bounded head/tail presentation choice; use a reverse scan for the newest requested lines instead of splitting unbounded output on every render. No tool payload/reducer rewrites.
- [ ] Keep truncation and artifact references truthful: copy means the full payload received by the app, not output already truncated upstream. Preserve horizontal scrolling and reveal controls.
- [ ] Run console extraction/presentation and nested-surface regressions, then commit Task 2.

## Task 3: One file-opening behavior for diff headers

Owned paths: `App/Tools/DiffView.swift`, `App/Tools/TranscriptReferenceView.swift` only if a small shared helper is required, and focused file-reference/diff tests. Do not change global user editor preferences during tests.

- [ ] Cover two relative paths in a multi-file diff resolving from the active project, a configured preferred editor, no configured editor, and a missing target. Reuse existing injectable file-opening tests where available.
- [ ] Render each diff header with the existing `TranscriptReferenceView(.file(path:..., line:nil))` path. Remove the separate `NSWorkspace.open` and single-file-only fallback if no caller remains. Preserve option-reveal and existing Settings behavior through the shared component.
- [ ] Run reference/diff tests. If the header snapshot changes, create only the candidate for parent visual approval; never promote an unseen candidate. Commit the implementation and tests.

## Task 4: Open reported child sessions and show recent tools

Owned paths: `OmpKit/Sources/OmpKit/SessionLibrary.swift`, focused OmpKit session-library tests, `App/Application/AppModel.swift` for a bounded child-open action only, `App/Shell/AppShellView.swift` for its environment wiring, `App/Tools/SubagentCardView.swift`, `SubagentPresentation.swift` if necessary, a small environment-action file if needed, and focused model/subagent/snapshot tests.

- [ ] Add a bounded actor API to read metadata for a reported child JSONL using the existing private scan path. It must be a regular nonsymlink JSONL exactly one level below the normal bucket's parent-session stem, physically inside the configured resolved library root. Reject missing files, arbitrary outside paths, directories, invalid extensions, too-deep nesting, and symlink escape. Do not broaden ordinary `listAll` results or accept arbitrary files.
- [ ] Test a legitimate child, each boundary above, and metadata retaining its actual path/cwd. Use a temporary library root and always clean fixtures.
- [ ] The model asks this library API for metadata and calls existing `openSession`. On failure, present the existing concise traceable error surface. A typed environment action lets the card ask the model to open the reported path. Show “Open session” only when a session file was actually reported; do not guess one. Cover the actual model route and missing-file failure.
- [ ] Display at most the existing three recent tools with compact, allowlisted useful arguments (`path`, `file`, `command`, `query`). Keep current tool distinct, avoid raw JSON or arbitrary secret-bearing fields, preserve existing recent output. Tests cover the three-item limit and no-link case.
- [ ] Run focused library/navigation/subagent tests. Send any changed snapshot candidates to the parent for approval before promotion. Commit Task 4.

## Task 5: Parent verification and evidence

- [ ] Review each task's diff for correctness, boundary behavior, preserved Stop/disclosure behavior, and minimum scope. Keep implementation workers out of broad audits and native app control.
- [ ] Build and launch the actual isolated Release artifact. Confirm a running duration advances over two observations and stays stable after completion/reopen. Exercise a growing long command, Show more, and copy through the UI.
- [ ] Open both relative multi-file diff paths through a QA-specific preferred editor configuration; verify the no-preference Settings path. Open a runtime-reported child session and return to its parent, retaining ordinary navigation behavior. If the installed runtime cannot supply a child fixture through a provider turn, label controlled RPC evidence explicitly.
- [ ] Save screenshots, exact source/executable hashes, test counts, and limitations. Update the roadmap and draft PR with a checklist. No merge or deployment.

## Working rules

You are not alone in the repository. Owned paths above are fences; report a necessary new caller before changing it. Do not revert others' edits. Generate `10x.xcodeproj` only with pinned `bundle exec ruby scripts/generate_xcodeproj.rb` when Swift files are added or removed. Use TDD for nontrivial logic and focused test selections, not the full application suite. Read `writing-ui` and `visual-ui` before UI changes and `verifying-work` before reporting success. Record source SHAs, commands, actual nonzero counts, snapshot candidates, decisions, and limits in `.superpowers/sdd/tool-details/report.md`. No push, merge, native launch, dependency changes, or nested agents from the worker.
