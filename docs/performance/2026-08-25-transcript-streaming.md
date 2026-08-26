# Transcript streaming performance

**Status:** Baseline and Fixed VERIFIED for the contract-correct `10x-transcript-burst 1.1.0` workload. The baseline production source is `f30e38403ec06c00ae335bb4d539502d7c641f39`; the fixed production source is `f9f22ae7e8248c96face8ff47c6974ebac595638`.

The accepted runs are baseline `contract-1.1h` (app PID 27955) and fixed `fixed-ax-1.0b` (app PID 26762). Both drove Release builds through real macOS controls, ran the same 1,000-update fixture contract, produced valid native sampler and Time Profiler exports, proved their exact owned child, reached the terminal UI state, and completed identity-checked cleanup.

## Result

| Measurement | Baseline | Fixed |
| --- | --- | --- |
| Real 1,000-update UI workload | Release XCUITest passed 1/1; Steer appeared and disappeared, Send message remained, terminal screenshot retained. | Release external AX driver passed; Steer appeared and disappeared, Send message remained. 52 snapshots were installed from the 1,000 raw updates. |
| Peak app CPU | 49.49%; independent `top` peak 50.4%. | 23.93%; independent `top` peak 22.7%. **51.6% lower.** |
| Peak RSS | 146,096,128 B (139.33 MiB). | 113,197,056 B (107.95 MiB). **22.5% lower.** |
| Peak physical footprint | 53,462,024 B (50.99 MiB). | 39,699,440 B (37.86 MiB). **25.7% lower.** |
| Main-thread sampled time | Approximately 2.358 s within Send/terminal bounds; 2.612 s over the full trace. | 0.340 s within exact fractional Send/terminal bounds; 0.345 s over the full trace. **85.6% / 86.8% lower.** |
| Visible responsiveness | Start session → Composer mode, Steer → Send message. | Start session → Composer mode, Steer → Send message. |
| Post-terminal idle | At +8.094 s: 0.01% CPU, 145,948,672 B (139.19 MiB) RSS, 53,019,656 B (50.56 MiB) footprint. | At +8.050 s: 0.00% CPU, 105,447,424 B (100.56 MiB) RSS, 35,783,664 B (34.13 MiB) footprint. |
| Reference-resolved hot rows | Accessibility text 117; ViewGraph render 413; SessionController.consumeEvents 13; ViewGraph.updateOutputs 148; MessageContentParser.parse 18; TranscriptReducer.consume 3. | Accessibility text 49; ViewGraph render 59; SessionController.consumeEvents 0; ViewGraph.updateOutputs 19; MessageContentParser.parse 0; TranscriptEventProcessor 16; TranscriptReducer.consume 9. |
| Installed-snapshot cadence | No snapshot signpost existed. | 52 installs; 19, 19, and 14 by wall-clock second. Maximum nonterminal rate 19/s, below the accepted burst's 20/s target. |

The poor performance came from multiplying work at every layer. Each growing RPC snapshot was decoded and reduced on the `MainActor`, the entire transcript array was reassigned even when a frame caused no visible mutation, and every assignment invalidated SwiftUI subtrees that reparsed unchanged assistant Markdown and accessibility text. Unsupported frames also accumulated invisible raw-event rows. Session replacement could leave stale pipeline continuations or a process handle alive long enough to publish into the replacement session.

The fixed pipeline reduces frames in an actor, discards unsupported or malformed no-op frames, and coalesces supersedable snapshot installs through a newest-one buffer and 50 ms cadence. The accepted burst stayed below 20 nonterminal installs per second, while lifecycle/control boundaries remain immediate and lossless. Generation and context guards reject stale continuations and session close now owns exact process disposal. SwiftUI's expensive assistant content subtree is equatable by message identity, visible text, and finality while live response metadata remains outside that seam.

The baseline XCUITest and fixed external Accessibility driver both poll app accessibility state, so their traces include app-side accessibility work. No overhead was subtracted. Because the drivers differ, elapsed wall time is not treated as a strict A/B metric; CPU, memory, sampled main-thread time, named stacks, and terminal state are the acceptance evidence.

## Regression guardrails

The deterministic `transcript-burst` fixture remains a runnable 1,000-update stress case. Tests lock down the properties that prevent recurrence: no more than 20 coalesced publications per second, final snapshots before reconciliation, lossless extension/control boundaries, stale-generation rejection, exact process disposal, 10,000 unknown events producing no transcript rows, and assistant-content equality excluding unrelated transcript and metadata changes.

`TranscriptSnapshotInstalled` and the search points of interest make future Release traces directly countable without logging prompt content. Re-run the preserved Release capture after changes to event reduction, snapshot publication, transcript rendering, session lifecycle, or the RPC fixture. Treat a return of `SessionController.consumeEvents`/`MessageContentParser.parse` to hot fixed stacks, a supersedable-update burst above 20 nonterminal installs/s, non-idle settled CPU, or monotonic post-terminal RSS/footprint growth as a regression requiring investigation.

## Invalidated captures

Only `contract-1.1h` and `fixed-ax-1.0b` contribute measurements above.

| Capture | Why it is excluded |
| --- | --- |
| Fixture 1.0.0, including uitest-finalaccepted-pid-99126 | Each update omitted assistantMessageEvent.partial and used invalid empty usage, materially under-shaping decode/allocation work. |
| Corrected-workload PID 62358 | Superseded. Its harness/provenance was not the single preserved, exact f30e384 controller required for this baseline. |
| contract-1.1c | Disposable XCUITest source did not compile; xcodebuild ended TEST FAILED. |
| contract-1.1d and contract-1.1e | xcodebuild ended BUILD INTERRUPTED and neither produced a valid multi-row metrics capture. |
| contract-1.1f, PID 21588 | XCUITest passed, but generated C printed literal backslash-n, so the CSV had one physical line. |
| contract-1.1g, PID 26222 | UI, cadence, trace, identity, and cleanup passed, but the controller exited nonzero on an inherited, non-requirement n >= 35 gate. It is preserved as failed evidence, not accepted. |
| fixed-1.0a | Fixed XCUITest automation conflicted with other system-wide test sessions before a valid workload capture; no measurements are accepted. |
| fixed-ax-1.0a | External AX capture rejected ambiguous window proof before sending the workload; cleanup succeeded and no measurements are accepted. |
| Any other local prefix | Diagnostic only; not accepted evidence. |

## Environment and workload

| Field | Accepted value |
| --- | --- |
| Branch / profiled production source | codex/performance-runoff / f30e38403ec06c00ae335bb4d539502d7c641f39 |
| Fixed branch / profiled production source | codex/performance-runoff-final / f9f22ae7e8248c96face8ff47c6974ebac595638 |
| OS | macOS 26.5.2 (25F84) |
| Machine | MacBook Pro Mac17,8; Apple M5 Pro, 18 cores; 48 GB |
| Disposable Release bundle | /private/tmp/tenx-transcript-uitest-derived-contract-1-1h/Build/Products/Release/10x.app |
| Profile HOME / project | /private/tmp/tenx-transcript-profile-home-contract-1-1h / /private/tmp/tenx-transcript-profile-project-contract-1-1h |
| Unique bundle / app PID | com.tannerpham.tenx.transcriptbaseline / 27955 |
| Exact owned fake child | PID 28400 |
| Wrapper version | 10x-transcript-burst 1.1.0 |
| Result bundle | /private/tmp/tenx-transcript-uitest-result-contract-1-1h.xcresult |
| Fixed disposable Release bundle | /private/tmp/tenx-transcript-ax-derived-fixed-ax-1-0b/Build/Products/Release/10x.app |
| Fixed profile HOME / project | /private/tmp/tenx-transcript-profile-home-fixed-ax-1-0b / /private/tmp/tenx-transcript-profile-project-fixed-ax-1-0b |
| Fixed unique bundle / app PID | com.tannerpham.tenx.transcriptfixed / 26762 |
| Fixed exact owned fake child | PID 27315 |

After prompt acknowledgement, the fixture emits agent_start, message_start for burst-message, 1,000 complete growing message_update snapshots at 2 ms cadence, an identical message_end, and terminal agent_end with isTerminal true. Each update serializes the same full snapshot in message and assistantMessageEvent.partial. The nested event is text_delta at content index 0 with delta x. Both snapshots include all required zero-valued usage and cost fields.

There is no production OmpInstallation.version UI consumer. Per Tanner's approved amendment, provenance is the exact wrapper CLI version plus exact recursively owned child executable/argv. No product UI was added for profiling.

## TDD evidence

The original fixture-mode RED at base 46aa985 produced zero updates and no message_end:

~~~text
managerPreservesThousandGrowingMessageSnapshots()
updates.count -> 0, expected 1,000
~~~

Artifact: /private/tmp/tenx-performance-recordings/baseline-transcript/original-red-base-46aa985.log

The stricter contract-shape test was then made RED before the fixture correction:

~~~text
Expectation failed: (frames.malformedUpdates -> 1000) == 0
~~~

Artifact: /private/tmp/tenx-performance-recordings/baseline-transcript/contract-red-1.1.0.log

At f30e384:

~~~text
swift test --package-path OmpKit --filter managerPreservesThousandGrowingMessageSnapshots
# 1 test passed after 2.631 seconds

swift test --package-path OmpKit
# 126 tests passed after 2.627 seconds; 2 pre-existing real-OMP skips
~~~

Artifacts: contract-green-1.1.0-final.log and ompkit-full-green-1.1.0.log under /private/tmp/tenx-performance-recordings/baseline-transcript.

## Real UI capture

The disposable Release XCUITest:

1. launched the unique bundle with isolated HOME and the exact fixture wrapper first on PATH;
2. waited for the visible Session prompt;
3. clicked Choose project and selected the isolated project through the real Open Panel;
4. typed burst and required enabled Start session;
5. wrote READY and waited while the controller established the pre-roll;
6. clicked Start session exactly once;
7. observed Composer mode, Steer appear and disappear while Send message remained;
8. attached a terminal-idle screenshot and terminated its own app.

Fresh XCResult summary:

~~~text
result: Passed
totalTestCount: 1
passedTests: 1
failedTests: 0
skippedTests: 0
test case duration: 46.807 seconds
~~~

The exported 4112 x 2658 PNG is:

/private/tmp/tenx-transcript-uitest-attachments-contract-1-1h/ECBD7585-909C-4055-8EF3-BC91A4E37E64.png

SHA-256: 72fed1f60a60003580c87f6543be14446bf77069b80fbb5bdf53880b962893d2

## Native sampler preflight and cadence

Before starting xcodebuild, the accepted controller generated and compiled its sampler, then asserted:

- self-check output was exactly one physical line;
- the one-sample format probe was exactly two physical lines (header plus row);
- neither file contained a literal backslash-n sequence;
- the full metrics file contained multiple physical rows;
- every measured interval after the first row was within 0.95–1.05 seconds.

Accepted preflight:

~~~text
self-check lines=1
format-probe lines=2
timebase_numer=125 timebase_denom=3 conversion_ns=125000000
~~~

Accepted metrics validation:

~~~text
data rows=30
minimum delta=0.995000 seconds
maximum delta=1.005006 seconds
out-of-range deltas=0
~~~

The sampler reads RSS with PROC_PIDTASKINFO, physical footprint with RUSAGE_INFO_V4, converts cumulative CPU ticks using mach_timebase_info, and schedules absolute mach_wait_until deadlines.

## Accepted timing

Times are 2026-08-25 PDT; sampler markers are stored in UTC.

| Event | Time |
| --- | --- |
| First sampler row | 14:31:07.089 |
| Time Profiler start | 14:31:08.453 |
| Send marker | 14:31:19 |
| Streaming appeared | 14:31:20 |
| Terminal marker | 14:31:26 |
| Time Profiler end | 14:31:35.696 |
| Last sampler row | 14:31:36.090 |

Collector coverage recorded below. Collector timestamps have subsecond
precision, but the UI Send and terminal markers are whole-second values:

~~~text
trace_pre_seconds=10.547
trace_post_seconds=9.696
sampler_pre_seconds=11.911
sampler_post_seconds=10.090
~~~

This exceeds Task 1's required 5-second pre-Send and 5-second post-terminal
windows. The recovery controller deliberately enforced a stricter 8-second
post-terminal gate for both collectors.

## Trace analysis

The accepted xctrace TOC and time-profile table are:

- /private/tmp/tenx-performance-recordings/baseline-transcript/contract-1.1h-pid-27955-trace-toc.xml
- /private/tmp/tenx-performance-recordings/baseline-transcript/contract-1.1h-pid-27955-time-profile.xml

The embedded Perl analyzer resolves tagged-backtrace references to backtraces,
then frame references, and resolves sample-time/thread references. It counts
Main Thread samples within the whole-second Send and terminal marker bounds and
counts each named stack group at most once per sampled row. The 2.358 s bounded
value is therefore approximate; the 2.612 s full-trace total is exact at the
export's 1 ms sample weights.

~~~text
main_thread_id=2
full_trace_ms=2612
send_through_terminal_ms=2358
AccessibilityCore.textResolvedToAttributedText=117
ViewGraphRootValueUpdater.render=413
SessionController.consumeEvents=13
ViewGraph.updateOutputs=148
MessageContentParser.parse=18
TranscriptReducer.consume=3
~~~

## Provenance and cleanup

The accepted provenance file records all three SHA-256 values:

| Input | SHA-256 |
| --- | --- |
| Entire accepted controller | 6e499fdb83b6bf205be4c3f4ecc7e20fa2c93700ce1ef42e1f538edd29b687d7 |
| scripts/performance/omp | b13e54622b224ee84ea798db080487cb726afe3936956151e4bb9473310a931e |
| fake_server.py | 8f710b1e16c0607dc8124b1d8af9cb241d364468b7df44ee34c98565a270b25b |

Exact owned child:

~~~text
28400 27955 /Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python /private/tmp/tenx-transcript-uitest-worktree-contract-1-1h/OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py transcript-burst --mode rpc --no-title
~~~

The controller persisted app PID, bundle ID, child PID, and exact child command before cleanup. A live survivor could be signalled only after bundle or exact-command identity validation. The accepted cleanup log is:

~~~text
unique_bundle_exited=true
owned_cleanup=app_and_child_exited
~~~

Final checks found the unique bundle absent and the temporary worktree removed. PID 65083 was absent at the pre-capture and final inspections. The exact script below explicitly rejects 65083 at every app, child, collector, and xcodebuild signal path; the captured owned PIDs were 27955 and 28400, so no signal targeted 65083.

## Accepted fixed capture

The fixed `fixed-ax-1.0b` controller built commit `f9f22ae7e8248c96face8ff47c6974ebac595638` in a disposable worktree with a unique bundle identifier, launched it visibly under an isolated HOME, and used a trusted external macOS Accessibility driver to operate the real project rail, Session prompt, Start session button, Steer state, and terminal Send message state. The controller recorded fractional-second markers and selected descendant PIDs by their trimmed first field.

The first fixed XCUITest attempt was invalidated because unrelated system-wide test automation prevented a valid capture. The accepted external driver avoided test-host injection while still exercising the real app controls. `CGWindowList` independently proved a visible on-screen app window before the workload. Terminal screenshot capture was attempted but macOS denied image creation because the shell lacks Screen Recording permission; the AX terminal-state assertion and visible-window proof remain valid.

### Fixed timing and cadence

| Event | Time (2026-08-25 PDT) |
| --- | --- |
| First sampler row | 19:09:51.891 |
| Time Profiler start | 19:09:54.455 |
| Send marker | 19:10:03.994 |
| Streaming appeared | 19:10:04.235 |
| Terminal marker | 19:10:06.845 |
| Time Profiler end | 19:10:16.091 |
| Last sampler row | 19:10:23.894 |

~~~text
rows=33 cadence_ok=1
trace_pre_seconds=9.539 trace_post_seconds=9.246
sampler_pre_seconds=12.103 sampler_post_seconds=17.049
~~~

The native sampler's 33 rows all remained within 0.95–1.05 seconds after the first sample. The trace and sampler both exceed the required five-second pre-Send and eight-second post-terminal coverage.

The app emitted one `TranscriptSnapshotInstalled` point of interest for each MainActor installation. The reference-resolving analyzer found 52 installs for the 1,000-update raw burst: 19 in `02:10:04Z`, 19 in `02:10:05Z`, and 14 in the partial terminal second. The maximum nonterminal count was 19 per wall-clock second, satisfying this burst's 20/s target. Revision 3 was superseded before installation; revisions remain strictly increasing through final revision 53. Unit tests separately prove immediate/lossless boundaries and controls.

### Fixed trace analysis

The fixed trace covers the exact fractional Send-through-terminal interval. The same reference-resolving stack analysis used for baseline reports:

~~~text
main_thread_id=2 full_trace_ms=345 send_through_terminal_ms=340
AccessibilityCore.textResolvedToAttributedText=49
ViewGraphRootValueUpdater.render=59
SessionController.consumeEvents=0
TranscriptEventProcessor=16
ViewGraph.updateOutputs=19
MessageContentParser.parse=0
AssistantMessageContentView=0
AttributedString._parseMarkdown=4
TranscriptReducer.consume=9
~~~

`SessionController.consumeEvents` and `MessageContentParser.parse` disappeared from sampled fixed stacks. The remaining processor/reducer rows are expected off-main pipeline work, and the four Markdown rows occur only when installed assistant text actually changes.

### Fixed provenance and cleanup

| Input | SHA-256 |
| --- | --- |
| Entire accepted fixed controller | aad158cf79e053c55d585b220804e3aac38ed27b48788e3952e2ac0daf1e9689 |
| External AX driver source | 294f33a81eb54b878d2b70afd99210d438e47cef52b97a550f536fe84a05501b |
| Snapshot-signpost analyzer | b4248bb2ce99327d06b66fe8327e18b1cc090f5c2dd3fa2a4e76fc070922ff05 |
| `scripts/performance/omp` | b13e54622b224ee84ea798db080487cb726afe3936956151e4bb9473310a931e |
| `fake_server.py` | 599c436e739881ef87967a42df9efd2a36b8e32e1e8b979f511349de144eafab |
| Exact profiled Release executable | 403e8ff0ced437e9eb75c14125a5a929ccebfa6bae955f926c50cfb1b91bc083 |

Exact owned child:

~~~text
27315 26762 /Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python /private/tmp/tenx-transcript-ax-worktree-fixed-ax-1-0b/OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py transcript-burst --mode rpc --no-title
~~~

The controller rejected PID 65083 at every app, child, driver, and collector signal path. It persisted app PID, bundle ID, child PID, exact child command, visible window ID, source hashes, and executable hash. Accepted cleanup output is:

~~~text
unique_bundle_exited=true
owned_cleanup=app_and_child_exited
~~~

Final inspection found the unique fixed bundle absent and the disposable worktree removed.

### Fixed build and tests

At the exact fixed source commit:

- app suite: 152/152 passed;
- OmpKit: the 126-test run passed, with two declared environment-dependent real-OMP tests skipped;
- universal arm64/x86_64 Release build: succeeded;
- final default-bundle Release executable SHA-256: `1c106722e77817e2086449ef02f6596efb4a919d1fd0a6b1ee9e061380756582`.

Durable logs are under `/private/tmp/tenx-performance-recordings/fixed-transcript/` as `final-app-tests-f9.log`, `final-ompkit-tests-f9.log`, and `final-release-build-f9.log`. The fresh app result bundle is `/private/tmp/tenx-performance-final-app-tests-f9/Logs/Test/Test-10x-2026.08.25_19-13-26--0700.xcresult`.

## Exact accepted baseline controller

Path:

/private/tmp/tenx-performance-recordings/baseline-transcript/contract-1.1h-capture.zsh

SHA-256:

~~~text
6e499fdb83b6bf205be4c3f4ecc7e20fa2c93700ce1ef42e1f538edd29b687d7
~~~

The following is the entire preserved script, byte-for-byte apart from this Markdown fence:

~~~zsh
#!/bin/zsh
set -euo pipefail
FEATURE='/Users/tannerpham/CS Projects/.worktrees/10x-performance-profile'; COMMIT=f30e38403ec06c00ae335bb4d539502d7c641f39
PREFIX=contract-1.1h; ART=/private/tmp/tenx-performance-recordings/baseline-transcript
TEMP=/private/tmp/tenx-transcript-uitest-worktree-contract-1-1h; DERIVED=/private/tmp/tenx-transcript-uitest-derived-contract-1-1h
RESULT=/private/tmp/tenx-transcript-uitest-result-contract-1-1h.xcresult; PROFILE_HOME=/private/tmp/tenx-transcript-profile-home-contract-1-1h; PROFILE_PROJECT=/private/tmp/tenx-transcript-profile-project-contract-1-1h
READY=$ART/$PREFIX-ready; GO=$ART/$PREFIX-go; TIMING=$ART/$PREFIX-timing; SCRIPT_COPY=$ART/$PREFIX-capture.zsh; SCRIPT_SHA=$ART/$PREFIX-capture.sha256; PROVENANCE=$ART/$PREFIX-provenance.txt; CLEANUP_LOG=$ART/$PREFIX-cleanup.log
SELF_CHECK=$ART/$PREFIX-sampler-self-check.log; FORMAT_PROBE=$ART/$PREFIX-sampler-format-probe.csv
PROFILE_PID=''; CHILD_PID=''; CHILD_COMMAND=''; TRACE_PID=''; TOP_PID=''; SAMPLER_PID=''; XCODEBUILD_PID=''; OWNED_CLEANUP_VERIFIED=0; APP_BUNDLE=com.tannerpham.tenx.transcriptbaseline
stop_collectors(){
  [[ -z "$TRACE_PID" ]] || { [[ "$TRACE_PID" != 65083 ]] || return 90; kill -INT "$TRACE_PID" 2>/dev/null || true; wait "$TRACE_PID" || true; TRACE_PID=''; }
  [[ -z "$TOP_PID" ]] || { [[ "$TOP_PID" != 65083 ]] || return 90; kill "$TOP_PID" 2>/dev/null || true; wait "$TOP_PID" || true; TOP_PID=''; }
  [[ -z "$SAMPLER_PID" ]] || { [[ "$SAMPLER_PID" != 65083 ]] || return 90; kill "$SAMPLER_PID" 2>/dev/null || true; wait "$SAMPLER_PID" || true; SAMPLER_PID=''; }
}
app_identity_live(){ [[ -n "$PROFILE_PID" && "$PROFILE_PID" != 65083 ]] || return 1; swift - "$PROFILE_PID" <<'SWIFT'
import AppKit
let pid=Int32(CommandLine.arguments[1])!
exit(NSRunningApplication.runningApplications(withBundleIdentifier:"com.tannerpham.tenx.transcriptbaseline").contains{$0.processIdentifier==pid} ? 0 : 1)
SWIFT
}
child_identity_live(){ [[ -n "$CHILD_PID" && "$CHILD_PID" != 65083 ]] && [[ "$(ps -p "$CHILD_PID" -o command= 2>/dev/null | sed 's/^ *//')" == "$CHILD_COMMAND" ]]; }
wait_gone(){ local pid=$1; for _ in $(seq 1 100); do kill -0 "$pid" 2>/dev/null || return 0; sleep .1; done; return 1; }
discover_profile(){
  [[ -n "$PROFILE_PID" ]] && return 0
  PROFILE_PID=$(swift - <<'SWIFT'
import AppKit
let apps=NSRunningApplication.runningApplications(withBundleIdentifier:"com.tannerpham.tenx.transcriptbaseline")
guard apps.count == 1 else { exit(apps.isEmpty ? 1 : 2) }
print(apps[0].processIdentifier)
SWIFT
  ) || { code=$?; (( code == 1 )) && return 80; return 81; }
  [[ "$PROFILE_PID" != 65083 ]]
}
verify_or_cleanup_owned(){
  discover_profile || { code=$?; (( code == 80 )) && return 0; return "$code"; }
  [[ "$PROFILE_PID" != 65083 ]] || return 72
  if [[ -z "$CHILD_PID" ]]; then
    line=$(desc 2>/dev/null | grep 'fake_server.py transcript-burst' | head -1 || true)
    if [[ -n "$line" ]]; then
      CHILD_PID=${line%% *}
      CHILD_COMMAND=$(ps -p "$CHILD_PID" -o command= | sed 's/^ *//')
      [[ -n "$CHILD_COMMAND" && "$CHILD_PID" != 65083 ]] || return 73
    fi
  fi
  if kill -0 "$PROFILE_PID" 2>/dev/null; then app_identity_live || return 72; kill -TERM "$PROFILE_PID"; fi
  if [[ -n "$CHILD_PID" ]]; then
    [[ "$CHILD_PID" != 65083 ]] || return 73
    if kill -0 "$CHILD_PID" 2>/dev/null; then child_identity_live || return 74; kill -TERM "$CHILD_PID"; fi
  fi
  wait_gone "$PROFILE_PID" || return 75
  [[ -z "$CHILD_PID" ]] || wait_gone "$CHILD_PID" || return 76
  swift - <<'SWIFT'
import AppKit
precondition(NSRunningApplication.runningApplications(withBundleIdentifier:"com.tannerpham.tenx.transcriptbaseline").isEmpty)
print("unique_bundle_exited=true")
SWIFT
  print 'owned_cleanup=app_and_child_exited'
}
finalize(){
  local result_code=$? cleanup_code=0 step_code=0
  trap - EXIT INT TERM
  set +e
  stop_collectors || cleanup_code=$?
  if (( OWNED_CLEANUP_VERIFIED == 0 )); then
    verify_or_cleanup_owned >>"$CLEANUP_LOG" 2>&1 || { step_code=$?; (( cleanup_code == 0 )) && cleanup_code=$step_code; }
  fi
  if [[ -n "$XCODEBUILD_PID" ]]; then
    if [[ "$XCODEBUILD_PID" == 65083 ]]; then
      (( cleanup_code == 0 )) && cleanup_code=91
    else
      kill "$XCODEBUILD_PID" 2>/dev/null
      wait "$XCODEBUILD_PID"
    fi
  fi
  [[ ! -e "$TEMP" ]] || { git -C "$FEATURE" worktree remove --force "$TEMP"; git -C "$FEATURE" worktree prune; }
  (( result_code == 0 && cleanup_code != 0 )) && exit "$cleanup_code"
  exit "$result_code"
}
trap finalize EXIT INT TERM
mkdir -p "$ART" "$PROFILE_HOME" "$PROFILE_PROJECT"
for p in "$TEMP" "$DERIVED" "$RESULT" "$READY" "$GO" "$TIMING" "$SCRIPT_COPY" "$SCRIPT_SHA" "$PROVENANCE" "$CLEANUP_LOG" "$SELF_CHECK" "$FORMAT_PROBE"; do test ! -e "$p" || { print -u2 "stale path: $p"; exit 10; }; done
swift - <<'SWIFT'
import AppKit
precondition(NSRunningApplication.runningApplications(withBundleIdentifier:"com.tannerpham.tenx.transcriptbaseline").isEmpty)
SWIFT
cp "$0" "$SCRIPT_COPY"; shasum -a 256 "$SCRIPT_COPY" >"$SCRIPT_SHA"
git -C "$FEATURE" worktree add --detach "$TEMP" "$COMMIT"
{ print "temp_head=$(git -C "$TEMP" rev-parse HEAD)"; print "wrapper=$TEMP/scripts/performance/omp"; "$TEMP/scripts/performance/omp" --version; shasum -a 256 "$SCRIPT_COPY" "$TEMP/scripts/performance/omp" "$TEMP/OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py"; } >"$PROVENANCE"
grep -qx 'temp_head=f30e38403ec06c00ae335bb4d539502d7c641f39' "$PROVENANCE"
grep -qx '10x-transcript-burst 1.1.0' "$PROVENANCE"
grep -q "$(cut -d' ' -f1 "$SCRIPT_SHA")" "$PROVENANCE"
cd "$TEMP"; mkdir -p UITests
apply_patch <<'PATCH'
*** Begin Patch
*** Update File: scripts/generate_xcodeproj.rb
@@
 tests = project.new_target(:unit_test_bundle, "TenXAppTests", :osx, "15.0")
+ui_tests = project.new_target(:ui_test_bundle, "TenXAppUITests", :osx, "15.0")
 tests.add_dependency(app)
+ui_tests.add_dependency(app)
@@
 test_group = project.main_group.new_group("Tests")
+ui_test_group = project.main_group.new_group("UITests")
@@
 Dir.glob(File.join(root, "Tests/**/*.swift")).sort.each do |path|
@@
 end
+Dir.glob(File.join(root, "UITests/**/*.swift")).sort.each do |path|
+  reference = ui_test_group.new_file(path.delete_prefix(root + "/"))
+  ui_tests.source_build_phase.add_file_reference(reference)
+end
@@
-    "PRODUCT_BUNDLE_IDENTIFIER" => "com.tannerpham.tenx",
+    "PRODUCT_BUNDLE_IDENTIFIER" => "com.tannerpham.tenx.transcriptbaseline",
@@
 end
+ui_tests.build_configurations.each do |configuration|
+  configuration.build_settings.merge!({"PRODUCT_BUNDLE_IDENTIFIER"=>"com.tannerpham.tenx.transcriptbaseline.uitests","PRODUCT_MODULE_NAME"=>"TenXAppUITests","GENERATE_INFOPLIST_FILE"=>"YES","SWIFT_VERSION"=>"6.0","SWIFT_STRICT_CONCURRENCY"=>"complete","MACOSX_DEPLOYMENT_TARGET"=>"15.0","TEST_TARGET_NAME"=>"10x","ENABLE_APP_SANDBOX"=>"NO","CODE_SIGN_ENTITLEMENTS"=>"UITests/TranscriptBurstUITests.entitlements"})
+end
@@
 scheme.add_build_target(app)
-scheme.add_test_target(tests)
+scheme.add_test_target(ui_tests)
*** End Patch
PATCH
apply_patch <<'PATCH'
*** Begin Patch
*** Add File: UITests/TranscriptBurstUITests.entitlements
+<?xml version="1.0" encoding="UTF-8"?>
+<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
+<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><false/><key>com.apple.security.temporary-exception.files.absolute-path.read-write</key><array><string>/private/tmp/tenx-performance-recordings/baseline-transcript</string></array></dict></plist>
*** Add File: UITests/TranscriptBurstUITests.swift
+import XCTest
+final class TranscriptBurstUITests:XCTestCase {
+ let base="/private/tmp/tenx-performance-recordings/baseline-transcript/contract-1.1h"
+ func testTranscriptBurstThroughRealControls() throws {
+  let ready=URL(fileURLWithPath:base+"-ready"),go=URL(fileURLWithPath:base+"-go"),timing=URL(fileURLWithPath:base+"-timing")
+  let app=XCUIApplication(bundleIdentifier:"com.tannerpham.tenx.transcriptbaseline")
+  app.launchEnvironment=["CFFIXED_USER_HOME":"/private/tmp/tenx-transcript-profile-home-contract-1-1h","PATH":"/private/tmp/tenx-transcript-uitest-worktree-contract-1-1h/scripts/performance:/usr/bin:/bin:/usr/sbin:/sbin"];app.launch()
+  let prompt=app.textViews["Session prompt"];XCTAssertTrue(prompt.waitForExistence(timeout:20));app.buttons["Choose project"].tap();app.typeKey("g",modifierFlags:[.command,.shift]);app.typeText("/private/tmp/tenx-transcript-profile-project-contract-1-1h");app.typeKey(.return,modifierFlags:[])
+  let choose=app.dialogs.matching(identifier:"open-panel").firstMatch.buttons["Choose Project"];XCTAssertTrue(choose.waitForExistence(timeout:15));choose.tap();prompt.tap();prompt.typeText("burst")
+  let start=app.buttons["Start session"];XCTAssertTrue(start.waitForExistence(timeout:15));XCTAssertTrue(start.isEnabled);try "ready\n".write(to:ready,atomically:true,encoding:.utf8)
+  let deadline=Date().addingTimeInterval(180);while Date()<deadline && !FileManager.default.fileExists(atPath:go.path){RunLoop.current.run(until:Date().addingTimeInterval(0.1))};XCTAssertTrue(FileManager.default.fileExists(atPath:go.path))
+  func mark(_ v:String)throws{let old=(try?String(contentsOf:timing)) ?? "";try(old+v+"="+ISO8601DateFormatter().string(from:Date())+"\n").write(to:timing,atomically:true,encoding:.utf8)}
+  try mark("send");start.tap();let steer=app.buttons["Composer mode, Steer"];XCTAssertTrue(steer.waitForExistence(timeout:45));try mark("streaming_started");let send=app.buttons["Send message"];let end=Date().addingTimeInterval(60);while Date()<end && (steer.exists || !send.exists){RunLoop.current.run(until:Date().addingTimeInterval(0.1))};XCTAssertFalse(steer.exists);XCTAssertTrue(send.exists);try mark("streaming_ended");Thread.sleep(forTimeInterval:10);let a=XCTAttachment(screenshot:app.screenshot());a.name="transcript-burst-1.1h-terminal-idle";a.lifetime = .keepAlways;add(a);app.terminate()
+ }
+}
*** End Patch
PATCH
apply_patch <<'PATCH'
*** Begin Patch
*** Add File: /private/tmp/tenx-proc-sampler-contract-1-1h.c
+#include <libproc.h>
+#include <mach/mach_time.h>
+#include <math.h>
+#include <stdio.h>
+#include <stdlib.h>
+#include <string.h>
+#include <sys/resource.h>
+#include <time.h>
+static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
+int main(int argc,char**argv){mach_timebase_info_data_t b={0};if(mach_timebase_info(&b)!=KERN_SUCCESS||!b.denom)return 65;if(argc==2&&!strcmp(argv[1],"--self-check")){uint64_t t=(uint64_t)b.denom*1000000;double n=(double)t*b.numer/b.denom;if(fabs(n-(double)b.numer*1000000)>.001)return 66;printf("timebase_numer=%u timebase_denom=%u conversion_ns=%.0f\n",b.numer,b.denom,n);return 0;}if(argc!=3)return 64;pid_t p=strtol(argv[1],0,10);int c=strtol(argv[2],0,10);uint64_t old=0,d=mach_absolute_time(),i=1000000000ULL*b.denom/b.numer;double s=now(),last=0;puts("timestamp_utc,pid,cpu_percent,rss_bytes,physical_footprint_bytes,monotonic_elapsed_seconds,monotonic_delta_seconds");for(int x=0;x<c;x++){struct proc_taskinfo q={0};struct rusage_info_v4 u={0};if(proc_pidinfo(p,PROC_PIDTASKINFO,0,&q,sizeof(q))!=sizeof(q)||proc_pid_rusage(p,RUSAGE_INFO_V4,(rusage_info_t*)&u))break;double n=now(),delta=last? n-last:0;if(last&&(delta<.95||delta>1.05))return 67;uint64_t cpu=q.pti_total_user+q.pti_total_system;struct timespec r={0};struct tm g={0};clock_gettime(CLOCK_REALTIME,&r);gmtime_r(&r.tv_sec,&g);char z[32]={0};strftime(z,sizeof(z),"%Y-%m-%dT%H:%M:%S",&g);printf("%s.%03ldZ,%d,%.2f,%llu,%llu,%.6f,%.6f\n",z,r.tv_nsec/1000000,p,last?100*((double)(cpu-old)*b.numer/b.denom/1e9)/delta:0,q.pti_resident_size,u.ri_phys_footprint,n-s,delta);fflush(stdout);old=cpu;last=n;d+=i;if(mach_wait_until(d)!=KERN_SUCCESS)return 68;}return 0;}
*** End Patch
PATCH
apply_patch <<'PATCH'
*** Begin Patch
*** Add File: /private/tmp/tenx-contract-1-1h-analyze-interval.pl
+use strict;
+use warnings;
+local $/;
+my ($xml_path, $lower, $upper) = @ARGV;
+open my $fh, '<', $xml_path or die $!;
+my $xml = <$fh>;
+my (%frame, %backtrace, %tagged, %time);
+while ($xml =~ m{<frame id="(\d+)" name="([^"]+)"}g) { $frame{$1}=$2 }
+while ($xml =~ m{<backtrace id="(\d+)"[^>]*>(.*?)</backtrace>}sg) { $backtrace{$1}=$2 }
+while ($xml =~ m{<tagged-backtrace id="(\d+)"[^>]*>(.*?)</tagged-backtrace>}sg) { $tagged{$1}=$2 }
+while ($xml =~ m{<sample-time id="(\d+)"[^>]*>(\d+)</sample-time>}g) { $time{$1}=$2 }
+$xml =~ /<thread id="(\d+)" fmt="Main Thread / or die "Main Thread missing\n";
+my $main=$1;
+my @groups=("AccessibilityCore.textResolvedToAttributedText","ViewGraphRootValueUpdater.render","SessionController.consumeEvents","ViewGraph.updateOutputs","MessageContentParser.parse","TranscriptReducer.consume");
+sub stack_for { my ($tag)=@_; my @backtrace_ids=($tagged{$tag}//"") =~ /<backtrace (?:id|ref)="(\d+)"/g; return join "\n", map { $frame{$_}//"" } map { ($backtrace{$_}//"") =~ /<frame (?:id|ref)="(\d+)"/g } @backtrace_ids; }
+my ($full,$interval)=(0,0); my %count;
+while ($xml =~ m{<row>(.*?)</row>}sg) { my $row=$1; my ($sid)=$row =~ /<sample-time (?:id|ref)="(\d+)"/; my ($tid)=$row =~ /<thread (?:id|ref)="(\d+)"/; if (defined $sid && defined $tid && $tid==$main) { $full++; my $sample=$time{$sid}; $interval++ if defined $sample && $sample >= $lower && $sample <= $upper; } my ($tag)=$row =~ /<tagged-backtrace (?:id|ref)="(\d+)"/; next unless defined $tag; my $stack=stack_for($tag); for my $group (@groups) { $count{$group}++ if index($stack,$group)>=0; } }
+print "main_thread_id=$main full_trace_ms=$full send_through_terminal_ms=$interval\n";
+print join(" ",map{"$_=".($count{$_}//0)}@groups),"\n";
*** End Patch
PATCH
ruby scripts/generate_xcodeproj.rb
clang -Wall -Wextra -Werror -O2 /private/tmp/tenx-proc-sampler-contract-1-1h.c -o /private/tmp/tenx-proc-sampler-contract-1-1h
/private/tmp/tenx-proc-sampler-contract-1-1h --self-check >"$SELF_CHECK"
[[ "$(wc -l <"$SELF_CHECK" | tr -d ' ')" == 1 ]]
grep -Eq '^timebase_numer=[0-9]+ timebase_denom=[0-9]+ conversion_ns=[0-9]+$' "$SELF_CHECK"
! grep -Fq '\n' "$SELF_CHECK"
/private/tmp/tenx-proc-sampler-contract-1-1h "$$" 1 >"$FORMAT_PROBE"
[[ "$(wc -l <"$FORMAT_PROBE" | tr -d ' ')" == 2 ]]
grep -qx 'timestamp_utc,pid,cpu_percent,rss_bytes,physical_footprint_bytes,monotonic_elapsed_seconds,monotonic_delta_seconds' "$FORMAT_PROBE"
! grep -Fq '\n' "$FORMAT_PROBE"
xcodebuild test -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath "$DERIVED" -resultBundlePath "$RESULT" -only-testing:TenXAppUITests/TranscriptBurstUITests/testTranscriptBurstThroughRealControls >"$ART/$PREFIX-xcodebuild.log" 2>&1 & XCODEBUILD_PID=$!
for _ in $(seq 1 1800); do
  test -f "$READY" && break
  kill -0 "$XCODEBUILD_PID" 2>/dev/null || { wait "$XCODEBUILD_PID"; exit 26; }
  sleep .1
done
test -f "$READY"
PROFILE_PID=$(swift - <<'SWIFT'
import AppKit
let a=NSRunningApplication.runningApplications(withBundleIdentifier:"com.tannerpham.tenx.transcriptbaseline");precondition(a.count==1);print(a[0].processIdentifier)
SWIFT
)
[[ "$PROFILE_PID" != 65083 ]]||exit 20;RUN=$ART/$PREFIX-pid-$PROFILE_PID;TRACE=$RUN.timeprofile.trace;METRICS=$RUN-metrics.csv;TOP=$RUN-top.txt;TREE=$RUN-owned-process-tree.txt;CURRENT=$RUN-current-process-tree.txt;TOC=$RUN-trace-toc.xml;XML=$RUN-time-profile.xml;ANALYSIS=$RUN-analysis.log;IDENTITY=$RUN-cleanup-identity.txt
for p in "$TRACE" "$METRICS" "$TOP" "$TREE" "$CURRENT" "$TOC" "$XML" "$ANALYSIS" "$IDENTITY";do test ! -e "$p"||exit 21;done
desc(){ ps -axo pid=,ppid=,command=|awk -v root="$PROFILE_PID" '{p[$1]=$2;l[$1]=$0}END{for(x in p){c=x;for(d=0;d<16;d++){if(p[c]==root){print l[x];break}if(!(c in p)||c==root)break;c=p[c]}}}'; }
xctrace record --template 'Time Profiler' --attach "$PROFILE_PID" --output "$TRACE" >"$RUN-xctrace.log" 2>&1 & TRACE_PID=$!
top -l 180 -s 1 -pid "$PROFILE_PID" >"$TOP" 2>&1 & TOP_PID=$!
/private/tmp/tenx-proc-sampler-contract-1-1h "$PROFILE_PID" 180 >"$METRICS" 2>"$RUN-sampler.log" & SAMPLER_PID=$!
sleep 12;touch "$GO";terminal=0
for _ in $(seq 1 1800); do
  desc >"$CURRENT"
  if [[ -z "$CHILD_PID" ]]; then
    line=$(grep 'fake_server.py transcript-burst' "$CURRENT" | head -1 || true)
    if [[ -n "$line" ]]; then
      CHILD_PID=${line%% *}; [[ "$CHILD_PID" != 65083 ]] || exit 22
      CHILD_COMMAND=$(ps -p "$CHILD_PID" -o command= | sed 's/^ *//'); [[ -n "$CHILD_COMMAND" ]] || exit 23
      cp "$CURRENT" "$TREE"
      { print "profile_pid=$PROFILE_PID"; print "bundle_id=$APP_BUNDLE"; print "child_pid=$CHILD_PID"; print "child_command=$CHILD_COMMAND"; } >"$IDENTITY"
    fi
  fi
  if grep -q '^streaming_ended=' "$TIMING"; then terminal=1; sleep 9; break; fi
  sleep .1
done
[[ -n "$CHILD_PID" && "$terminal" = 1 ]]||exit 24
stop_collectors
wait "$XCODEBUILD_PID";XCODEBUILD_PID=''
xctrace export --input "$TRACE" --toc --output "$TOC";xctrace export --input "$TRACE" --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' --output "$XML"
trace_start=$(sed -n 's:.*<start-date>\(.*\)</start-date>.*:\1:p' "$TOC"|head -1); trace_end=$(sed -n 's:.*<end-date>\(.*\)</end-date>.*:\1:p' "$TOC"|head -1); send_time=$(sed -n 's/^send=//p' "$TIMING"); terminal_time=$(sed -n 's/^streaming_ended=//p' "$TIMING"); sampler_first=$(awk -F, 'NR==2{print $1}' "$METRICS"); sampler_last=$(awk -F, 'END{print $1}' "$METRICS")
to_ns(){ ruby -r time -e 'puts((Time.iso8601(ARGV.fetch(0)).to_r*1_000_000_000).to_i)' "$1"; }
trace_start_ns=$(to_ns "$trace_start"); trace_end_ns=$(to_ns "$trace_end"); send_ns=$(to_ns "$send_time"); terminal_ns=$(to_ns "$terminal_time"); sampler_first_ns=$(to_ns "$sampler_first"); sampler_last_ns=$(to_ns "$sampler_last")
trace_pre_ns=$(( send_ns - trace_start_ns )); trace_post_ns=$(( trace_end_ns - terminal_ns )); sampler_pre_ns=$(( send_ns - sampler_first_ns )); sampler_post_ns=$(( sampler_last_ns - terminal_ns ))
(( trace_pre_ns >= 5000000000 && trace_post_ns >= 8000000000 && sampler_pre_ns >= 5000000000 && sampler_post_ns >= 8000000000 )) || exit 25
lower_ns=$trace_pre_ns; upper_ns=$(( terminal_ns - trace_start_ns ))
awk -F, 'NR>1{n++;if(NR>2&&($7<.95||$7>1.05))bad=1}END{print"rows="n,"cadence_ok="(!bad);exit(n<2||bad)}' "$METRICS">"$ANALYSIS"
ruby -e 'puts "trace_pre_seconds=%.3f trace_post_seconds=%.3f sampler_pre_seconds=%.3f sampler_post_seconds=%.3f" % ARGV.map { |v| v.to_f / 1_000_000_000 }' "$trace_pre_ns" "$trace_post_ns" "$sampler_pre_ns" "$sampler_post_ns" >>"$ANALYSIS"
perl /private/tmp/tenx-contract-1-1h-analyze-interval.pl "$XML" "$lower_ns" "$upper_ns">>"$ANALYSIS"
grep -Fq "$TEMP/OmpKit/Tests/OmpKitTests/Fixtures/fake_server.py transcript-burst --mode rpc --no-title" "$TREE"
verify_or_cleanup_owned >"$CLEANUP_LOG" 2>&1
grep -qx 'unique_bundle_exited=true' "$CLEANUP_LOG"
grep -qx 'owned_cleanup=app_and_child_exited' "$CLEANUP_LOG"
OWNED_CLEANUP_VERIFIED=1
print "capture_complete profile_pid=$PROFILE_PID child_pid=$CHILD_PID"
~~~

## Validation commands

~~~sh
A=/private/tmp/tenx-performance-recordings/baseline-transcript
P=contract-1.1h
R="$A/$P-pid-27955"

shasum -a 256 -c "$A/$P-capture.sha256"
grep -qx 'temp_head=f30e38403ec06c00ae335bb4d539502d7c641f39' "$A/$P-provenance.txt"
grep -qx '10x-transcript-burst 1.1.0' "$A/$P-provenance.txt"
grep -Fq 'fake_server.py transcript-burst --mode rpc --no-title' "$R-owned-process-tree.txt"
grep -qx 'unique_bundle_exited=true' "$A/$P-cleanup.log"
grep -qx 'owned_cleanup=app_and_child_exited' "$A/$P-cleanup.log"
grep -q '\*\* TEST SUCCEEDED \*\*' "$A/$P-xcodebuild.log"

awk -F, '
  NR > 1 {
    rows++
    if (NR > 2 && ($7 < 0.95 || $7 > 1.05)) bad++
  }
  END {
    print "rows=" rows, "cadence_ok=" (bad == 0)
    exit(rows < 2 || bad)
  }
' "$R-metrics.csv"

cat "$R-analysis.log"

F=/private/tmp/tenx-performance-recordings/fixed-transcript
Q=fixed-ax-1.0b
S="$F/$Q-pid-26762"

shasum -a 256 -c "$F/$Q-capture.sha256"
grep -qx 'temp_head=f9f22ae7e8248c96face8ff47c6974ebac595638' "$F/$Q-provenance.txt"
grep -qx '10x-transcript-burst 1.1.0' "$F/$Q-provenance.txt"
grep -Fq 'fake_server.py transcript-burst --mode rpc --no-title' "$S-owned-process-tree.txt"
grep -qx 'unique_bundle_exited=true' "$F/$Q-cleanup.log"
grep -qx 'owned_cleanup=app_and_child_exited' "$F/$Q-cleanup.log"

awk -F, '
  NR > 1 {
    rows++
    if (NR > 2 && ($7 < 0.95 || $7 > 1.05)) bad++
  }
  END {
    print "rows=" rows, "cadence_ok=" (bad == 0)
    exit(rows < 2 || bad)
  }
' "$S-metrics.csv"

ruby "$F/$Q-signpost-analyzer.rb" \
  "$S-signposts.xml" \
  '2026-08-25T19:09:54.455-07:00' \
  '2026-08-26T02:10:06.845Z' \
  26762
cat "$S-analysis.log"
~~~

Observed output includes both capture checksums OK, baseline TEST SUCCEEDED, rows=30 and rows=33 with cadence_ok=1, all timing gates, 52 fixed snapshot events with a 19/s maximum nonterminal rate, and the reference-resolved analyses above.

## Local artifacts

All binary and temporary capture data is untracked under /private/tmp:

- contract-1.1h-pid-27955.timeprofile.trace
- contract-1.1h-pid-27955-metrics.csv
- contract-1.1h-pid-27955-top.txt
- contract-1.1h-pid-27955-owned-process-tree.txt
- contract-1.1h-pid-27955-cleanup-identity.txt
- contract-1.1h-pid-27955-trace-toc.xml
- contract-1.1h-pid-27955-time-profile.xml
- contract-1.1h-pid-27955-analysis.log
- contract-1.1h-provenance.txt
- contract-1.1h-cleanup.log
- contract-1.1h-xcodebuild.log
- /private/tmp/tenx-transcript-uitest-result-contract-1-1h.xcresult
- /private/tmp/tenx-transcript-uitest-attachments-contract-1-1h
- fixed-ax-1.0b-pid-26762.timeprofile.trace
- fixed-ax-1.0b-pid-26762-metrics.csv
- fixed-ax-1.0b-pid-26762-top.txt
- fixed-ax-1.0b-pid-26762-trace-toc.xml
- fixed-ax-1.0b-pid-26762-time-profile.xml
- fixed-ax-1.0b-pid-26762-signposts.xml
- fixed-ax-1.0b-pid-26762-analysis.log
- fixed-ax-1.0b-pid-26762-signpost-analysis.log
- fixed-ax-1.0b-pid-26762-ax-driver.log
- fixed-ax-1.0b-pid-26762-visible.txt
- fixed-ax-1.0b-provenance.txt
- fixed-ax-1.0b-cleanup.log
- fixed-ax-1.0b-capture.zsh
- fixed-ax-1.0b-signpost-analyzer.rb
