# Composer draft and route recovery

> Use superpowers:subagent-driven-development. One implementation worker owns Tasks 1–3 sequentially; the parent reviews and drives the actual Release app for Task 4. No nested agents.

**Goal:** Restore unsent composer text and staged images after relaunch, per saved session or new-session project, and return to the last valid conversation. Nothing recovered is sent automatically.

**Scope:** The INPUT draft-persistence and TITLES route-restoration recommendations. Base `9cdefa7`, draft PR #42 stacked on PR #38. File insertion, warnings/CJK behavior, title fallback, and git metadata refresh are separate bounded changes. No runtime, dependency, cloud-sync, schema, or global preference changes.

**Design:** Add one local binary-plist recovery store under the current app bundle's Application Support directory. It holds ordered text/image snapshots and the last meaningful route. Live dependencies inject disk persistence; the normal dependency initializer and previews/tests default to an in-memory store. Keep current in-memory controller reuse and receipt behavior. Use the original encoded image bytes and IDs; do not re-encode images or parse them back out of transcript JSON.

## Task 1: Small local recovery store

Owned files: new `App/Sessions/ComposerRecoveryStore.swift`, `App/Sessions/ComposerAttachment.swift` for Codable conformance only if used, `App/Application/AppDependencies.swift`, and new focused `Tests/TenXAppTests/ComposerRecoveryStoreTests.swift`. Generate project only with pinned `bundle exec ruby scripts/generate_xcodeproj.rb`.

- [ ] Before production edits, test text/Unicode and ordered attachment bytes/IDs round-trip, independent session/project keys, removal, malformed-file fallback, and latest-write ordering across debounce/flush. Tests use a temporary root and never standard app data.
- [ ] Canonicalize file/project keys consistently with existing standardized/resolved paths. Keep image count/size validation bounded by existing attachment limits and safely ignore invalid records. Use Codable data with a format version; no broad migration framework.
- [ ] Update in-memory snapshots immediately. Debounce disk writes on a serialized background writer, use atomic replacement and a monotonic revision so an older queued write cannot win, and expose an awaited flush. Preserve actual data on write failure and expose a traceable concise recovery error. Use private directory/file permissions (0700/0600) for these local user drafts.
- [ ] Represent recoverable in-flight input separately from the newer editable draft, with its original attachment IDs and minimum history user index. This is only the local send acknowledgment boundary; do not persist or replay an accepted runtime queue. A temporary initial-session owner may use a stable local ID with its project until the actual session path is known; keep this within the same store, not a second journal/service.
- [ ] Run the focused store checks, commit Task 1, and report the exact count and SHA.

## Task 2: Preserve drafts across controller and send lifecycles

Owned files: `App/Sessions/SessionController.swift`, `App/Application/AppModel.swift`, `App/Sessions/ActiveSessionView.swift`, `App/Sessions/NewSessionView.swift` only if needed for the recovery notice, and focused controller/navigation tests plus a minimal existing RPC fixture extension if needed. New small shared recovery notice view is allowed if it avoids duplicated UI.

- [ ] Hydrate the session's editable draft/images synchronously when creating a controller, before its asynchronous open can race a rapid A/B switch. Persist subsequent mutations without writing into another controller or project. Persist each new-project draft separately; preserve A when choosing B and restore A on return.
- [ ] Before clearing the composer for a send, retain the submitted text/images as an in-flight recovery snapshot and flush that snapshot before issuing the provider command. On successful acknowledgment remove only that snapshot, retaining text/images typed during the wait. On rejection, timeout, Stop, or uncertain disconnect preserve the snapshot and current draft without automatic retry. Keep existing receipt/reconciliation semantics and do not turn accepted queued messages back into drafts.
- [ ] Initial session creation must not erase its project draft before durable ownership exists. A temporary initial-owner record keeps the initial input and any newer controller draft; transfer it to the actual session path once known. Remove the old project snapshot only when it is still the submitted revision, so a newer project draft is never erased. Failed opens remain recoverable through the existing Review prompt flow. Unresolved initial-owner records must be recovered when that project is selected after relaunch, retaining all text/images if more than one exists; never silently discard them.
- [ ] After authoritative history loads, use the existing PendingUserSubmission match rules and minimum user index to discard a recovered in-flight snapshot only when its actual echo is present. Otherwise combine its text/images with the current editable draft once (stable-ID dedupe) and show the existing-register warning: “A previous send wasn’t confirmed. Review the conversation before sending this draft.” No automatic send, queue recreation, or duplicate receipt rendering.
- [ ] Add regressions for A/B sessions and projects, an accepted send with newer text/image, rejection with newer text/image, delayed initial open, failed initial open, ownership transfer while a newer project draft exists, and relaunch recovery with/without the corresponding history echo. Include a prior identical message before the saved minimum user index so it cannot consume the recovery record.
- [ ] Snapshot all active/latest composer state and await the store flush before shutdown discards controllers. Preserve data when a controller is evicted; clear successfully archived/deleted session records and route references only for `SessionMutationReport.succeededPaths`, preserving failed paths. Ordinary switching and explicit New session must remain responsive.
- [ ] Run only the focused new/regression checks, create any necessary UI snapshot candidates for parent approval, then commit Task 2.

## Task 3: Restore the last meaningful route

Owned files: `App/Application/AppModel.swift`, `AppRoute.swift` only if required for a small persisted representation, and focused navigation/startup tests. Prefer a private Codable route in the recovery store instead of changing every AppRoute case.

- [ ] Persist saved-session selection and explicit new-session project intent. Settings/providers/search/archived views do not replace the last meaningful conversation route. Keep direct user navigation higher priority than a delayed startup restore.
- [ ] Restore once, after sessions and recent projects have loaded and the actual onboarding/provider/runtime gates permit the workspace. A saved session must match current active metadata by canonical path and its cwd must still be an existing directory. Missing/archived/deleted sessions or missing projects fall back to a valid new-session route and clear stale route references.
- [ ] Recover an interrupted initial-owner route into its project's new-session draft without starting a provider turn. If the user last explicitly chose New session, preserve that intent.
- [ ] Test last-session restoration, new-session intent, settings not displacing the last route, missing/archived paths, missing project, and onboarding still taking precedence. Keep normal runtime-replacement gating behavior intact.
- [ ] Run focused navigation/startup checks, commit Task 3, and report the final source SHA.

## Task 4: Parent Release verification

- [ ] Review store ordering, acknowledgment ownership, restore timing, per-project isolation, image identity, and no automatic sends. Resolve only findings required by this scope.
- [ ] Build and launch an isolated Release app. Enter different text plus a PNG in two saved sessions and a new-project composer; quit and relaunch through the real app. Confirm exact text/images, the last valid session, and no added user message. Repeat a valid new-session route and an isolated missing-project fallback.
- [ ] Use the controlled delayed/rejecting RPC fixture to exercise shutdown during acknowledgment and a failed first open; keep that evidence distinct from actual OMP. Verify the recovered uncertainty warning and that only an explicit Send submits it.
- [ ] Save screenshots, hashes, nonzero test counts, and remaining limitations. Update the roadmap/PR checklist. No merge or deployment.

### Required send-barrier review correction

- [x] Make explicit flush failure observable at the send barrier. A failed pre-RPC recovery write retains the composer input, removes the unsent receipt, shows a recoverable save notice, and skips the prompt RPC; a successful retry clears the notice.
- [x] Revalidate the captured pipeline immediately after the awaited write. Clear only the staged draft and attachment IDs so typing or attachments added during the write survive.
- [x] Keep the revision guard and disk write synchronous inside the writer actor. Place the controllable asynchronous test barrier in `flush` after snapshot capture, and prove a delayed older flush cannot overwrite a newer persisted revision.
- [x] Run the focused delayed-write, invalidated-pipeline, and unwritable-destination regressions in isolated DerivedData and record their evidence in the implementation report.

## Working rules

You are not alone in the repository. The listed paths are fences; flag a required out-of-fence caller and continue independent work. Do not revert others' edits. Read the applicable TDD, writing-ui, visual-ui, and verifying-work skills. Do not add general abstractions, a recovery settings page, speculative retention policies, or a queue-replay feature. No nested agents, full application suite, push, merge, native app control, packaging, or dependency changes. Record owned changes, exact commands/counts, decisions, snapshots, and limits in `.superpowers/sdd/composer-drafts/report.md`.
