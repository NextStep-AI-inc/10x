# Task 3 report: bounded idle session retention

Status: DONE

Commit: `41bb850 perf(app): bound inactive idle session retention`, on top of
`d86e970 merge: origin/main (PR #22) into codex/performance-audit-fixes`.

## Result

- `AppModel` keeps at most `maxRetainedInactiveIdleSessions` (4) inactive idle
  sessions beyond the active one, least recently visited first. Visiting a
  session (`openSession`, `startNewSession`, controller creation) moves it to
  the front of `sessionVisitOrder`; `openNewSession`, `chooseProject`, and
  every controller activity change schedule one deferred budget review.
- `handleMemoryPressure()` first reclaims every reclaimable inactive idle
  session and waits for their runtimes to close, then continues with the
  existing warm-client eviction.
- `SessionController.isEligibleForIdleEviction` is the controller's own view of
  "nothing to lose": idle, no opening or send in flight, no title generation,
  empty draft/attachments/initial attachments, no pending slash attachments or
  pending submissions, no queued messages, no pending user input, no extension
  sheet, inline request, timeout, or response in flight.
- `ProviderAccountCoordinator.hasPendingWork(sessionID:)` keeps sessions with a
  pending or desired route, a routing tail, or an active managed turn out of
  eviction; nothing is reclaimed while `canCreateManagedSession` is false (an
  account removal is reassigning sessions).
- Reclaiming calls `dispose()` before `removeManagedSession`, so the close
  targets the live handle's path, then records a per-path close barrier.
  `openSession` and `renameColdSession` await the barrier for that path, and
  exits observed while the old runtime closes are dropped from
  `pendingUnexpectedExits` when the barrier completes.
- `stopped`/`failed` controllers are deliberately not reclaimable: they hold no
  process and their recovery UI is load-bearing.

## TDD evidence

The two tests were inherited from the Codex thread's uncommitted work. Their
fixture spawned the fake server in `/tmp/Project`, which does not exist here,
so the first run failed on startup rather than on retention; the fixture now
creates a project directory and passes it as `cwd`.

RED (`red-task3-v2.log`, merged tree without the implementation): 2 tests,
7 issues, all on the retention assertions — the least-recent session was never
removed, memory pressure evicted nothing, and the reopened controller was the
original.

GREEN (`green-task3-v1.log`): both tests passed in 5.8 s.

Regression (`task3-regression.log`): 112 free `@Test` functions from
`AppModel*Tests`, `SessionController*Tests`, and
`ProviderAccountCoordinatorTests` passed in 7.8 s at commit `41bb850`
(suite-nested tests are covered by the full run in Task 5).

## Caveats

- Eviction runs one main-actor hop after the trigger, so tests that count
  managed sessions immediately after opening a fifth inactive session must
  wait, as the new tests do.
- Real OMP reports the resumed session file as its `sessionFile`, so the
  handle path and the reported path coincide; the barrier is keyed by every
  path indexed for the controller in case they ever differ.
