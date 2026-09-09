# Task 10 report: optional native checker and bounded contract corpus

Status: DONE

Base: `936368d556eb0e5d87b81c84d6287b36b6d5b201`

Source commit: `dd5622bb617e2bab30bf72d8797f781ef89db51c feat(map): check native layouts within a bounded generation budget`

## Implemented

- Added `SessionMapChecker`, which renders the production `SessionMapGraphView` with persisted first-seen ordering, inert interaction/activity/motion, the current pane width minus the pane's shared 16-point horizontal content insets, and a 480-point viewport limit. AppKit view capture remains on the main actor; PNG encoding and the isolated checker completion run off it.
- Added a bounded verdict parser for the five allowed issue types. It accepts at most 12 issues with 240-character descriptions, ignores unknown fields, rejects malformed/entity-bearing XML, and preserves the valid writer map when checking is unavailable.
- Extended `SessionMapGenerator` with one shared three-call budget and one writer retry/rewrite budget. It records off/skipped/passed/failed/rewrittenUnchecked/unavailable, never checks a rewritten revision twice, treats deterministic layout diagnostics as authoritative, and skips render/check work for status-only graph changes. Structural comparison includes node identity/kind/group/display geometry fields and edge endpoints/kind/label.
- Added checker configuration, capability, and source/config publication fences. AppModel re-resolves the selected checker before publication and passes the actual synchronized pane width.
- Added a pane metadata bridge for persisted first-seen order, update time, and honest final-revision disclosure. Production fresh/reload paths use record metadata; explicit snapshot/fixture view overrides still take priority. Passed/failed disclosures limit the claim to the rendered graph region, while rewritten/unavailable outcomes state that the final revision was not checked.
- Extended the live fixture call record with total, writer, and checker attempt counts without persisting prompts, XML, transcript content, or images.
- Added one opt-in current-configuration contract runner. It resolves the configured writer at run time, executes one generation for each of four synthetic cases, writes non-overwriting JSON evidence and planning/incremental native PNGs, records model identity/timing/call counts/ID retention/layout diagnostics/source SHA, and remains skipped by default.
- Reused the existing full `supportingXML` fixture and its deterministic parser/native snapshots. It covers section/row/text/stat/chart, timeline, files, checklist, callout, and next-step content without reference churn.
- Regenerated `10x.xcodeproj` with the pinned generator; three new Swift files produced 12 generated-project lines.

## Verification

Behavioral RED: `/tmp/10x-f59a-session-map-task10-behavioral-red.log`. One test executed and recorded the expected three failures before checker integration: one call instead of three, the original headline instead of the rewrite, and off instead of rewrittenUnchecked.

First GREEN: `/tmp/10x-f59a-session-map-task10-first-green.log`. The required valid → issues → valid path passed 1/1 within three calls.

Final focused evidence: `/tmp/10x-f59a-session-map-task10-final-focused.log`. Eleven non-live declared functions passed and the live contract function was intentionally skipped; the two parameterized functions exercised four malformed-verdict cases and four budget/failure cases. The aggregate reported 12 selected tests in 0.059 seconds with no failures.

Final neighboring evidence: `/tmp/10x-f59a-session-map-task10-final-regressions.log`. Nine tests passed in 0.263 seconds, covering writer repair/cache/reconciliation, late-generation and AppModel race fences, six-block supporting-content parsing, diagram ordering, and light/dark 320/440 supporting-leaf snapshots.

Native checker evidence: the initial `/tmp/10x-f59a-session-map-task10-native-checker-candidate.png` is preserved. Root inspection found it used the 320-point outer pane width rather than the pane's 288-point inner graph viewport. The corrected `/tmp/10x-f59a-session-map-task10-native-checker-corrected-candidate.png` is 576×836 with SHA-256 `695aae0aff18bd55232e7489deabf0a65eb538e36e01a1be97787dc59037aefb`. `/tmp/10x-f59a-session-map-task10-native-corrected.log` passed 1/1 in 0.044 seconds and asserts the outer-to-inner dimension mapping. Original-resolution inspection shows the actual Root 1–7, Cycle A/B, Disconnected, and Dependent graph cards, status rows, routes, and Relationships disclosure with viewport cropping matching the production pane. Both are unpromoted `/tmp` candidates; no reference image changed.

Fresh/reload metadata evidence: the first reload attempt correctly failed three assertions because the test fixture preinstalled a pane and bypassed the production async load entry point. The passing rerun overwrote `/tmp/10x-f59a-session-map-task10-metadata-green.log`; the failed result remains in `/tmp/10x-f59a-session-map-derived/Logs/Test/Test-10x-2026.09.08_17-31-12--0700.xcresult`. The fixture gained a default-preserving option to enter the production load path, after which fresh and reload tests passed 2/2 in 0.014 seconds.

`git diff --check` passed before the source commit.

## Root-owned gate

The Release build, full app suite, opt-in configured-writer corpus, live checker/provider result, native Regenerate click, before/after incremental inspection, and chat-state preservation remain root-owned per the assignment. No live model call, preference mutation, reference promotion, merge, release, or deploy occurred in this task.

Enable the one contract runner with the Xcode-forwarded variables `TEST_RUNNER_TENX_SESSION_MAP_LIVE_CONTRACT=1`, `TEST_RUNNER_TENX_SESSION_MAP_EVIDENCE_DIR=<explicit directory>`, and `TEST_RUNNER_TENX_SESSION_MAP_SOURCE_SHA=<exact build SHA>`. It refuses to overwrite an existing `session-map-contract-<SHA prefix>` directory.
