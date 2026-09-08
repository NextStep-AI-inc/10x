# Task 5 review-fix report

Status: DONE_WITH_CONCERNS

## Implemented

- Remote authorization is journaled before every computer or host-tool mutation.
  Stop validates host-tool removal and computer disable before local cleanup; an
  indeterminate response reaches the injected session-process force-close seam
  and reports `Unavailable`, never `Off`.
- The two-second Stop budget covers host settling, abort, and remote teardown.
- Focus isolation rejects providers that cannot isolate. Background remains
  explicit legacy best-effort only.
- Legacy `/computer` commands require an explicit `agentInvoked: false` reply.
  Unsupported structured reconciliation attempts validated legacy off.
- `get_state` now has a typed model/computer availability snapshot. It avoids
  `dumpTools`, which Code Mode can alter, and focus mode fails closed on a
  missing/inactive model or disabled/malformed computer state.
- Host calls run as controller-owned tasks keyed by exact ID. Cancellation is
  recorded synchronously, results are sent once, and late results cannot revive
  a stopped generation. Manifest outcomes from cancelled calls remain available
  for cleanup.
- Session teardown cancels stream/reconciliation/extension work, stops computer
  use, and closes the child. AppModel serializes replacement before assigning a
  new active controller and uses a single temporary transition reference for
  exit routing.
- Behavioral capture and background-input probe failures now return to the
  controller for `needsHandoff`; invalid capabilities still fail technically.

## Verification

- `ruby scripts/generate_xcodeproj.rb` completed with no generated diff.
- `swift test --package-path OmpKit`: 139 tests passed, 2 existing environment
  skips. Includes supported and rejected legacy command variants.
- `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-task5-review-app`:
  159 tests passed.
- `xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/tenx-task5-review-release`:
  succeeded.

## Remaining concerns

- The review asked for a complete per-seam failure matrix and deterministic
  AppModel rapid-replacement/deallocation tests. The safety paths are
  implemented and covered by focused lifecycle tests, but that exhaustive test
  expansion was not completed in this fix round.

## Round 2 follow-up

Status: DONE

- Enablement carries a lifecycle generation through every suspension point. A
  concurrent Stop invalidates the generation, releases a late prepared desktop,
  and prevents delayed OMP enablement from registering tools or reviving Ready.
- Deadline-aware transport, RPC, and process-manager shutdown now return a
  confirmed-dead result. A non-confirmed close retains its handle and journals;
  normal closure remains intentionally silent while force-close retains the
  unexpected-exit route for later confirmed death.
- Structured refresh first validates typed availability, then reissues
  `set_computer_use(true, require-handoff)` as OMP's model-authoritative
  revalidation. Legacy refresh fails closed because it has no equivalent proof.
- Host-tool registration requires an exact acknowledged `toolNames` set.
- Controller deinitialization cancels its manifest watcher and outstanding host
  tasks. The watcher task keeps only a weak controller reference.

### Debugging note

The first complete OmpKit run exposed a repeatable shutdown hang in the
grandchild fixture. The leader correctly exited on stdin EOF, but its inherited
stdout child remained in the captured process group; `StdoutDrainer.finish()`
then blocked in `readToEnd()`. An early success return introduced by the
deadline change skipped group TERM/KILL. Shutdown now continues group teardown
after leader EOF before final stream draining. The normal-close watcher race was
also preserved as an intentional close, so it cannot be reported as a crash.

### Round 2 verification

- `ruby scripts/generate_xcodeproj.rb` completed with no generated diff.
- `swift test --package-path OmpKit`: 141 tests passed, 2 environment skips.
  The isolated inherited-stdout grandchild test passed in 0.695 seconds.
- `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task5`:
  164 tests passed, including delayed prepare/enable races and controller
  deinitialization watcher cancellation.
- `xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/tenx-agent-desktop-task5-release`:
  succeeded.

## Round 3 follow-up

Status: DONE_WITH_CONCERNS

- Each enable, refresh, and host-tool registration mutation is represented by a
  controller-owned task. Stop invalidates its generation, cancels and settles
  those tasks before it begins unregistering or disabling, and forces the
  owning process closed when the shared deadline is exhausted. The stateful
  delayed-enable test verifies remote computer state finishes disabled, tools
  finish empty, and the registry is released last.
- A process exit is now distinct from stdout EOF. `LineTransport` reports exit
  from `Process.terminationHandler`; `RpcClient` keeps natural trailing frames
  available until stream EOF. Forced shutdown closes the reader instead of
  draining an inherited stdout pipe indefinitely, while group/descendant death
  is still confirmed before it returns success.
- Host-tool acknowledgement accepts only a complete all-string exact set; the
  fixture now also exercises a mixed string/number acknowledgement.
- Controller deallocation uses a lock-protected cancellation bag rather than
  `MainActor.assumeIsolated`. Cancelling an outer host task now forwards its
  exact call ID to the host tool.
- If force-close cannot prove death inside the deadline, controller resources
  remain owned. Session teardown does not issue a normal close in that state;
  AppModel retains the session for the real unexpected-exit event and then
  removes that temporary ownership exactly once. Resource cleanup itself runs
  only after remote Off or confirmed process death and remains retained if the
  shared Stop budget expires.

### Debugging note

The first full app run in this round failed
`stopDuringDelayedPrepareReleasesTheLateDesktopWithoutEnablingOMP`. The task
invoking `enable()` had not necessarily run before the test slept for 20ms;
therefore Stop observed `Off`, and enable later legitimately began with the
new generation. The delayed lifecycle now emits a pre-suspension marker and
the test waits for that marker, establishing the intended in-flight race before
stopping. The subsequent complete app suite passed.

### Round 3 verification

- `ruby scripts/generate_xcodeproj.rb` completed with no generated diff.
- `swift test --package-path OmpKit`: 141 tests passed. The inherited-stdout
  grandchild shutdown case passed in 1.754 seconds.
- `xcodebuild -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS,arch=arm64' test`:
  166 tests passed.
- `xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS,arch=arm64' build CODE_SIGNING_ALLOWED=NO`:
  succeeded.

### Remaining concern

The round requested an integrated controller-to-manager slow-resource-cleanup
test and a detached-context deinit/host-launch cancellation test. The retained
ownership and cancellation paths are implemented and covered by the existing
controller/transport tests, but those two extra integration harnesses were not
added in this pass.

## Round 4 follow-up

Status: DONE

- Remote mutations remain controller-owned until their underlying operation
  actually completes. Caller cancellation no longer removes or cancels the
  tracked task; Stop waits within its existing shared deadline, then relies on
  confirmed process death before releasing local safety ownership.
- Resource cleanup has one shared task. The manifest, prepared desktop, lease,
  and registry ownership are detached synchronously before its first await, so
  Stop and process-exit handling can only join the same cleanup operation.
- Every retiring `SessionController` has independent ownership keyed by its
  identity. Exit watchers are retained per originating process-manager
  identity, and exit routing compares the manager handle's immutable session
  path rather than the mutable path returned by `get_state`. OMP replacement
  excludes every safety-owned old-manager handle from normal closure.
- Manager termination is now group-confirmed. `LineTransport` tracks detached
  descendants with Darwin's in-process child-PID API, escalates TERM/KILL to the
  process group and captured descendants, and returns success only when the
  leader, group, and descendants are all dead. Natural leader exit drains
  trailing frames in bounded chunks; forced shutdown discards pending bytes.
  `SessionProcessManager` does not remove the handle or emit its exit until
  that confirmation succeeds.

### Round 4 TDD evidence

- The cancellation-settlement regression failed with the delayed enable write
  occurring after disable and final remote state still enabled; it passes with
  lease/registry release after actual mutation settlement.
- The slow cleanup/process-exit race failed with two provider cleanup calls; it
  passes with one cleanup, one desktop/lease/registry release, and release only
  after the gate opens.
- Natural leader exit and deadline force-close regressions failed while their
  detached grandchild heartbeat continued after manager removal/event; both
  pass with an unchanged heartbeat after the event.
- Rapid transition and installation replacement tests failed when remote
  `get_state.sessionFile` intentionally differed from the manager handle path;
  both pass with exact originating-manager ownership and one release per owner.
- Reopening a still-safety-owned path initially routed the one confirmed-exit
  event to the new active controller and stranded the retiring owner. The
  regression passes after exit routing gives the exact retiring safety owner
  priority for a shared manager handle.

### Debugging note

The first complete OmpKit run passed 142 of 143 tests but timed out an existing
one-second host-tool event test. The initial descendant tracker spawned
`pgrep` every 20ms for every concurrent client, inflating otherwise subsecond
tests to roughly 1.5 seconds. Replacing it with `proc_listchildpids` removed the
load: the isolated transport/manager set passed in 0.716 seconds and the next
complete package run finished in 1.160 seconds.

### Round 4 verification

- `swift test --package-path OmpKit`: 143-test run passed (141 executed, 2
  environment-only skips).
- `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination
  'platform=macOS,arch=arm64' -derivedDataPath
  /tmp/tenx-task5-round4-app-tests -only-testing:TenXAppTests`: 171 tests passed.
- `xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release
  -destination 'generic/platform=macOS' -derivedDataPath
  /tmp/tenx-task5-round4-release CODE_SIGNING_ALLOWED=NO build`: succeeded;
  `lipo -archs` reported `x86_64 arm64`.
- `ruby scripts/generate_xcodeproj.rb` completed with no generated project
  diff. `git diff --check` completed without errors.

### Not verified

- No manual UI walkthrough was run because this round changes lifecycle and
  transport behavior only and adds no user-facing UI or copy.

## Round 5 follow-up

Status: DONE

- A confirmed manager exit now snapshots and notifies every retiring controller
  that owns the exact originating manager/immutable handle path, then notifies a
  distinct matching active controller. Each snapshotted retiree is removed only
  if it is still the same retained object after cleanup completes.
- Process teardown tracks Darwin identities as PID plus `proc_bsdinfo` start
  time. Dead and reused identities are pruned, every target is revalidated
  before signaling, and the original process group is signaled only while an
  exact original leader or descendant anchors it. A reused leader prevents a
  group signal; surviving original descendants are signaled individually.
- Child/group enumeration and the tracked identity set have fixed 4096-entry
  caps, traversal checks the caller's shutdown deadline, and a tree that was
  never completely observed cannot later certify termination. Real detached-descendant
  heartbeat tests remain the production check for natural and forced shutdown.
- The transport line queue and RPC event queue each have a fixed 512-frame cap.
  Byte-line or queue overflow terminates the stream and poisons the RPC
  connection instead of resynchronizing or dropping a protocol frame.
- Natural shutdown polls reader completion only inside the shared deadline.
  The reader is cancelled/finalized at the deadline, while normal trailing
  frames are preserved when they drain in time. Process termination still wakes
  the manager independently of reader-owned event completion.
- The descendant tracker uses a weak owner guard, cancels on shutdown, and has
  deterministic shutdown-poll and abandoned-transport deallocation coverage.

### Round 5 TDD evidence

- The same-path A → B → C lifecycle regression failed with the active owner
  never reaching recovery, the original lease unreleased, and both retirees
  retained. It passes with one notification per controller and no retained
  retired owner.
- Stable-identity tests first failed because the transport had only raw PID and
  PGID tracking. Reused leader/child identities and a stale numeric group now
  receive no signal; a reused leader with a still-original descendant avoids
  group kill and targets only that exact descendant.
- A deliberately incomplete process enumeration initially became a false
  confirmed-dead result after the leader disappeared. A persistent complete-
  observation gate now keeps that result unconfirmed.
- Backlog tests initially found a non-throwing unbounded line stream and an
  unbounded RPC event stream. Both transport-level and client-level overloads
  now fail closed within the test deadline, while 200 normal trailing frames
  still arrive.
- A reader gate proved the old natural shutdown remained blocked after its
  100 ms deadline. The bounded implementation returns before the 300 ms
  observation point and cancels the reader.
- The first focused force-close run exposed that preserving reader ownership
  had also suppressed the manager's termination wake-up. Separating termination
  notification from event completion restored both deadline-false and natural
  detached-grandchild behavior.

### Round 5 verification

- `swift test --package-path OmpKit`: 154-test run passed in 2.862 seconds
  (152 executed, 2 environment-only skips).
- `xcodebuild -project 10x.xcodeproj -scheme 10x -destination
  'platform=macOS,arch=arm64' -derivedDataPath /tmp/tenx-round5-app-final test`:
  172 tests passed in 2.832 seconds; `** TEST SUCCEEDED **`.
- `xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release
  -destination 'generic/platform=macOS' -derivedDataPath
  /tmp/tenx-task5-round5-release CODE_SIGNING_ALLOWED=NO build`: succeeded;
  `lipo -archs` reported `x86_64 arm64`. The only warning was the existing
  no-AppIntents metadata-extraction notice.
- `ruby scripts/generate_xcodeproj.rb` completed with no generated project
  diff. `git diff --check` completed without errors.

### Not verified

- No manual UI walkthrough was run because round 5 changes only process,
  protocol-backpressure, and controller ownership behavior; it changes no UI or
  user-facing copy.

## Round 6 follow-up

Status: DONE_WITH_CONCERNS

- Process-tree termination certification is no longer sticky. Any later
  incomplete, capped, interrupted, or deadline-bounded observation while an
  original identity may still be live invalidates the prior certificate. Only
  a subsequent complete observation anchored by the original leader or an
  exact retained descendant can certify the tree again.
- Every manager handle now has an immutable UUID generation carried in its
  unexpected-exit event. `SessionController` and `AppModel` match the exact
  originating manager and generation, so a buffered exit from an old process
  cannot stop a new same-path process. Exit fan-out removes each notified owner
  from current retiring storage immediately after its awaited notification,
  including an active owner that became retiring through reentrancy.
- Transport lines use an 8 MiB cumulative queued-byte budget. RPC events use a
  65 MiB budget, sufficient for one maximum 64 MiB reassembled v2 event plus a
  maximum 1 MiB physical control frame. Bytes are charged from the exact input
  or reassembled `Data.count` before enqueue and released by a unique lease on
  consumption, drop, or stream teardown. Count caps remain as a second bound;
  either overflow fails closed rather than dropping a protocol frame.
- Short transport shutdown deadlines are divided across graceful, TERM, and
  KILL phases. This preserves the caller's deadline while ensuring the grace
  phase cannot consume all time needed to reap an overflowed peer.

### Round 6 TDD evidence

- A complete process observation followed by an incomplete live-tree read
  initially retained the old certificate and reported termination after the
  leader disappeared. Tracker- and manager-level regressions now retain the
  handle and suppress the event until a complete observation anchored by the
  original descendant recovers certification and the descendant then exits.
- An old same-path manager exit initially stopped the reopened active session.
  Exact generation matching leaves the new controller untouched. A separate
  gated cleanup test initially retained an active owner that moved to retiring
  during an earlier notification; both old owners now deallocate and release
  once.
- Count-only transport and RPC queues initially accepted aggregate legal frames
  above their byte budgets. Both now poison and shut down within their existing
  deadlines. One near-physical-limit line and one maximum reassembled event
  remain accepted, and the existing 200-frame trailing drain still passes.

### Debugging note

The first complete OmpKit run exposed that a one-second shutdown could spend
its entire deadline waiting for graceful EOF before signaling an overflowed
child. The focused test passed only when a broken pipe happened to end the
fixture early. Dividing the existing deadline among shutdown phases made the
behavior deterministic without increasing it; the next complete run passed.

The first clean app run also exposed the pre-existing 50 ms scheduling sleep in
`exactAgentDesktopBorrowAndCancellationRouteToTheRegisteredHostTool`: under
parallel suite load neither host task ran before its assertion. The unchanged
test passed in the next exact full run; this timing-sensitive test remains a
suite concern outside the round-6 ownership changes.

### Round 6 verification

- `swift test --package-path OmpKit`: 162 tests passed in 2.809 seconds.
- `xcodebuild -project 10x.xcodeproj -scheme 10x -destination
  'platform=macOS,arch=arm64' -derivedDataPath /tmp/tenx-round6-app-final2
  test`: 174 tests passed in 2.870 seconds; `** TEST SUCCEEDED **`.
- `xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release
  -destination 'generic/platform=macOS' -derivedDataPath
  /tmp/tenx-round6-release-final2 CODE_SIGNING_ALLOWED=NO build`: succeeded;
  `lipo -archs` reported `x86_64 arm64`.
- `ruby scripts/generate_xcodeproj.rb` completed with no generated project
  diff. `git diff --check` completed without errors.

### Not verified

- No manual UI walkthrough was run because round 6 changes lifecycle identity,
  process certification, and protocol backpressure only; it changes no UI or
  user-facing copy.

## Round 7 follow-up

Status: DONE

- Entering `ProcessTreeTracker.refresh` with an already-expired deadline now
  clears any previous complete-observation certificate before returning. A
  later anchorless scan therefore cannot reuse stale proof to report the tree
  terminated.
- `LineTransport.shutdown` requires its pre-close tree observation to complete
  before it closes stdin. A skipped observation returns `false` without
  changing the child, allowing a later deadline-bearing retry to establish
  fresh anchored proof and perform normal group-confirmed shutdown.
- Intermediate shutdown phase waits stop at their sub-deadline without calling
  the tracker once more with that expired sub-deadline. Valid proof established
  before TERM/KILL is retained unless a real incomplete observation invalidates
  it.

### Round 7 TDD evidence

- The tracker sequence complete anchored observation → expired refresh → all
  anchors disappear initially reported termination. It now remains
  unconfirmed.
- The manager regression initially removed the handle and emitted an exit after
  an expired force-close destroyed the leader anchor. It now retains the handle
  and emits no event until the fake process identity is re-anchored by a new
  complete observation.
- Zero-deadline force-close initially closed stdin despite skipping its
  pre-close observation. It now leaves both a simple child and detached
  grandchild running and owned; a retry with a real deadline shuts down the
  group, confirms death, and removes the handle.

### Round 7 verification

- `swift test --package-path OmpKit`: 164 tests passed in 3.143 seconds.
- `xcodebuild -project 10x.xcodeproj -scheme 10x -destination
  'platform=macOS,arch=arm64' -derivedDataPath /tmp/tenx-round7-app test`:
  174 tests passed in 3.791 seconds; `** TEST SUCCEEDED **`.
- `xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release
  -destination 'generic/platform=macOS' -derivedDataPath
  /tmp/tenx-round7-release CODE_SIGNING_ALLOWED=NO build`: succeeded;
  `lipo -archs` reported `x86_64 arm64`.
- `ruby scripts/generate_xcodeproj.rb` completed with no generated project
  diff. `git diff --check` completed without errors.

### Not verified

- No manual UI walkthrough was run because round 7 changes only process
  certification and shutdown sequencing; it changes no UI or user-facing copy.

## Round 8 follow-up

Status: DONE

- `ProcessTreeTracker` now produces observation completeness and certified
  termination from one bounded scan. `refresh` and `isTerminated` are wrappers
  over that result instead of `isTerminated` starting a second refresh and
  leader lookup.
- Each `LineTransport.hasExited` poll performs exactly one certification scan:
  a running Foundation process records the live tree, while an exited leader
  asks the tracker for the single scan's termination result. A confirmed
  graceful or TERM-phase exit completes shutdown immediately rather than
  starting later signal phases that can no longer add evidence.
- The existing process seam now supplies the tracker clock, and the existing
  tracker-poll hook is forwarded through the internal RPC test initializer.
  This permits a deterministic manager regression without wall-clock sleeps:
  it kills the leader immediately after a complete anchored poll, advances the
  tracker clock during dead snapshots, and verifies a later valid poll emits
  the matching-generation exit and removes the handle.

### Round 8 TDD evidence

- With the old redundant `hasExited` refresh restored, the deterministic
  manager regression failed in 3.435 seconds: no exit event arrived and the
  old handle remained retained. The first scan consumed the sub-deadline and
  the second entry invalidated its previously complete certificate.
- With the single-observation implementation restored, the same regression
  passed in 0.048 seconds. The matching handle generation was emitted, the
  manager removed the handle, and confirmation remained valid on the later
  shutdown poll.
- The related certification, detached-grandchild, bounded-reader, and tracker
  lifecycle selection passed: 7 tests in 2.728 seconds.

### Round 8 verification

- `swift test --package-path OmpKit`: 165 tests passed in 2.751 seconds.
- `xcodebuild -project 10x.xcodeproj -scheme 10x -destination
  'platform=macOS,arch=arm64' -derivedDataPath /tmp/tenx-round8-app test`:
  174 tests passed in 4.320 seconds; `** TEST SUCCEEDED **`.
- `xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Release
  -destination 'generic/platform=macOS' -derivedDataPath
  /tmp/tenx-round8-release CODE_SIGNING_ALLOWED=NO build`: succeeded;
  `lipo -archs` reported `x86_64 arm64`.
- `ruby scripts/generate_xcodeproj.rb` completed with no generated project
  diff. `git diff --check` completed without errors.

The first full OmpKit run exposed interference from the regression's initial
blocking `Thread.sleep` clock simulation: the unrelated one-second trailing
frame test missed its deadline under parallel load while passing alone. The
fixture now advances an injected monotonic tracker clock without blocking an
executor thread; the final complete run passed.

### Not verified

- No manual UI walkthrough was run because round 8 changes only process-tree
  observation and shutdown sequencing; it changes no UI or user-facing copy.
