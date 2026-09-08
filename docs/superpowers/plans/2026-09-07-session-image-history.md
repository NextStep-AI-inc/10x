# Restore persisted image attachments

The approved active-session audit requires image continuity, receipt reconciliation, and reopening saved input. Release testing of recovery commit `9afb324` found that OMP 18.1.10 writes `blob:sha256:<hash>` references into JSONL. The app passes those references to its base64 image renderer, which shows a placeholder and cannot match the original pending submission. This dependency is being handled before the remaining queue/image acceptance checks.

## Design and constraints

Hydrate image content at the shared `SessionTimelineLoader` boundary, before `TranscriptHistoryMapper`. Keep session parsing and indexing free of filesystem side effects. Preserve entry IDs, metadata, order, and inline base64 images. The trusted default blob directory is the sibling of the app's default sessions directory: `~/.omp/agent/blobs`; inject a directory in tests. Never derive that directory from a session's content or path.

Resolve only image content objects' `data` fields that exactly match OMP's lowercase 64-digit SHA-256 reference format. Open the referenced regular file without following a final symlink and verify its content hash. Missing, invalid, non-regular, or mismatched blobs retain the existing attachment fallback. An unresolved valid reference must not become a permanent cache hit, because a blob may appear after the transcript write. Successfully hydrated, unchanged timelines retain the existing cache behavior. Do not weaken image equality in pending-submission reconciliation.

## Task 1: Load persisted image bytes

Owned files: `App/Sessions/SessionTimelineLoader.swift`, a small colocated `SessionImageBlobResolver.swift` if needed, `Tests/TenXAppTests/SessionTimelineLoaderTests.swift`, and generated `10x.xcodeproj/project.pbxproj` only through `ruby scripts/generate_xcodeproj.rb`.

- [x] Add a failing loader test using a temporary blob directory and valid PNG bytes referenced from a user message. Assert the mapped image's bytes equal the original and `PendingUserSubmission.reconcile` consumes the matching receipt exactly once.
- [x] Add table-driven invalid/missing/uppercase/traversal/wrong-hash/symlink cases that preserve the reference, plus missing-then-created recovery with an unchanged transcript. Keep unrelated text and inline base64 unchanged.
- [x] Implement the minimum resolver at the loader boundary. Traverse known message image content positions only; do not rewrite arbitrary blob-like strings or resolve arbitrary paths. Use existing JSONValue and SessionEntry values without changes to OmpKit.
- [x] Verify unchanged successful loads reuse the cache and changed/replaced/cancelled session loads retain their existing behavior. Run the focused timeline and pending-submission tests, then the app suite. Six expanded activity snapshot references already fail identically at baseline `e60234a`; record that known baseline if still present, without rerecording it here.
- [x] Commit implementation and tests with exact check results in the task report.

## Task 2: Verify the actual Release experience

- [x] Parent review of lookup boundaries, cancellation, cache behavior, and receipt identity.
- [x] Build Release and launch an isolated app/profile through native UI automation. Reopen the saved image-bearing session captured by recovery QA and confirm the thumbnail renders.
- [x] Send one harmless image-bearing prompt, wait for persistence, and confirm exactly one user message with its image and no duplicate pending receipt. Relaunch and reopen that session to confirm the image survives.
- [x] Commit screenshots, artifact SHA/build commit, and a short verified/not-verified record. Update the PR and roadmap; no merge or deployment.

## Decision record

- Reuse the shared loader instead of changing rendering or receipt matching: one restoration point covers live boundary reconciliation and cold reopening.
- Preserve bad references visibly instead of failing the whole session: a missing image must not prevent reading the remaining conversation.
- `origin/main` advanced to `0be4353` with settings-editor changes during this run. This branch stacks on recovery `7e9c4be`; those changes do not overlap the owned implementation paths. Base integration and the known snapshot failures remain PR-readiness gates.

## Execution record

Production commits: `ee5276f` and `6e3bec4`. Parent lookup/cache/receipt and FIFO review accepted. All 12 relevant tests pass after the FIFO correction. Actual Release pixels, live receipt reconciliation, and quit/relaunch/reopen passed; [evidence](../evidence/2026-09-07-session-image-history/README.md) records the exact artifact, screenshots, and full-suite limits. The image dependency is handled; unsent disk drafts remain in INPUT. PR #34 remains draft on the documented baseline/base gates.
