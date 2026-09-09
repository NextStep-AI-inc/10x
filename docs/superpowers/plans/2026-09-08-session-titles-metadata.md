# Persist fallback titles and refresh branch metadata

The authorized TITLES audit item requires useful persisted titles and current project metadata. PR #42 handles the last valid route. This slice fixes the remaining in-memory-only fallback and refreshes read-only git metadata.

## Design

After the existing successful initial prompt acknowledgment, choose a usable generated title or the existing bounded first-prompt fallback. A missing generator or unusable generated value must not prevent persisting the fallback when one exists. Trim and bound consistently, then send exactly one `set_session_name` for this first-title attempt. Publish the resulting local title only while the same session pipeline and title generation are current. Manual rename, stop/restart, and session replacement win over a delayed title task. Keep rejected/uncertain prompts unchanged; do not auto-send or retry them. Log a sanitized title-save failure without failing the composer or exposing the prompt.

Reuse `SessionHeaderMetadata.resolve` to refresh after a terminal agent boundary and when returning to a retained session. Coalesce overlapping metadata reads and guard their results with the existing session generation/identity so a stale project cannot overwrite the current header. No polling, filesystem watcher, git checkout, or new metadata cache. Nonterminal agent boundaries must not masquerade as completion.

## Ownership

- `/tmp/10x-audit-titles`, branch `codex/active-session-titles`, base `8e835b7` (PR #42).
- Worker owns `SessionController.swift`, the retained-session selection call in `AppModel.swift` if needed, focused `SessionControllerTests.swift` / `AppModelNavigationTests.swift` / `SessionHeaderMetadataTests.swift`, and their controlled RPC fixture. Any new Swift source goes through the generated-project script.
- You are not alone. No edits in drafts/input/context worktrees or outside these paths. No dependencies, runtime/config changes, schema, broad rename/navigation refactor, native UI, push, merge, full suite, or nested agents. Use `/tmp/10x-derived-titles` exclusively.

## Task 1: Persist a usable first title

- [ ] Add a nil/unusable generator regression: acknowledged initial prompt sends one bounded fallback title and disk/library metadata remains named after reopening. Generated titles still win; rejected input does not start naming.
- [ ] Cover a delayed generator versus manual rename and session replacement so automatic naming cannot overwrite newer intent. Reuse existing rename and lifecycle fixtures.
- [ ] Implement the small shared title-selection/save path with specific sanitized failure handling. Run the affected title/receipt checks and commit.

## Task 2: Refresh project metadata

- [ ] In a temporary git repository, open on branch A, change only that test repository to branch B, deliver a terminal boundary, and observe B in controller metadata. Verify nonterminal/stale boundaries and delayed old results cannot replace current metadata.
- [ ] Verify returning to a retained controller refreshes metadata without opening a duplicate runtime. Keep startup/open behavior intact.
- [ ] Implement coalesced reads with cancellation/generation protection; run focused metadata/navigation tests. Commit and report exact selectors, nonzero counts, logs, and limitations.

## Task 3: Parent acceptance

- [ ] Review the final diff, build Release, and launch an isolated QA bundle. Verify a controlled nil-title generator fallback persists and real generated/manual/duplicate titles remain distinguishable by project.
- [ ] In an owned QA git project only, change branch through a real tool turn and observe the header update; switch away/back after an external QA-only branch change. Never change Tanner's checkout.
- [ ] Record evidence and update TITLES roadmap/PR alongside PR #42 route recovery. Keep the PR draft for integration and recorded baseline issues; merge remains Tanner's decision.

## Preflight

Both changes reuse existing session lifecycle boundaries and generation guards. Naming remains downstream of acknowledgment; metadata reads are independent of prompt contents. No new durable state is needed beyond the runtime's existing session name.
