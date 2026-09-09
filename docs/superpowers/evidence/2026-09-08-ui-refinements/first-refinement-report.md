# Active-session UI refinement evidence

Status: **DONE_WITH_CONCERNS**. All five requested UI changes passed native acceptance. [PR #46](https://github.com/NextStep-AI-inc/10x/pull/46) remains **draft** because the full app suite is not fully green. No GitHub merge or deployment occurred.

[Native screenshot gallery](progress-gallery.html) · [Implementation plan](../../plans/2026-09-08-active-session-ui-refinements.md) · [Test results](test-results.txt) · [Recorded checks](verification.json) · [Native proof](native-verification.json)

## Requested changes

- [x] Keep the header status; replace repeated composer and quiet-transcript Working text with animated bars. Two real frames show different bar heights. The final build's Stop button ended the controlled response.
- [x] Show independent warnings in a fitted flyout. Zero, one and two warnings have identical composer border rows, 417–418 and 563–564, in the 760×592 window. Clearing the model warning leaves the attachment warning intact.
- [x] Give follow-up and steer messages distinct symbols, accents and surfaces, including pending receipts. Both unique test messages were delivered once and kept their appearance after app quit/relaunch. The app-owned send-action panel supports keyboard and pointer selection.
- [x] Keep colored diff totals in the tool header, remove repeated single-file labels, and align multi-file details with actions. Wrap/Scroll worked; Copy patch pasted both complete patches into the actual composer. File navigation opened the exact neutral fixture file in Cursor in the preceding Release checkpoint.
- [x] Model, project, context, warning and send-action components own their panels. Native normal/minimum-window checks passed, long model content scrolled, Escape returned composer focus, and single-click panel switching worked. Resizing via the window corner dismisses the panel cleanly; reopening fits the new window bounds.

## Build and verification

Native Release source: `ffd095a1bf1dcb2bc1f0a4a62c650b5de3794f35`, branch `codex/active-session-ui-refinements`, based on `codex/active-session-audit-integration`.

- Release build, Swift 6 compilation, pinned Xcode project generation and strict ad-hoc signature check passed.
- **1,605 app tests executed: 1,602 passed, 3 failed.** All seven new mode checks, the existing repeated-queue check, and changed-surface screenshot checks passed.
- The two failed running/error snapshots exactly match the actual hashes recorded against pre-merge main in [main-baseline.json](../2026-09-08-audit-integration/main-baseline.json). Their references remain unchanged.
- `staleReconciliationFailureCannotOverwriteNewerBoundary()` failed to reach its third synthetic history request under full-suite load; it passed in 0.735 seconds in the isolated rerun. Its existing synthetic timing is unchanged. This is an open verification concern, not a green suite.
- The two expanded diff references and 19 additional affected references were visually inspected before acceptance. [Snapshot review](snapshot-review.json).
- A test-fixture regression found in the first full run was corrected: its preexisting history row is written before Ready, keeping repeated-message indices consistent. The original repeated-queue behavior check then passed.

The native acceptance profile uses a local [RPC fixture](native-fixture.py) to generate provider events, queued delivery and real structured tool presentations. The app itself is the Release binary. No external model work is implied by these checks. [Received prompts and delivery proof](native-rpc-proof.json).

## Review and limits

Parent review covered the diff and file-path identity, component placement/focus behavior, submission matching/persistence, stale-generation guards and rendered message equality. The reviewed follow-up keeps transient styling until the persisted snapshot is installed and caches recorded modes outside row rendering. No open finding blocks the five demonstrated UI flows.

OMP supplies no originating queue ID or persisted send mode. Identical overlapping payloads with conflicting modes therefore keep a standard delivered appearance; imported/older messages are not classified by their wording. The native fixture verifies unambiguous text messages. Image-only mode styling, the macOS Reduce Motion setting and VoiceOver were not exercised natively. Above/below placement is covered by geometry tests; native panels in this footer layout opened above.

The earlier audit's live CJK input gate remains pending. Warning text reuses existing messages, including the generic image-limit wording on an invalid image. Provider runtime behavior, dependencies and unrelated baseline fixes are outside this change.

## For Tanner to test

Open `/tmp/10x-ui-refinements-final-build/10x-ui-refinements.app` or the [gallery](progress-gallery.html). The isolated app is running with the controlled **UI refinement acceptance** session available. Review animation feel, follow-up/steer contrast and the connected popup outlines at your preferred window size. The [build manifest](native-final-build.json) records the executable SHA, isolated profile and launch command.
