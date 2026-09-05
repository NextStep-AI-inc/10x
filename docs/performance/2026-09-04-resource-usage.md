# Performance and resource usage audit fixes

PR: https://github.com/NextStep-AI-inc/10x/pull/23

## Baseline and scope

The original audit inspected local main `e178acb`, which was behind the remote.
Implementation and the comparisons below use remote main `eb95373` as the baseline.
PR #20 had already moved cumulative streaming-message normalization behind the
publication cadence; PR #18 had already bounded expensive rendered content. These
changes are preserved rather than implemented again.

The interaction work in PR #22 is separate. Its composer, navigation, search,
context and native question changes are not part of this performance PR.

| Original finding | Resolution |
| --- | --- |
| Normalize every cumulative streaming snapshot | Already fixed in main by PR #20; verify existing pipeline tests and matched probe. |
| Enumerate watcher topology after every transcript append | Distinguish content writes from structural events; debounce topology refresh. |
| Reparse unchanged history at adjacent reconciliation boundaries | One cached history per controller, file identity checks, cancellation and a 50 ms debounce. |
| Keep every visited controller and process | Limit eligible inactive idle sessions; preserve active work and unsaved input. |
| Normalize a tool repeatedly while applying one update | Apply related fields atomically and skip unchanged content. |
| Allocate JSON repair candidates for valid frames | Decode valid JSON first; retain malformed-input recovery. |
| Unbounded stdout and decoded-event queues | Bound queue memory and temporary storage, preserving order and command-response progress. |

## Idle session retention

`AppModel` keeps at most four inactive idle sessions beyond the one in front of
the user (`AppModel.maxRetainedInactiveIdleSessions`), least recently visited
first, and reclaims every reclaimable one under memory pressure. A session is
reclaimable only when its controller reports nothing eviction would lose
(`SessionController.isEligibleForIdleEviction`: idle, no opening or send in
flight, no draft, attachments, pending or unconfirmed prompts, queued messages,
or runtime requests awaiting an answer) and the provider account coordinator has
no route or managed turn pending for it. Stopped and failed controllers keep
their recovery state and are never reclaimed; they hold no process.

Reclaiming disposes the controller, then records a close barrier for every path
it was reachable under. Reopening or cold-renaming that path waits for the
barrier, so a close scheduled for the old runtime cannot land on its
replacement, and any exit observed while the old runtime closed is discarded
rather than reported against the new controller. `SessionProcessManager` adds
the same guard at its level: an exit whose report was still being assembled
when a fresh open registered for the path is dropped. Under memory pressure the
warm clients go first, then the idle runtimes, which are the larger reclaim and
the slower close. A reclaimed session reopens
from persisted history like any other cold session; the cost is that reopen,
not lost work.

## Incoming queue budgets

`LineTransport.lines` (raw stdout lines) and `RpcClient.events` (decoded frames)
each sit on a `BoundedRecordQueue`:

| Budget | Value | Behavior at the limit |
| --- | --- | --- |
| In-memory encoded bytes | 4 MiB | Newer records spill to a private temporary file |
| In-memory records | 1,024 | Same |
| Spill file, physical | 65 MiB (64 MiB plus one physical frame of headroom) | `enqueue` fails; the client stops the session with a diagnostic |

The producer never waits on the consumer: the stdout reader enqueues and returns,
and the RPC reader keeps decoding responses while events queue behind a stalled
consumer, so a response can never deadlock behind the event stream. Order is
preserved by a single rule: once anything has spilled, every newer record spills
until the file is fully consumed and truncated. Consumed prefixes are compacted
only when a write would otherwise cross the cap. The spill file is created with
`mkstemp` and unlinked immediately, so it is never visible and the kernel
reclaims it if the app dies. Spilled events keep only their wire bytes and are
decoded again when read back; in-memory events keep the decoded frame.

The one record at the head of an otherwise empty queue may exceed the memory
budget transiently, so a large reassembled frame still reaches an idle consumer.
Records queued behind others must fit the spill file; the cap carries one
physical frame of headroom above the protocol's 64 MiB maximum reassembled frame
so a single maximum-size frame always fits with its length prefix. Only a real
backlog past that fails the session, explicitly, rather than being truncated. A
failed queue releases its spill file immediately.

Exhausting a budget is reported, not hidden: `RpcClient` records a protocol
error, fails pending requests with `processExited`, prefixes
`stderrSnapshot()` with `[OmpKit:RpcClient] The event backlog exceeded its
65 MiB storage budget …`, and answers any request issued after the teardown
with the same `processExited` reason. `SessionProcessManager` forwards that
text into the session's recovery message (`UnexpectedExit.stderrTail`). `RpcClient.eventBacklogMetrics` and
`LineTransport.lineBacklogMetrics` expose queue depth, spilled bytes, and peaks
for tests and future instrumentation.

## Review-round fixes

The consolidated review of the branch surfaced two defects in the earlier
commits, both fixed here with regression tests that fail on the previous code:

- The cancellable header split let a session listing run from a task that
  was cancelled mid-scan cache every remaining file as "not a session" until
  restart. The header parser now ignores the caller's cancellation, and the
  scan never caches a verdict reached under cancellation.
- Deferring watcher topology refresh behind the debounce let a transcript
  deleted and recreated within one window keep its watcher on the dead inode.
  A file watcher that sees a rename or delete is dropped at once and reopened
  by the deferred refresh.

## Reproducing the synthetic probes

On an Apple Silicon Mac with the repository's Xcode and Ruby dependencies installed:

```sh
python3 scripts/performance/audit.py --output /private/tmp/10x-audit-unique-run
```

Use a new output directory for each revision. The script builds Release without
launching the app, compiles the probes against that build, and saves revision,
compiler, build and measurement logs. Run identical probes against both revisions.
The app probe verifies the final streamed text, final tool result and history item
count. The library probe verifies JSON checksums and session counts.

These measurements isolate library/model work. They are not whole-app latency,
memory-leak, or first-token measurements. Other development sessions were active
on the same machine; small timing differences should be treated as noise.

The history probe reports `cold_ms` separately from the median of three loads of
the same file. After caching, that median measures unchanged reloads. The two tool
probes distinguish identical repeated payloads from genuinely changing results.
Watcher wall time includes deliberate write/settle sleeps; CPU time is the useful
comparison when the workload keeps up with those sleeps.

## Verification record

- Current-main baseline: `eb95373`; Release build succeeded.
- Baseline app tests: 1,223 Swift Testing tests in 28 suites plus four XCTest lifecycle tests passed.
- Baseline OmpKit tests: 188 tests, including three environment-dependent skips.
- JSON/watcher implementation: `43f9123`; 192 OmpKit tests, including the same three skips, passed.
- Tool/history implementation: `0fa2154`; 19 affected app tests and 22 parser/tree tests passed.
- Base moved to `7e04b9e` (PR #22 merged) in merge `d86e970`; no conflicts.
- Idle session retention: `41bb850`; the two new retention tests failed on the merged base without the change (7 issues) and passed with it; 112 free `AppModel*`, `SessionController*`, and `ProviderAccountCoordinator` tests passed afterwards.
- Bounded queues: `f97ac8b`; `swift test --package-path OmpKit` — 212 tests passed, three environment-dependent skips, including twelve new queue, client, and transport tests.
- Final integration at `f97ac8b`: `xcodebuild test` — 1,322 Swift Testing tests in 34 suites plus four XCTest checks passed, zero failures. Release build and probe results are recorded below.

## Final measurements

Both columns come from the same probe sources, compiled with `-O` against a
Release build: the baseline from remote main `eb95373`, the final from `f97ac8b`
(this branch after Tasks 1–4, with PR #22 merged in). Medians of three runs
unless the probe reports a single value. The machine was shared with other
sessions' `xcodebuild` runs during both measurements (load average 13–17), so
single-digit percentages and the single-value listing probes are noise; the
targeted paths moved by one to three orders of magnitude.

| Probe | Metric | Baseline eb95373 | Final | Change |
|---|---|---:|---:|---:|
| processor_1000_growing_updates | median_ms | 59.3 | 67.0 | +12.9% |
| tool_update_setters_100_3700_bytes | median_ms | 1,342.7 | 3.3 | -99.8% |
| tool_changed_updates_100_3700_bytes | median_ms | 1,508.5 | 286.6 | -81.0% |
| tool_single_construction_100_3700_bytes | median_ms | 303.3 | 284.2 | -6.3% |
| tool_update_setters_100_37000_bytes | median_ms | 11,814.6 | 30.4 | -99.7% |
| tool_changed_updates_100_37000_bytes | median_ms | 11,411.1 | 3,399.6 | -70.2% |
| tool_single_construction_100_37000_bytes | median_ms | 2,949.3 | 3,500.0 | +18.7% |
| timeline_100_messages_93673_bytes | median_ms | 197.5 | 0.3 | -99.8% |
| timeline_100_messages_93673_bytes | cold_ms | 296.1 | 157.0 | -47.0% |
| timeline_1000_messages_936972_bytes | median_ms | 1,845.0 | 2.8 | -99.8% |
| timeline_1000_messages_936972_bytes | cold_ms | 1,845.0 | 2,047.5 | +11.0% |
| timeline_3000_messages_2814971_bytes | median_ms | 6,822.2 | 8.2 | -99.9% |
| timeline_3000_messages_2814971_bytes | cold_ms | 6,822.2 | 5,371.4 | -21.3% |
| rpc_current_1000_frames_4096_bytes | median_ms | 33.7 | 6.4 | -80.9% |
| rpc_valid_json_direct_1000_frames_4096_bytes | median_ms | 9.8 | 6.0 | -38.2% |
| rpc_current_100_frames_65536_bytes | median_ms | 41.9 | 2.8 | -93.3% |
| rpc_valid_json_direct_100_frames_65536_bytes | median_ms | 5.5 | 2.7 | -50.8% |
| rpc_current_10_frames_1048576_bytes | median_ms | 57.0 | 3.7 | -93.6% |
| rpc_valid_json_direct_10_frames_1048576_bytes | median_ms | 5.7 | 3.6 | -37.6% |
| library_warm_100_files | ms | 14.2 | 9.7 | -31.7% |
| watch_100_appends_100_files | cpu_ms | 750.7 | 38.8 | -94.8% |
| watch_100_appends_100_files | wall_ms | 1,427.8 | 1,432.0 | +0.3% |
| library_warm_1000_files | ms | 107.2 | 139.4 | +30.0% |
| watch_100_appends_1000_files | cpu_ms | 7,699.9 | 118.7 | -98.5% |
| watch_100_appends_1000_files | wall_ms | 8,704.0 | 1,546.0 | -82.2% |

Readings on paths this PR did not change — the streaming processor, single tool
construction, cold timeline parsing, warm listing — moved ±10–30% in both
directions between runs, which is the noise floor here, not an effect.
The unchanged-history reloads (`median_ms` after the cold load) fall to a few
milliseconds because the loader now serves the cached history for an unchanged
file; `cold_ms` is the honest cost of opening a session for the first time.

## Live application check

`launch-release.sh` (session scratch) copied the Release product, changed its
bundle identifier to `com.nextstep.tenx.perf-audit`, re-signed it ad hoc, and
launched it with an isolated `HOME`. The process (SHA `f97ac8b`) was alive after
12 s, owned one on-screen 640 × 400 window according to
`CGWindowListCopyWindowInfo`, and exited on SIGTERM. Screen Recording is denied
to agent processes on this machine and no application-control grant was
available, so no screenshot or scripted drive of a real session was possible;
that remains for a human pass.

Session artifacts are under
`/Users/tannerpham/.codex/artifacts/10x-performance-pr23` (baselines) and the
Claude session scratch directory (final `perf-final/`, test logs).
The committed probes above are the reproducible source; local build products and
test-result bundles are intentionally not committed.
