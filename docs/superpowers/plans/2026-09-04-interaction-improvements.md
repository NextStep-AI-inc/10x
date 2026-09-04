# Interaction improvements implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved September 4 interactions in the actual macOS app, with regression and live Release evidence.

**Architecture:** Extend existing session controllers, transcript pipeline, account dock and settings stores. Keep pending UI state separate from confirmed runtime state. Reuse OMP contracts; do not introduce a parallel session protocol.

**Tech Stack:** SwiftUI/AppKit, Observation, Swift Testing, OmpKit RPC and JSONL session storage, generated Xcode project.

## Ordered working slices

Each slice receives its concrete file/contract plan before implementation. Independent feature work uses disjoint owned paths; parent integrates shared AppModel, SessionController and TranscriptView changes serially. The base is newer than the audit, so a verified existing fix satisfies a finding without another patch.

1. [x] Model favorites and approved segmented effort selector (U09/B12): `2026-09-04-model-favorites-effort.md`.
2. [x] Native questions (F05) from actual OMP request contracts; connect explicit waiting state.
3. [x] Persistent renaming and visible Restore (F06/B15); maintain metadata/search synchronization.
4. [x] Search-to-match (F04) with stable entry identity and older-history loading.
5. [x] Submission/drafts/focus/title/activity/recovery (U01/U02/U06, B01/B02/B13/B16).
6. [x] Composer right-side actions, literal input, Stop and queue receipts (U07, B03/B04/B05).
7. [x] Explicit transcript follow intent and stable reading anchors (U08, B08/B14).
8. [x] Provider/account hover and pinned details (U03/U04/U05), preserving main's new routing behavior.
9. [x] OMP/10x tab ownership and local composer settings (U10).
10. [x] Task schema, file references, empty/advisory rows and duration accuracy (B06/B07/B09/B10/B11).
11. [x] Integrated realistic Release QA, review and evidence delivery.

Implementation is committed through `b717755`; final Release evidence and completion status are recorded in `2026-09-04-interaction-verification.md`.

## Shared verification commands

Final app tests use Debug because test-only hooks are conditional on DEBUG; user-facing verification uses a separately built Release app:

```sh
xcodebuild test -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/10x-interaction-build \
  CODE_SIGNING_ALLOWED=NO
```

For focused regression checks use exact Swift Testing function names, including parentheses, and verify the nonzero `Test run with …` summary. Use `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` for subsequent local verification. Regenerate new source references with `ruby scripts/generate_xcodeproj.rb`; never hand-edit the project.

Final Release app uses a distinct bundle identity and its own preferences. User's installed app, drafts and unrelated sessions stay untouched. Test real development in a disposable fixture, with medium/high Sol, Grok 4.6 and Opus 5 only where provider behavior matters. Record screenshots, command logs, actual tested commit and reproduction steps. Restore global runtime preferences after testing.

## Review and completion

- [x] Every B/U/F item above has implementation and verification coverage; live-versus-fixture limits are explicit in the handoff.
- [x] Review implementation against the approved spec before code quality review.
- [x] Review live normal/constrained layouts and light/dark snapshots; multi-account motion and live Reduce Motion are explicitly left for human feel testing.
- [x] Prepare final PR body with actual results and limits; no source-only success claims.
- [x] Deliver Verified / Not verified / For Tanner to test in the handoff and local evidence report. No merge or deployment.
