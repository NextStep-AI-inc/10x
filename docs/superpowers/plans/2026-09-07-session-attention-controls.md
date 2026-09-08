# Session attention controls

> Use superpowers:subagent-driven-development for Tasks 1–2. Parent owns review and native Release verification.

**Goal:** Make an active session's status and pending request reachable from the header and composer without stealing the user's focus or reading position.

**Base:** `19ee7b7`, draft PR #37 stacked on readable-turn PR #35. Implements SIGNALS and the directly related request-arrival focus acceptance from PERMISSIONS. Other permission policy/timeout behavior remains a later slice.

**Design:** Reuse `SessionController.activityState` and its existing `SessionActivityState` labels/colors. Render one shared, compact status control in the header and active composer. Hide Ready; show Working, Needs your response, Failed, and Stopped consistently. Needs your response is an explicit button that scrolls to the earliest unresolved request. Arrival itself does not scroll or focus. Rail unread completion remains an independent existing signal. Do not add a notification system or parallel activity model.

## Task 1: Shared status and explicit transcript navigation

Owned files: `App/Sessions/SessionActivityControl.swift` (new), `SessionHeaderView.swift`, `ComposerView.swift`, `SessionController.swift`, `TranscriptNavigationRequest.swift` (new), `TranscriptView.swift`, and focused new `Tests/TenXAppTests/SessionAttentionTests.swift` or relevant existing controller/viewport/search tests. Regenerate `10x.xcodeproj` only with pinned `bundle exec ruby scripts/generate_xcodeproj.rb`.

- [ ] Add behavior tests for earliest unresolved confirm/select/input/editor/openURL row selection in transcript order, no-op without a pending request, and a fresh navigation identity on repeated explicit activation. Stable targets are `TranscriptItem.viewID` values such as `extension-ui:<id>`.
- [ ] Add a small navigation request carrying a row ID and unique identity, separate from text search. `focusPendingRequest()` clears a conflicting search request, stops following latest, and requests the earliest unresolved row. Keep row navigation reusable for the already-approved subsequent per-turn file index; do not add speculative target types or a navigation framework.
- [ ] Handle explicit navigation in `TranscriptView` by centering the target row after it exists, using the existing search/scroll patterns. Reject a removed/stale target or cancelled navigation. Request arrival must publish no navigation. A jump does not focus a text editor or act on the request.
- [ ] Add the same `SessionActivityControl` to the header and active composer. Keep existing model/context/send/Stop controls reachable at compact widths. Use existing typography and palette. Only the actionable state is a button; ordinary state text must not look clickable. Hide Ready and preserve the header's title/metadata hierarchy.
- [ ] Verify navigation does not alter rail unread state, current draft/images, request response state, or unrelated disclosure. Retain existing rail unread and viewport regressions.

## Task 2: Keep arrival from stealing typing focus

Owned files: `App/ExtensionUI/ApprovalCardView.swift`, `ExtensionQuestionCardView.swift`, related existing extension interaction tests, and focused additions to `Tests/TenXAppTests/ViewSnapshotTests.swift` / new reference images only after parent visual review.

- [ ] Remove or narrowly gate the unconditional arrival `.task` focus assignments. Explicit user clicks and normal keyboard navigation retain their existing behavior; Return must not silently approve a card that appeared while the user was typing elsewhere. Do not change response payloads, timeout semantics, or the runtime policy.
- [ ] Run focused attention/navigation, extension-router, search, unread-state, and viewport checks. Confirm nonzero test counts; use the documented free-function selectors with parentheses. Do not repeat the full app suite or promote six unrelated known snapshot failures.
- [ ] Render compact header/composer active and pending states plus a quiet Ready case. Send the candidate paths to the parent for visual review before copying new reference images. Keep the existing source-specific failures unchanged.
- [ ] Commit atomic changes and a private `.superpowers/sdd/session-attention/report.md` with exact SHAs, tests/counts, decisions, and limits. Do not add private scratch to Git. You are not alone; do not revert other edits or touch another worktree. Out-of-fence needs are skip-and-flag for that item, not a full abort.

## Task 3: Parent Release verification

- [ ] Review source and actual snapshot candidates for one authoritative status, stable row navigation, no implicit action, and compact layout.
- [ ] Build and visibly launch an isolated Release app. Drive two sessions: one working and one waiting for input. Confirm header, composer, and rail agree without clearing the other session's unread completion.
- [ ] In a controlled request-arrival fixture, scroll to older content and type a draft. The arriving card must leave focus, text, and position intact. Click the header action and the composer action separately; each must reveal the earliest unresolved card. Resolve the first of multiple requests and verify the next target updates. Record fixture evidence separately from real-provider activity.
- [ ] Verify Return, ordinary Tab/click focus, and Stop remain reachable from the pending card. The durable Stop correction is a separate PR; label base-runtime limitations honestly.
- [ ] Commit actual screenshots, source/artifact hashes, test counts, and verified/not-verified limits. Update roadmap/PR; keep draft on red baseline/base gates. No merge or deployment.
