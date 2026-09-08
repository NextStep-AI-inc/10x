# Model favorites and effort selector implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist model favorites above the catalog and show every supported effort label using Tanner's approved segmented preview.

**Architecture:** An app-local favorite identity store mirrors RecentModelStore's persistence boundary. ComposerControlsModel exposes favorites, presentation builds sections, and shared picker content owns independent row/star actions. Effort layout is computed from actual available width and supported options.

**Tech Stack:** SwiftUI, UserDefaults, Swift Testing.

## Task 1: Favorite persistence and presentation

Owned files: new `App/Sessions/FavoriteModelStore.swift`, `App/Sessions/ComposerControlsModel.swift`, `App/Sessions/ComposerControlsPresentation.swift`, `Tests/TenXAppTests/FavoriteModelStoreTests.swift`, `Tests/TenXAppTests/ComposerControlsPresentationTests.swift`.

- [ ] Add failing behavioral checks: a favorite survives a second store instance; same model ID from two providers remains distinct; toggle removes only the selected identity; missing catalog entries don't render but stay stored; filtered favorites precede catalog results and are not repeated in Recent.
- [ ] Reuse the existing stable `ComposerModelInfo.id` (`provider/modelID`). Store an ordered string array under `favorite-model-keys`, without changing OMP config. API:

```swift
@MainActor
struct FavoriteModelStore: Sendable {
    func toggle(_ model: ComposerModelInfo)
    func rankedModels(from catalog: [ComposerModelInfo]) -> [ComposerModelInfo]
}
```

- [ ] Inject the store with a default into ComposerControlsModel; recompute `favoriteModels` after catalog refresh and toggle. A favorite toggle never invokes model-selection RPC.
- [ ] Extend `pickerSections(models:recents:query:)` with a default-empty `favorites` argument. Filter favorites with the same matching function; put FAVORITES first, then existing recents (excluding favorites) and provider groups (excluding favorites). Preserve current no-favorites behavior and search semantics.
- [ ] Run the exact new tests and existing presentation tests; inspect nonzero count. Commit these owned files only.

## Task 2: Independent stars and full effort labels

Owned files: `App/Sessions/ModelPickerContent.swift`, `App/Sessions/ModelPickerFlyout.swift`, `App/Sessions/ComposerSessionControlsView.swift`, and focused picker presentation tests.

- [ ] Thread favorite identities and toggle callback through both the flyout and reusable ModelPickerContent, with defaults for command-browser callers. Keep model row and star as sibling buttons, not nested buttons. Accessible labels describe Add/Remove favorite plus model/provider; changing a star keeps the picker open.
- [ ] Change default picker width from 300 to 440 and make content width follow the measured available container. Preserve the stepped outline, keyboard navigation, dismissal, catalog loading/errors and Fast mode.
- [ ] Use an effort title row followed by evenly sized segments. Display `xhigh` as `Extra high`; other actual options have readable capitalized labels. Use emphasis background/on-emphasis foreground for selected state.
- [ ] At widths below 390, six levels use three columns/two rows. At wider sizes six fit one row. Calculate settings height from row count so Fast mode/outline never clips. Four supported levels remain one row when space permits.
- [ ] Add focused layout checks for 440/six, 360/six and 360/four options; verify full labels and provider-specific choice preservation. Do not assert a screenshot alone proves star persistence.
- [ ] Regenerate the Xcode project if source files were added, build Release and inspect the actual picker in normal and constrained windows. Exercise search, star/unstar, reopen/relaunch, keyboard selection and effort updates. Capture screenshots against the approved preview.
- [ ] Commit, then perform spec and quality reviews before marking this slice complete.

## Verification invocation

```sh
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS' -derivedDataPath /tmp/10x-interaction-build \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
  '-only-testing:TenXAppTests/favoriteModelsPersistAcrossStoreInstances()'
```

Expected: the new function fails before implementation and passes afterward, with one executed Swift Testing test. Add the remaining exact function selectors from the implemented test declarations. Final UI verification is required before completion.
