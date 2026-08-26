# Session Search Performance

**Date:** 2026-08-25
**Build:** Release, commit `703592c066456cc6ebc0e81fdbd24c92a175f536`
**Machine:** Mac17,8, Apple M5 Pro, 48 GiB RAM
**OS:** macOS 26.5.2 (25F84)

## Result

Warm search now dispatches once, completes its indexed query in 9.236 ms, performs no JSONL parsing, and returns to idle. The fixed 22-prefix run peaked at 9.13% app CPU and a 73.02 MiB physical footprint.

The recorded baseline corpus is no longer present byte-for-byte on disk. The fixed stress run therefore used a read-only, scale-equivalent disposable corpus with the same documented dimensions: 51 JSONL files and 21,700,054 bytes. It was assembled from the 46 current recursive session files plus five deterministic copies. This validates the acceptance thresholds at the original scale, but it is not represented as a strict content-identical A/B run.

## Cause and correction

The old query path reopened and decoded every supplied JSONL file after every query mutation. Cancellation happened only between parsed entries, so typing could overlap expensive decodes that had already started. The baseline sample attributes approximately 1.299 CPU-s to `SessionSearchService.search` and 1.128 CPU-s to `SessionFileParser.parse`.

The fixed path:

- stores searchable result metadata in a persistent SQLite FTS5 index;
- fingerprints each source by path, modification date, and size;
- parses only new or changed sessions, one file at a time;
- shares one lazy index service across modal lifetimes;
- waits 250 ms after the last query change and rejects stale results;
- cancels pending work when the modal disappears;
- emits query-free `SearchQueryStarted` and `SearchQueryFinished` points of interest.

## Baseline and fixed metrics

| Metric | Baseline | Fixed warm run | Verdict |
|---|---:|---:|---|
| Corpus scale | 51 files, 21.7 MB | 51 files, 21,700,054 B | Dimension matched; content-identical corpus unavailable |
| Query dispatches for 22 prefixes | Up to one per mutation | 1 | Pass |
| Search latency | About 1.0 s | 9.236 ms | Pass, limit 100 ms |
| Peak app CPU | About 30–50% | 9.13% | Pass, limit 15% |
| Peak RSS | Not preserved for the typing run | 125,894,656 B (120.06 MiB) | Recorded separately |
| Peak physical footprint | 157.5 MB reported by `sample` | 76,563,512 B (73.02 MiB) | Pass, limit 125 MB |
| `SessionFileParser.parse` in warm trace | 1.128 CPU-s in baseline sample | 0 references | Pass |
| Settled idle CPU | About 0% | 0.04% before, 0.02% after | Pass, limit 1% |

The final query was `performancequeryabcxyz` (22 characters). The driver installed all 22 prefixes at 100 ms intervals. The original literal query and cadence were not recoverable from the baseline artifacts, so this cadence is explicit rather than inferred.

## Build and test evidence

```sh
ruby scripts/generate_xcodeproj.rb
git diff --check

xcodebuild -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/tenx-search-final-tests test

swift test --package-path OmpKit

xcodebuild -project 10x.xcodeproj -scheme 10x \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/tenx-search-release build
```

Results:

- App suite: 112/112 passed.
- OmpKit suite: 126/126 passed, with the two environment-dependent real-OMP tests skipped as declared by the suite.
- Universal Release build: succeeded.
- Reference images: unchanged.
- Release executable SHA-256: `32cfc649ee7fb9b066493768ff241d5f9e95ce9fde815efdec39786a70fe0dce`.

Durable local verification artifacts:

- App test result: `/private/tmp/tenx-search-final-tests/Logs/Test/Test-10x-2026.08.25_16-07-47--0700.xcresult`
- Project generation and diff check: `/private/tmp/tenx-performance-recordings/fixed-search/final-project-check.log`
- OmpKit suite: `/private/tmp/tenx-performance-recordings/fixed-search/final-ompkit-tests.log`
- Release build: `/private/tmp/tenx-performance-recordings/fixed-search/final-release-build.log`

## Fixed capture

The exact visible build was:

```text
/private/tmp/tenx-search-release/Build/Products/Release/10x.app
PID 57918
```

The index was built once, search was closed and reopened, and the measured run was warm. The final capture used:

```sh
xctrace record --template 'Time Profiler' --attach 57918 \
  --output /private/tmp/tenx-performance-recordings/fixed-search/fixed-search-warm-final.timeprofile.trace

/private/tmp/tenx-proc-sampler-contract-1-1h 57918 22 \
  > /private/tmp/tenx-performance-recordings/fixed-search/fixed-search-warm-final-metrics.csv

/private/tmp/tenx-search-ax-driver 57918 workload performancequeryabcxyz 100
```

The Time Profiler run covers `2026-08-25T16:27:33.085-07:00` through `16:27:48.129-07:00`. Its app signposts are:

```text
SearchQueryStarted   9,216,554,791 ns
SearchQueryFinished  9,225,791,250 ns
Elapsed                  9,236,459 ns
```

Exports and checks:

```sh
xctrace export --input /private/tmp/tenx-performance-recordings/fixed-search/fixed-search-warm-final.timeprofile.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]' \
  --output /private/tmp/tenx-performance-recordings/fixed-search/fixed-search-warm-final-signposts.xml

xctrace export --input /private/tmp/tenx-performance-recordings/fixed-search/fixed-search-warm-final.timeprofile.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  --output /private/tmp/tenx-performance-recordings/fixed-search/fixed-search-warm-final-time-profile.xml
```

The export contains exactly one app `SearchQueryStarted`, exactly one app `SearchQueryFinished`, and no `SessionFileParser.parse` frame.

## Baseline artifacts and limits

- `/private/tmp/tenx-performance-recordings/baseline-search-typing.sample.txt` contains the 157.5 MB peak physical footprint and the parser/search CPU attribution for PID 64650.
- `/private/tmp/tenx-performance-recordings/baseline-search-miss-time.trace` identifies the baseline Release build and contains search/parser samples for PID 56988.
- `/private/tmp/tenx-performance-recordings/baseline-search-typing-time.trace` is not exportable (`Document Missing Template Error`).
- The baseline literal query, input cadence, per-second sampler CSV, and original 51 files were not preserved. Those are reported as unavailable rather than reconstructed as exact evidence.

Only the exact profiled PID was terminated. `/private/tmp/tenx-performance-recordings/fixed-search/fixed-search-cleanup.log` records `profile_pid_57918_exited=true` and `profile_children_exited=true`.

Binary traces and disposable corpus copies remain under `/private/tmp` and are not committed.
