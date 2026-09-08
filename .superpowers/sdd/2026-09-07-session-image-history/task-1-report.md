# Task 1 report: persisted session image bytes

Status: DONE_WITH_CONCERNS

## Result

- `SessionTimelineLoader` hydrates exact `blob:sha256:` references in known message image content before mapping the active timeline.
- The default trusted store is `~/.omp/agent/blobs`; tests inject a temporary store.
- Blob reads open the final component with `O_NOFOLLOW`, require a regular file, and verify the SHA-256 digest before replacing the reference with base64.
- Missing, malformed, uppercase, traversal-shaped, wrong-hash, directory, and symlink inputs keep their original attachment fallback.
- A valid unresolved reference prevents a cache install, so an unchanged transcript recovers when its blob appears. Successful unchanged loads retain the existing cache.
- `TranscriptHistory`, parsing, receipt equality, and OmpKit are unchanged.

## Scope ledger

- Resolution is limited to `SessionEntry.message` → message `content` array → blocks whose `type` is `image` → `data`. Blob-like text and unrelated content fields are preserved.
- Entry bases, IDs, timestamps, message metadata, order, text blocks, and inline base64 images are preserved.
- The trusted blob root comes only from loader construction. Session content and session paths cannot choose it.
- No new Swift file was added, so project regeneration was unnecessary.
- The branch remained on its existing recovery stack; no merge, rebase, push, PR mutation, or main-worktree change was made.

## TDD evidence

RED: the selected test build exited 65 because `SessionTimelineLoader` had no `blobDirectory` injection and therefore could not express the required hydration boundary. Production code was added only after that failure.

GREEN:

- 12 selected loader and pending-submission tests passed. This includes valid hydration, exact-once receipt consumption, cache reuse, missing-then-created recovery, every rejection case, and the existing changed/replaced/cancelled/read-change cache tests.
- The final selected run reported `Test run with 12 tests in 0 suites passed after 0.014 seconds`.
- The first full app run executed 1,383 tests in 34 suites. The image-history tests passed. It reproduced only the six documented baseline activity snapshot failures: `activityDisclosureSnapshotDark`, `structuredDiffSnapshot`, `subagentActivitySnapshot`, `activityDisclosureSnapshot`, `subagentActivitySnapshotDark`, and `activityStructuredDiffDarkSnapshot`.
- A second full run after test cleanup reproduced those six and also hit four assertions in unrelated `openingASessionWhileItsNewSessionOpenIsInFlightReusesItsController`. That test passed immediately in isolation: 1 test in 0 suites after 0.662 seconds. No out-of-scope navigation code was changed.
- `git diff --check` passed before the report was written.

## Not verified

- Real Release rendering, live send/reconciliation, and relaunch/reopen behavior are parent-owned Task 2 work.
- The six baseline activity snapshot references were not rerecorded.
