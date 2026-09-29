# Test-suite repair evidence

## Scope and diagnosis

The pre-repair integrated suite ran 1,714 tests in 44 suites and reported 188 issues: 180 snapshot assertions and eight functional assertions across five tests. The repair preserves exact PNG comparison; no tolerance, disabled test, or blanket record mode was introduced.

- Opening now starts the runtime while resolving header metadata. The opening task remains tracked until the header resolves and generation is checked, so disposal closes an opened child without installing stale metadata.
- Provider and reconciliation fixture transitions use explicit release markers instead of short wall-clock windows. The provider-less model contract remains unchanged: an explicit model without a provider clears it immediately; an update without a model retains it.
- Archive cleanup waits for child removal and activity cleanup instead of assuming a fixed 500 ms delay.
- Active composer snapshot fixtures supply session signal state. Expanded activity snapshots request Expanded mode and use a canvas that contains the full cards.
- Every changed reference was visually inspected. Initial differences comprised approved dock changes, tool layouts already on main, and small text-raster differences. The exact OS/font cause of the latter was not established. Six dependent tool snapshots changed only where they embed the refreshed source-image fixture.
- Detached composer snapshot hosts cannot supply a native window anchor. Their forced-open model menu uses the existing provisional 120pt trigger. Native window placement is verified separately.

## Iteration results

- Baseline: 1,714 tests, 44 suites, 188 issues (`/tmp/10x-main-integration-tests.log`).
- First repaired full run: 1,715 tests, 44 suites, 16 issues (14 snapshot assertions, two functional assertions; `/tmp/10x-repair-full-1.log`). Opening/disposal, archive cleanup, provider lifecycle, and stale reconciliation passed under full-suite load.

Final verification results and native evidence are recorded below.
- Second repaired full run: 1,715 tests, 44 suites, seven issues (five snapshots and two command event-order assertions; `/tmp/10x-repair-full-2.log`). Earlier queue/context failures passed but were not treated as resolved by that alone.
- Command fixtures now hold the prompt response until the controller consumes a following control-event sentinel. The context fixture arms a stale response explicitly and chooses token values by accepted-send state, not incidental state-read count.
- Provider onboarding snapshots use isolated preferences, stub settings/update dependencies, and a cancellation-aware test deadline. This prevents full-suite contention from firing the production 10-second startup timeout and clearing the fixture provider model. The fixture asserts provider identity after bootstrap.
- Working snapshots freeze animation through the existing Reduce Motion environments. Three working captures and the small settings text-field baseline adjustment were byte-identical between a full run and a focused run (`/tmp/10x-repair-snapshot-stability.log`).
- Third full attempt stopped at compilation: Swift needed an explicit `CheckedContinuation<Void, any Error>` annotation in the test deadline helper. No tests ran in that attempt.

## Release and native evidence

Command (exit 0, **BUILD SUCCEEDED**; `/tmp/10x-repair-release.log`):

```sh
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination platform=macOS \
  -derivedDataPath .superpowers/sdd/2026-09-28-bottom-signal-dock/NativeQA/DerivedData \
  CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER=com.nextstep.tenx.bottomdockqa
```

This universal arm64/x86_64 Release build includes the final product opening fix. Subsequent edits only affect tests and evidence.

Native isolated Release window, fixture-backed runtime:

- Model footer opens a correctly anchored menu with clear space before workspace status: [model screenshot](test-repair-native-model.jpg).
- Send opens the session, enters Working, and a second prompt queues a steer message. Inline context opens its detail popover and Escape closes it: [working screenshot](test-repair-native-working.jpg).
- Cmd-N removes the context break while preserving aggregate working activity: [new-session screenshot](test-repair-native-new-session.jpg).
- QA process 10886 quit and was confirmed exited. The main checkout's unrelated edits were left untouched.

## Snapshot audit

[Reference manifest](test-repair-reference-manifest.json) records all 179 changed reference paths, original/final SHA-256 hashes, and review reasons. The exact-image comparison harness is unchanged. Snapshot frames for expanded tool cards were enlarged to contain the intended full content. The blank provider setup capture from the second full run was rejected, not promoted.

## Verification limits

Native checks use the test provider. Live-provider integration, VoiceOver, narrow-window interaction, and image paste/drop were not exercised in this repair pass. Earlier feature evidence records motion/compaction behavior; this repair did not change those animations. No fresh main-only full suite was run, so these failures are not all claimed to predate the feature.

## Final local gate

```sh
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination platform=macOS \
  -derivedDataPath .superpowers/sdd/2026-09-28-bottom-signal-dock/DerivedData
```

Exit 0, **TEST SUCCEEDED**. **1,715 tests in 44 suites passed in 14.168 seconds** (`/tmp/10x-repair-full-4.log`). This run includes every final fixture change and the new opening/disposal regression. `git diff --check` passed.

Result bundle: `.superpowers/sdd/2026-09-28-bottom-signal-dock/DerivedData/Logs/Test/Test-10x-2026.09.29_14-48-04--0700.xcresult` (local ignored artifact).

The previous red main-integration report is superseded by this repair result. Remote CI and merge state are recorded on PR #49.
