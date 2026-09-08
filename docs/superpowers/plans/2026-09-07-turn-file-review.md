# Per-turn tool-reported files

> Use superpowers:subagent-driven-development. The implementation worker owns Tasks 1–2; the parent owns final review and Release interaction evidence.

**Goal:** Let a reader reach the existing edit details from a compact list of files reported by tools in that response turn.

**Scope:** A tool-derived index, explicitly limited to successful registered edit, AST edit, and write tools. It does not infer authorship, inspect git changes, include shell-created files, or sum per-edit line counts. The audit authorizes this scoped alternative. Existing transcript rows and navigation remain the detail surface.

**Base:** `e8f1294`, stacked on pending-attention PR #37. Reuse `TranscriptNavigationRequest` and `SessionController.focusTranscriptRow`. Later integration must preserve the separately implemented controller-owned disclosure state and valid scroll-anchor correction from PR #35. Do not merge branches or modify another worktree.

## Task 1: Extract exact reported paths

Owned files: new `App/Sessions/TranscriptTurnFiles.swift`, focused `Tests/TenXAppTests/TranscriptTurnFilesTests.swift`, and generated project output via pinned `bundle exec ruby scripts/generate_xcodeproj.rb` only.

- [ ] Add focused regressions for successful edit/apply_patch multi-file diffs, write file references, AST changed-file collections, duplicate paths across tools, latest matching tool identity, and two separate turns. Use existing structured presentation fixtures.
- [ ] Project from each `TranscriptTurnSection.items`. Include only `.complete` tools whose registered kind is edit, AST edit, or write. Prefer structured diff file paths, then structured collection file references, then the card's file reference. Do not parse prose or shell commands.
- [ ] Trim whitespace and normalize lexical `.`/`..` path components without filesystem IO. Preserve first-seen order; one normalized path appears once and links to its latest completed matching tool. Do not infer that relative and unrelated absolute paths name the same file.
- [ ] Exclude running/failed tools, shell writes, unrelated path mentions, and empty paths. No invented totals, workspace completeness claims, or new persistence.

## Task 2: Link the list to existing tool details

Owned files: new `App/Sessions/TranscriptTurnFilesView.swift`, `App/Sessions/TranscriptView.swift`, `TranscriptTurnSummaryView.swift` only if needed, related render/disclosure/navigation tests, and targeted `ViewSnapshotTests.swift`/reference images. Do not edit tool extraction, git commands, editor opening, controller runtime, or provider settings.

- [ ] Display a restrained list beneath the terminal turn summary only when paths exist. Label `Tool-reported files (N)` and explain: `Completed edit and write tools in this turn. Shell commands and other workspace changes are not included.` Keep long paths readable and individually accessible.
- [ ] Clicking a path expands its existing group and tool card through `ToolDisclosureState`, clears search via the existing navigation API, releases follow-to-latest, and centers the existing stable `tool:<id>` row after rendering. It must work from Slim mode without duplicating a diff or relying on a nonempty search query.
- [ ] Preserve existing row IDs, turn grouping, search, disclosure, and viewport behavior. Prefer adding the file data to existing summary projection over a parallel transcript traversal in each row.
- [ ] Run focused projection, render/navigation/disclosure checks and one targeted snapshot with long paths. Parent must view the candidate before promoting it. Do not run the full suite or promote the six unrelated baseline snapshot failures.
- [ ] Commit atomic changes and record exact SHAs, test counts, and limits in `.superpowers/sdd/turn-file-review/report.md` (private, not tracked). You are not alone; do not revert others. Out-of-fence needs are skip-and-flag.

## Task 3: Parent Release verification

- [ ] Review final extraction and navigation behavior; approve the actual snapshot before promotion.
- [ ] Build and visibly launch an isolated Release app. In an owned disposable project containing a pre-existing dirty file, drive real edit/write tools, repeated edits to one path, a multi-file patch, and a shell-created file. Confirm the scoped list shows each reported path once and excludes the shell/pre-existing changes.
- [ ] Click each relevant path from Slim mode and verify the existing matching card expands and is reached. Record source/executable hashes, screenshots, and provider/runtime limits.
- [ ] Update roadmap and draft PR evidence. No merge or deployment.
