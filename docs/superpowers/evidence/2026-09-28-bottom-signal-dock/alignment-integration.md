# Composer alignment integration

User-requested source commit `773dbe24ff57b4cabe13d4d48f05d2f2e059d9b9` cherry-picked cleanly as `6e430ef` on `codex/bottom-dock-design`.

The change gives the editor and footer the same column width and trailing inset. Send/Steer/Follow up stop before the wave and provider controls. It removes the separate footer GeometryReader calculations.

## Verification so far

- Universal Release build and Swift compile/typecheck passed (`/tmp/10x-alignment-integration-release.log`), using the same isolated build command as the test-suite repair report.
- First integrated full suite: 1,715 tests / 44 suites / 33 issues: 32 expected alignment snapshot differences and the previously intermittent repeated-message queue assertion (`/tmp/10x-alignment-integration-tests.log`).
- Diagnostic full suite: 1,715 tests / 44 suites / 32 issues, all alignment snapshots. The queue case passed (`/tmp/10x-alignment-diagnostics-tests.log`).
- Bounded queue test repeat: all 20 repetitions passed, exit 0 (`/tmp/10x-queue-repeat-diagnostics.log`). This does not establish the intermittent full-suite failure's cause.
- All 32 alignment snapshot pairs were visually reviewed. [Manifest](alignment-reference-manifest.json) records before/after hashes. The existing exact-image harness remains unchanged.
- Native Release: clicking the relocated send button creates a session; Follow up selection plus send creates one queued follow-up bubble. Attachment opens the native chooser. Model opens and anchors correctly. [Working screenshot](alignment-native-working.jpg), [model screenshot](alignment-native-model.jpg).
- Initial unsuccessful model clicks resolved after refreshing the automation window binding; the previously failing point then opened the menu. No product patch was made for that automation issue.

## Limits

Native window remained 1180×760 points; resize actions did not take effect. The existing minimum-width snapshots were reviewed, but native narrow-width interaction was not verified. The user began manually testing the isolated QA app (PID 50902), so it was left open and automation stopped. This is a fixture-backed runtime, not a live provider integration check.

Final suite result and integration commit will be recorded after verification.

## Integrated alignment gate

After refreshing the reviewed references, the full suite passed: **1,715 tests / 44 suites**, exit 0, **TEST SUCCEEDED**, 16.126 seconds (`/tmp/10x-alignment-final-tests.log`). The earlier intermittent queue assertion remains under separate causal investigation; a passing run alone is not treated as its repair.
