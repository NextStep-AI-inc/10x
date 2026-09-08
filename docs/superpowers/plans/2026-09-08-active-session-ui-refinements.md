# Active-session UI refinements implementation plan

> **For agentic workers:** Use `superpowers:subagent-driven-development` to implement the bounded tasks below. The parent owns integration, project generation, Release QA, and the final review.

**Goal:** Apply Tanner's five visual adjustments to the combined native audit build: restrained composer activity, flyout warnings, distinct follow-up messages, a cleaner diff, and component-owned popup behavior.

**Architecture:** Reuse the app's `TwoRectShelfShape`, existing palette/type styles, and `OutsideInteractionDismissal`. Share geometry and dismissal plumbing; the invoking component owns presentation, panel sizing, preferred opening direction, and focus return. Preserve known submission mode through receipt/history reconciliation without inferring it from the message text or changing OMP's files.

**Tech stack:** Swift 6, SwiftUI and AppKit, existing OmpKit, Swift Testing and native macOS Release QA. No dependencies or runtime changes.

**Starting point:** Local integration `4b1d8b1`, fresh worktree `/tmp/10x-audit-ui-refinements`, branch `codex/active-session-ui-refinements`. Original audit branches stay independent. This pass contains only the requested refinements. GitHub merge and deployment need Tanner's explicit authorization.

## Design and acceptance

1. Keep the top session status. Replace the composer's repeated dot/Working label with a small animation. Preserve elapsed time if useful, accessible Working state, and Stop. Reduce Motion gets a stationary treatment.
2. Attachment and model warnings share a warning trigger in the composer footer. Opening it shows the full messages in an existing-style flyout; a warning's presence must not add an inline red-text row or increase composer height. Long text wraps in the panel. Loading/error/empty behavior remains owned by its component.
3. Follow-up receipts and delivered messages use a branch-arrow cue, a distinct leading accent and a restrained alternate surface, with a Follow-up label as additional information. Steer gets its own cue. Standard messages remain standard. Known unambiguous mode survives the receipt becoming a history row and reopening. Identical pending payloads with conflicting modes cannot be safely identified by OMP history and keep the standard delivered style. Older messages with no recorded mode are never guessed from their wording.
4. The tool card's top header owns the colored addition/removal summary. The diff body has one aligned file-details/action row, without a separate aggregate statistics toolbar. Multi-file patches retain per-file headings. Copy patch and Wrap/Scroll remain available, keyboard accessible, and truthful. File references, hunk context, progressive loading, and actual row coloring remain intact.
5. Model, context, warning, steer/follow-up, and project flyouts use the same placement rules. Prefer the component's configured side, choose the opposite side when it fits better, clamp to the usable window, and scroll oversized contents. The trigger remains connected to the panel's stepped shape. Escape, outside-click, toggling, switching panels, and window resize work without accidental action activation or lost editor focus. Preserve `OutsideInteractionDismissal`'s existing single-click handoff to the intended outside control; do not swallow deliberate navigation clicks. Existing command-browser keyboard behavior must continue to work.

## Task 1: Simplify diff chrome

**Ownership:** `App/Tools/DiffView.swift`, `ToolCardScaffold.swift`, `ToolSurfaceView.swift`, `ToolCardView.swift`; tightly related tests under `Tests/TenXAppTests/`. New shared diff presentation helpers only if the existing models cannot express the summary. No composer edits.

- [x] Inspect `ToolCardContent` and every `DiffView` caller. Keep standalone diff headers informative as well as tool-card usage.
- [x] Add a focused check for summary ownership and single/multiple-file header behavior. Existing structured-diff rendering checks cover parsing and progressive content; do not duplicate them.
- [x] Remove `DiffView.toolbar`'s aggregate colored counts. Place its Wrap/Scroll and Copy patch actions alongside the relevant file header; allow a second action row only when the available width cannot hold both.
- [x] Render typed diff totals in `ToolCardScaffold`'s outcome position with cyan additions and red removals. Avoid parsing a generic outcome string to recover numbers. Preserve the existing accessible header text.
- [ ] Capture the changed structured-diff snapshot, visually inspect it, then accept only the relevant reference images. Parent repeats this flow in the Release app.
- [x] Commit the bounded diff change after relevant checks pass.

## Task 2: Component-owned flyouts, warnings, and activity

**Ownership:** Composer controls (`ComposerView.swift`, `ComposerSessionControlsView.swift`, `ContextUsageControl.swift`, `ChooseProjectFlyout.swift`, `ModelPickerFlyout.swift`, `SessionActivityControl.swift`, `TurnActivityView.swift`), reused design primitives under `App/Design/`, and directly related tests. Keep broad session lifecycle and tool rendering changes out.

- [ ] Extract the existing window measurement into a reusable anchor reader and add a pure placement result. Inputs are the anchor rect, window content rect, desired panel size, preferred vertical side, and edge padding. Outputs are a clamped panel rect and selected side. The algorithm is:

```swift
let above = max(0, anchor.minY - bounds.minY - padding)
let below = max(0, bounds.maxY - anchor.maxY - padding)
let preferredSpace = prefersAbove ? above : below
let oppositeSpace = prefersAbove ? below : above
let opensAbove = preferredSpace >= desired.height || preferredSpace >= oppositeSpace
    ? prefersAbove : !prefersAbove
let availableHeight = opensAbove ? above : below
let size = CGSize(width: min(desired.width, max(0, bounds.width - 2 * padding)),
                  height: min(desired.height, availableHeight))
let x = min(max(anchor.minX, bounds.minX + padding), bounds.maxX - padding - size.width)
let y = opensAbove ? anchor.minY - size.height : anchor.maxY
let panel = CGRect(origin: CGPoint(x: x, y: y), size: size)
```

The reader normalizes AppKit coordinates to the helper's top-down coordinates once. Include the trigger step in the final silhouette and offset calculations. Do not cap a SwiftUI frame without making its overflowing content scrollable.

- [ ] Before implementation, cover a lower-edge anchor opening upward, an upper-edge anchor opening downward, right-edge horizontal clamping, a short window, and a desired width larger than the window. Use concrete `CGRect` values and assert containment and selected direction. Run those focused tests red, then green.
- [ ] Adapt the model control to use shared placement, removing its width-only reader. The existing loading/empty content and keyboard model navigation remain reachable.
- [ ] Replace context's system popover and the send action's OS `Menu` with component-owned app-style panels. Send-action options are `Steer` / `Send during the current response` and `Follow up` / `Queue for the next turn`; selecting an option updates the existing controller preference and returns focus to the editor.
- [ ] Add warning presentation to `ComposerFlyout`, rendering the existing deduplicated feedback in a footer-triggered panel. Keep the trigger slot's height constant. Remove the inline warning row, retain complete warning text in the panel, and dismiss when the warning is resolved.
- [ ] Reuse the component placement/dismissal behavior for project selection and verify command-browser coexistence. Avoid separate parent-level offsets for the migrated controls.
- [ ] Give `SessionActivityControl` an explicit compact composer variant that replaces its dot/Working label with a restrained animation; its header default keeps text. Remove the duplicate quiet-turn Working label in `TurnActivityView` by reusing the same restrained animated treatment where appropriate. Use the Reduce Motion environment and expose an accessible Working label; preserve top status and Stop behavior.
- [ ] Run focused composer routing, model picker, context control, and placement checks. Parent owns Release native checks at the app's minimum width, a short window, and a normal desktop window.
- [ ] Commit the bounded component change after checks pass.

## Task 3: Preserve and render known submission mode

**Ownership:** `PendingUserSubmission.swift`, `SessionController.swift`, `TranscriptView.swift`, `MessageBubbleView.swift`; a small colocated submission-presentation store and its tests; `App/Application/AppDependencies.swift` for store injection and `App/Application/AppModel.swift:makeSessionController` for passing that dependency only. Default test/preview controllers use an in-memory store. No OMP schema/runtime edits or recovery-store expansion.

- [ ] Retain the requested `StreamingBehavior?` on the receipt before awaiting prompt acknowledgment. An idle primary send has no mode; never read the current global preference to classify an older message.
- [ ] Extend receipt reconciliation with a matched-pair callback/result while preserving its current consumed-index behavior. Keep unresolved mode receipts separately until a real history load can bind them to persisted entry IDs. Controller history-loading sites already know when the data is persisted; no broad snapshot-provenance system is needed.
- [ ] Bind live echoes to known mode for immediate display; bind persisted history rows using the existing ordered exact text/image matching and the captured minimum user index. Where a live echo supplies a raw message timestamp, use it to disambiguate the later history match. Do not match ambiguous candidates, guess from text, or persist synthetic live IDs as durable identity.
- [ ] Persist only canonical session path, real JSONL entry ID, and mode in a small app-owned presentation store. Reuse `UserDefaults` string dictionaries for this modest annotation set; store no message text or images. Inject isolated defaults in tests. Reopening loads those known annotations. Document that imported/preexisting messages without a mode annotation keep the standard appearance.
- [ ] Pass mode explicitly to `MessageBubbleView`, including it in Equatable rendering. Apply the same appearance to pending receipts and their delivered bubbles. Use existing typography/palette plus the requested visual cue, not labels alone.
- [ ] Write meaningful checks for receipt echo arriving before ACK, identical queued messages with different modes, live-to-persisted ID replacement, reopen through a fresh store instance, unknown historical messages remaining standard, and stale history generation rejection. Run red before implementing the new data flow, then green.
- [ ] Commit the bounded mode/presentation change after checks pass.

## Task 4: Native acceptance, evidence, and handoff

**Ownership:** Parent: project generation, test/build orchestration, native QA, evidence, gallery integration, documentation and PR status.

- [ ] Regenerate `10x.xcodeproj` using `ruby scripts/generate_xcodeproj.rb` with the pinned xcodeproj 1.27.0. Never hand-edit it.
- [ ] Run focused affected tests and the app build. Use a unique derived-data path for this worktree. Previously recorded snapshot baseline failures remain separately identified; do not call a suite green if they still fail.
- [ ] Package a named Release QA app using the existing isolated QA home and OMP wrapper pattern. Record source SHA, executable SHA, launch command, and minimum-window dimensions. Leave Tanner's real app and settings untouched.
- [ ] Drive actual controls: trigger and dismiss model/context/warnings/send/project panels, select both send modes, resize with an open panel, scroll oversized content, and verify focus returns. Check simultaneous warning messages and composer height. Capture screenshots from the actual app.
- [ ] Run a controlled response; check animation plus Stop. Send a follow-up and a steer; observe pending and delivered styles, then reopen to confirm recorded style. Confirm a standard message is not reclassified.
- [ ] Expand a real tool diff, change Wrap/Scroll, copy the patch, follow its file reference, and inspect single- and multi-file/long-path layouts. Preserve the existing row colors.
- [ ] Review the actual changed UI against Tanner's screenshot and all five checklist items. Fix only regressions in the requested flow.
- [ ] Add the new real-build evidence and explanations to the progress gallery, retaining the earlier evidence as the prior state. Verify the gallery controls after updating it.
- [ ] Update plan/checklist and PR description with actual results, explicit gaps, and the local build to test. Parent reviews spec coverage then code quality. No GitHub merge or deployment.

## Scope and known limits

The previous audit's live CJK check and four unrelated baseline snapshot failures remain separate from this refinement. No provider-notice, premature-provider-completion, keyboard-setting, runtime, or dependency changes are added here. Generated project changes are parent-owned so parallel file creation cannot race the generator. Verification ends after the requested native slice passes and evidence is attached; remaining unrelated findings are reported, not absorbed into the patch.
