# 10x OMP event boundary: Cursor execution handoff

## Status and authoritative git anchor

**Design: DONE. Implementation: NOT STARTED.** Tanner approved the spec and selected the Cursor/Composer handoff for the implementation plan. No product code, build, or test run belongs to this work yet.

- Repository: `git@github.com:NextStep-AI-inc/10x.git`
- Design branch: `codex/omp-event-boundary-design`
- Reviewed plan commit: `8d0550f75e2290c8bbcaaeb9c65e7e796aace959`
- Earlier design commits: `0f23df8` (approved wrappers), `3784d0a` (boundary and switch), `95c827e` (design start).
- Existing draft PR: https://github.com/NextStep-AI-inc/10x/pull/48
- Clean design checkout at export: `/Users/tannerpham/CS Projects/.worktrees/10x-omp-event-boundary-design`.
- The rollout's original main-branch startup metadata is stale and is retained separately as `original_git` in the export. Use the anchor above and verify the current design branch tip for the subsequent documentation-only handoff commit.
- Never import WIP from `/Users/tannerpham/CS Projects/10x`: it is Tanner's shared IDE/manual-testing checkout and contains unrelated work. There is no task WIP to apply.

Read these committed files from the implementation checkout:

1. [Approved spec](../specs/2026-09-28-omp-event-boundary-design.md)
2. [Implementation plan](../plans/2026-09-28-omp-event-boundary.md)
3. [Approved tool gallery](../designs/2026-09-28-omp-tool-gallery.html), committed with this handoff.
4. Repository `AGENTS.md` and `docs/testing.md`; read `ARCHITECTURE.md` if present. No architecture file was found during planning.

The spec and plan are the executable source of scope; this file supplies decisions and continuity. They allow resumption from git without the conversation export.

## Required model routing

- **Composer 2.5 high fast:** implementation and light checks.
- **Grok 4.7 xhigh fast:** verification and audits. This explicitly supersedes the earlier Grok 4.6 preference.
- **Strongest/main Codex session:** orchestration, steering, and visual verification.

These exact Cursor models were unavailable to the exporting Codex session, so none was launched. Configure the destination with these exact choices. If a model is unavailable, report that limitation; do not silently substitute another model. Delegated work must have explicit owned paths, respect concurrent work, and skip-and-flag an out-of-fence need rather than abort the entire task.

## Decision timeline

1. Tanner initially considered replacing OMP with an owned harness. His concrete pain was UI adaptation, unused feature complexity, and crashes/visual failures from unhandled output, especially advisor behavior. He accepted an App event boundary as the protective seam. **Inferred rationale:** contain presentation complexity first while retaining OMP's working execution machinery.
2. A full/partial/default visibility selector was considered, then Tanner requested one toggle. The approved **Show agent guidance** switch is off by default, reusing the existing notice preference. It changes transcript visibility only.
3. Tanner chose intentional tool-specific presentation contracts, with shared components where content fits (Read and Write share a source surface). A single generic layout for every tool was not the chosen design.
4. The first mockups lacked clear file identity and worker ownership. Tanner required existing file-type icons, the actual edited filename, and a connected file surface. Approved revision: filename/icon in the header; folder icon, directory, and actions in a neutral strip attached to source/diff; counts/reveal in a divided footer.
5. Delegate was still too noisy. Approved revision: assignment/count/status in parent header, then compact worker identity/current activity/Open session. Remove repeated assignment, tool history/count, and model metadata from the glanceable row. Exact `parentToolCallID` determines ownership; unmatched workers stay visible separately.
6. Tanner approved the written spec, then selected option A, the Cursor/Composer handoff. His latest instruction corrected verification routing to **Grok 4.7 xhigh fast**.

## Contracts that must survive implementation

- Keep OMP in charge of execution, tools, and persisted sessions. `OmpKit` owns framing, byte limits, correlation, and child process failure. The App boundary owns semantic validation, stable identity, bounded presentation, and recovery.
- Share classification between live events and restored history. Streaming/end/reopen reconciliation must update existing IDs, never duplicate guidance or lose ordinary conversation.
- Always show user/assistant/tool activity, required input/approval, and errors. Advisor and agent-attributed developer/hidden custom content become compact optional guidance. A user file mention always remains a Referenced file indicator; never expose its injected body.
- Reuse `HarnessNoticePreferenceStore.isEnabled` and its key. Retire threshold/model UI and per-event summarization after parity is proved; leave persisted old values and summary cache untouched.
- Unknown passive events continue the session and create bounded diagnostics without raw secrets, tool arguments, file bodies, or instruction bodies. Malformed terminal tool/worker updates close existing cards with a display error instead of leaving a spinner.
- Bound tool values before storing/extracting/rendering. Preserve explicit `ToolCardRegistry` names and aliases. Missing fields and unknown tools fall back to visible labeled bounded cards.
- Apply the planned budgets: guidance 512 UTF-8 bytes/6 lines; title 80 bytes; latest 128 guidance/diagnostic entries plus omission count; diagnostic traversal 256 nodes. Tool scalar 8 KiB, array 32 children, depth 4, total 256 nodes, inline media 256 KiB. Expansion/copy/accessibility must obey bounds too.
- Full tool results remain in existing persisted session files, reachable through a deliberate file action plus copyable call ID; do not introduce a second raw-result cache.
- Unsupported or malformed extension UI with a usable ID gets one `{cancelled:true}` response through the original pipeline plus visible recovery. Preserve the provider-account machine channel before fallback. Reject missing/empty/blank IDs structurally in OmpKit. Fence responses/timers across restarts; the plan specifies recovery after 10 seconds without turn completion.
- Reuse native SwiftUI components, CornerCard, existing file icons/reference actions, and semantic source/diff/console/search/media surfaces. No generic event bus, new harness, database change, dependency, upstream OMP requirement, or three-mode selector.

## Execution trajectory and open work

The plan has ten tasks and three checkpoints:

1. **Tasks 1–3: guidance.** Classifier and preview bounds, shared live/history normalization, one switch and compact row. Prove a real advisor/developer session live and after reopening in a Release build before checkpoint 2.
2. **Tasks 4–7: passive events and tools.** Diagnostics, ingestion budgets, connected file/tool surfaces, compact Delegate grouping. Prove real tool flows and malformed/large payload fallbacks.
3. **Tasks 8–10: interactions and final evidence.** Usable request IDs, one correlated cancellation and recovery, built-app full flow, evidence, PR ready, scoped review. Merge requires Tanner's explicit approval.

No implementation task or product tool call was left running. `likely_live: true` and `stop_reason: mid_tool: exec` describe this intentional export of the active planning session, not an interrupted code change. Do not replay the export's last shell tool.

Checkpoints are verification gates, not fresh design questions. Continue within the approved plan; if a concrete code constraint changes scope, update the plan before broadening it. Flag unrelated issues separately.

## Authorization and operating constraints

Tanner authorized this handoff and execution of the approved plan in Cursor. Routine reversible implementation, targeted tests, Release builds, evidence, and the normal draft-PR lifecycle in his own repository fit that scope. **No merge, deploy, migration, dependency addition, third-party/public PR, or broad refactor is authorized.** Do not re-ask for approval of the already selected design or execution route.

- Create a fresh isolated implementation worktree under `/Users/tannerpham/CS Projects/.worktrees/`, based on the design ref containing the plan and handoff. Use the platform's managed worktree tool if available. Do not edit the main checkout or another session's worktree. Port 3000 belongs to Tanner.
- Read `writing-prs` at branch start and preserve draft-first PR history. PR #48 is the existing design draft; keep its role explicit when opening the implementation PR.
- Read required execution/TDD skills and `writing-ui` + `visual-ui` before UI work, `launching-local-builds` before launching, `verifying-work` before claims, and `reviewing-code` after making the implementation PR ready.
- Never hand-edit `10x.xcodeproj`. Add Swift files under App/Tests, then run `ruby scripts/generate_xcodeproj.rb` with pinned xcodeproj 1.27.0.
- Swift Testing selectors must name exact functions including `()`. File/suite selectors can run zero tests and appear green. Check nonzero executed counts. The plan's test names are proposed tests, not existing proof.
- Verify actual user actions in a built app, not a dev server or endpoint-only checks. Confirm the local build is visible. Do not use AppleScript, AX presses, or `open -a` to steal focus.
- Report each checkpoint as Verified / Not verified / For Tanner to test, backed by commands, counts, screenshots, and interaction evidence.

## Evidence at handoff

**Verified:** spec approval and UI decisions are in the conversation; committed plan has ten ordered tasks, valid spec reference, no placeholders, and clean diff checks. At export, the design branch was clean and pushed at the stated plan SHA; no product modifications were present.

**Not verified:** any proposed feature behavior, build, tests, or real-app UI. The HTML mockup passed structural generation checks and Tanner approved its inline presentation. Automated on-screen preview access was blocked; do not present the mockup as a screenshot from an implemented build or bypass that denial.

**For Tanner to test later:** guidance visibility live/after reopen, connected file surfaces and multi-file diff selection, compact worker ownership, and unsupported interaction recovery in the verified build.

## NEXT ACTION

Read the committed plan and repository instructions, confirm the exact Composer/Grok routing, then create the fresh implementation worktree from the design ref including this handoff. Start **Task 1: `guidanceClassifierBoundsAndLabels()`**, demonstrate a nonzero failing test, and implement the bounded classifier. Reach the first built-app guidance checkpoint before starting broader tool work.
