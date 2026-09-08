# Task 4 report: bounded incoming queues without response deadlocks

Status: DONE

## Result

- `BoundedRecordQueue<Payload>` (`OmpKit/Sources/OmpKit/Wire/BoundedRecordQueue.swift`):
  lock-protected FIFO between one synchronous producer and one asynchronous
  consumer. Records live in memory up to 4 MiB of encoded bytes and 1,024
  records; newer ones spill to a `mkstemp`-created, immediately unlinked
  temporary file capped at 64 MiB of physical size. Consumed prefixes are
  compacted only when a write would otherwise cross the cap. Exceeding the cap
  fails `enqueue` with `backlogExceeded` and marks the queue failed; nothing is
  ever dropped silently.
- FIFO invariant: once anything has spilled, every newer record spills until
  the file is fully consumed and truncated. The head record of an empty queue
  may exceed the memory budget transiently; queued records must fit the cap.
- `LineTransport.lines` and `RpcClient.events` are now `AsyncStream(unfolding:)`
  views over their queues, so the public `AsyncStream<Data>` /
  `AsyncStream<RpcFrame>` types are unchanged. `StdoutDrainer` enqueues and
  stops reading when the queue refuses a line; the RPC reader keeps decoding
  responses while events queue, so a stalled event consumer cannot block a
  response. `precedingEventCount` still counts enqueued events.
- Spilled events keep only their wire bytes and are decoded again on read-back;
  in-memory events keep the already-decoded frame.
- Overflow on either queue poisons the client: a protocol error is recorded,
  pending requests fail with `processExited`, and `stderrSnapshot()` is
  prefixed with `[OmpKit:RpcClient] The <queue> backlog exceeded its N MiB
  storage budget …`, which `SessionProcessManager.reportExit` already forwards
  into the controller's recovery text. A stdout overflow leaves the child alive
  behind a full pipe, so the reader poisons instead of waiting for an exit.
- Consumer cancellation wakes the parked `next()`; queued records survive for
  a later consumer. `finish()` still delivers everything accepted at EOF.
- Test seams: `RpcClientTestHooks.eventQueueLimits` / `lineQueueLimits` /
  `beforeStartReader`, an internal `LineTransport` initializer taking
  `lineQueueLimits`, and `eventBacklogMetrics` / `lineBacklogMetrics` /
  `transportBacklogFailure` readers. New fake-server modes `line-flood N S`
  and `event-flood N S`.

## TDD evidence

RED: the new tests reference `BoundedRecordQueue`, `BoundedRecordQueueLimits`,
the limit hooks, and the metrics seams, none of which existed, so the first
OmpKit build failed to compile (`ompkit-task4-v1.log`; the surviving error in
that log is the queue's own `NSLock` use inside an async function, fixed by
moving locking into synchronous poll/park steps).

GREEN (`ompkit-task4-v2.log`): `swift test --package-path OmpKit` — 212 tests
passed, 3 environment-dependent skips, 2.97 s. The twelve new tests:

- `BoundedRecordQueueTests`: order through memory → spill → memory, oversized
  head vs. queued records, overflow at the cap with later records ignored,
  compaction of a consumed prefix before the cap fails, cancelled consumer
  wake-up, spill file never visible on disk, `close()` metrics.
- `RpcClientTests`: `stalledEventConsumerDoesNotBlockResponses` (3,000 × 4 KiB
  events ahead of a `get_state` response with nobody reading `events`; the
  response arrives, spill happened, memory stayed within budget, all 3,000
  events then replay in order and the spill file is truncated),
  `eventBacklogOverflowStopsTheSessionWithADiagnostic` (8 KiB / 64 KiB limits;
  request fails with the diagnostic in `stderrTail`, `termination` finishes,
  `stderrSnapshot()` is prefixed, a protocol error is recorded),
  `stdoutBacklogOverflowStopsTheSessionWithADiagnostic` (reader held back with
  `beforeStartReader`; startup fails with the stdout diagnostic).
- `LineTransportTests`: spill beyond a 64 KiB memory budget replays 2,000
  lines in order after the child exited; overflow ends `lines`, records
  `backlogFailure`, and `shutdown()` still reaps the wedged child in < 5 s.

## Caveats

- Budgets count encoded bytes; decoded `JSONValue` trees beside in-memory
  records are larger, so the memory figure is a floor, documented as such.
- A 64 MiB reassembled frame queued behind anything else cannot fit the 64 MiB
  spill cap and fails the session explicitly; documented in
  `docs/performance/2026-09-04-resource-usage.md`.
- Whole-app runs, Release build, and probes belong to Task 5.
