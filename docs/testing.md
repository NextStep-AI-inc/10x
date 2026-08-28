# Running the tests

Everything lives in one scheme. The whole suite:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
```

The generated shared scheme intentionally runs `TenXAppTests` serially. This
target mixes process-spawning tests, MainActor snapshot rendering, and startup
watchdogs; Swift Testing's default full-target parallelism can exhaust a shared
Mac and turn scheduler delay into unrelated timeout and snapshot failures. Do
not override the scheme with `-parallel-testing-enabled YES`. Focused selectors
remain fast because they execute only the requested tests.

## Selecting a single test

The suite is Swift Testing free `@Test` functions, not `XCTestCase` subclasses.
There are no suites to address, so a file- or type-shaped selector matches
nothing:

```bash
# WRONG — matches zero tests and still prints ** TEST SUCCEEDED **
xcodebuild test ... -only-testing:TenXAppTests/ViewSnapshotTests
```

That vacuous pass is the failure mode to watch for: a green run that verified
nothing. Address the function instead, parentheses included:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:"TenXAppTests/fullTranscriptCompactWindowSnapshot()"
```

Confirm the run actually executed something. Swift Testing reports its own
count near the end of the log:

```
Test run with 1 test in 0 suites passed after 0.047 seconds.
```

A missed selector prints `Executed 0 tests` and `** TEST SUCCEEDED **` with no
`Test run with …` line at all — the absent summary is the tell.

## Snapshot references

References are PNGs in `Tests/TenXAppTests/ReferenceImages/`, compared
byte-for-byte by `Tests/TenXAppTests/SnapshotHarness.swift`.

### Promoting one snapshot

Any failing comparison — and any snapshot with no reference yet — writes the
image it actually rendered next to the reference as `<name>.actual.png`, and
the failure message carries the path. Open it against the reference, and if the
new rendering is correct, promote it:

```bash
mv Tests/TenXAppTests/ReferenceImages/rich-transcript-compact.actual.png \
   Tests/TenXAppTests/ReferenceImages/rich-transcript-compact.png
```

A later passing run deletes its own `.actual.png`, so a leftover file always
means that snapshot is still failing. They are gitignored; never commit one.

### Re-recording in bulk

To overwrite every reference with the current rendering, without reviewing each
one first:

```bash
TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild test \
  -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
```

Then `git diff --stat` to see which references moved, and inspect each changed
PNG before committing. Recording is deterministic: an unchanged view re-records
byte-identical, so anything git reports as modified is a real visual change.

**The `TEST_RUNNER_` prefix is required and cannot be dropped.** macOS unit
tests are hosted in the app, which `testmanagerd` launches without the invoking
shell's environment. `RECORD_SNAPSHOTS=1 xcodebuild test …` therefore never
reaches the test process, and neither does the trailing build-setting form
`xcodebuild test … RECORD_SNAPSHOTS=1`. Only `TEST_RUNNER_`-prefixed variables
are forwarded into the test host, with the prefix stripped.

**Never commit an `EnvironmentVariables` entry in the scheme's `TestAction`.**
Setting one locally to record from inside Xcode is fine, as long as it does not
land in the checked-in scheme. A scheme
entry beats the injected value, so the `RECORD_SNAPSHOTS = $(RECORD_SNAPSHOTS)`
entry that used to live there expanded to the empty string and silently
overwrote `TEST_RUNNER_RECORD_SNAPSHOTS=1`. That is what made CLI re-recording
impossible and let two transcript references rot through a whole merge cycle.
`scripts/generate_xcodeproj.rb` now leaves the block out on purpose.

## Regenerating the Xcode project

`scripts/generate_xcodeproj.rb` rebuilds `10x.xcodeproj` from the file tree.
Be aware that on a current `xcodeproj` gem it renames every object UUID, so a
regeneration lands as a ~1800-line diff plus new scheme blueprint identifiers,
unrelated to whatever you changed. Small scheme or target edits are cheaper to
make in the generator and mirror by hand into the checked-in project.
