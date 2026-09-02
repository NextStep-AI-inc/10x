# Task 5 report — decode tool media once off-main

## RED

Added `ToolMediaLoaderTests.swift` before `ToolMediaLoader.swift`, regenerated the project, and ran:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/mediaLoaderDecodesOneImmutableItemOnce()'
```

The test failed as expected because `ToolMediaLoader` and `DecodedToolMedia` did not exist. Result bundle: `~/Library/Developer/Xcode/DerivedData/10x-bxbthukntyhepwdxepxgagdrmozo/Logs/Test/Test-10x-2026.09.01_20-29-20--0700.xcresult`.

## GREEN and verification

Implemented an `@MainActor` observable loader with a cancellable active task, one completed-item cache, injected async decoding for deterministic tests, and a detached ImageIO decoder for inline base64 and file URLs. `DecodedToolMedia` retains decoded bytes for Save. HTTP(S) previews remain on `AsyncImage` and do not call the loader.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/ToolMediaLoaderTests'
```

Passed: 6 tests covering one decode for repeated immutable IDs, completed same-ID cache reuse, replacement/stale-result rejection, explicit cancellation, invalid inline data, and retained Save bytes.

```bash
! rg -n 'Data\(base64Encoded|NSImage\(data: decodedData' App/Tools/ToolSurfaceView.swift
```

Passed: no decoding remains in `MediaItemView` or its computed view helpers.

The six directly affected media snapshots were recorded, visually inspected, then rerun normally:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  '-only-testing:TenXAppTests/mediaToolCardsSnapshot()' \
  '-only-testing:TenXAppTests/mediaToolCardsSnapshotDark()' \
  '-only-testing:TenXAppTests/semanticToolSurfacesSnapshot()' \
  '-only-testing:TenXAppTests/semanticToolSurfacesSnapshotDark()' \
  '-only-testing:TenXAppTests/mcpFallbackToolCardsSnapshot()' \
  '-only-testing:TenXAppTests/mcpFallbackToolCardsSnapshotDark()'
```

Passed: 6 snapshots. The inspected change is limited to each local preview's initial compact spinner while detached ImageIO work completes; labels, Open, metadata, and surrounding layout remain intact. The loader publishes the decoded `CGImage` on completion.

```bash
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS'
bundle exec ruby scripts/generate_xcodeproj.rb
git diff --check
```

Passed: universal Release build, reproducible project generation, and whitespace validation. The generator added exactly 8 `project.pbxproj` lines for the two new Swift files. Release retains pre-existing warnings in `MessageBlockView` and `ModelPickerFlyout`; none originate in Task 5.

## Full-suite result

Ran the full suite twice:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
```

After updating the six direct snapshot references, both runs reached 1,166 tests in 26 suites with the same sole failure: `DiffRenderPresentationTests.cancelledOldTokenizationCannotPublishIntoReplacementContent()`. That out-of-scope diff test passes in isolation. No diff files were changed.

## Self-review

- `ToolMediaLoader` cancels prior work for a new ID and checks both task cancellation and active item ID before any main-actor publication.
- Same completed IDs return without another decode; local and inline data keep their full bytes in the loaded result, and unsupported data is loaded with no image rather than discarded.
- `MediaItemView` renders state only. Save reads `loader.decodedData`; no base64 or AppKit raw-data image construction remains in the view path.
- `CGImage` crosses the detached boundary via the narrow `@unchecked Sendable` decoded-result wrapper because CoreGraphics does not provide static Sendable conformance; all mutable loader state remains main-actor isolated.

## Fix Round 1

### RED

Added the new generation, cancellation, and default-decoder tests first. The
focused test build failed as expected because `ToolMediaItem` had no
`contentID` initializer argument:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  '-only-testing:TenXAppTests/ToolMediaLoaderTests'
```

### Review findings resolved

1. Detached ImageIO decoding now passes `kCGImageSourceShouldCacheImmediately:
   true` to `CGImageSourceCreateImageAtIndex`. The default inline-PNG test
   proves it returns a 1×1 `CGImage`, rather than relying only on injected
   decoding.
2. `decodeMedia` awaits its detached task through a cancellation handler that
   cancels that task, with cancellation checks retained before decoding and
   publishing.
3. A cancelled caller clears only its matching active generation after its
   await returns. `cancelledCallerCanReloadTheSameItem` proves a later same-item
   load starts and publishes a second decode.
4. Each extracted `ToolMediaItem` now stores a fresh UUID `contentID` outside
   `body`. The view task, loader active state, completed cache, and stale-result
   guard use it. Semantic `Equatable` deliberately excludes this token, so
   re-extracting unchanged bytes remains a reducer no-op; changed bytes produce
   a new item/token and reload. Tests cover both cases.
5. Loading reserves the successful preview's 200-point height. A mounted,
   settled snapshot harness restores all six affected light/dark references to
   decoded-preview coverage, and `tool-media-loading.png` independently covers
   the spinner geometry. Loaded light/dark and loading fixtures were inspected.
6. Loaded local previews use `Image(image, scale: 1, label: Text(...))`, so the
   image itself carries the accessibility label.
7. Default-decoder tests cover valid inline PNG, valid local temporary PNG,
   invalid inline data (`.unavailable`), and missing local files (`.failed`).
8. Save is gated to inline `item.data` and uses the loader-retained bytes.
   Local file cards retain Open without gaining Save.

### Verification

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  '-only-testing:TenXAppTests/ToolMediaLoaderTests'
```

Passed: 12 tests, including eager default decoding, same-generation caching,
same-visible-ID replacement, stale/cancelled publication, caller cancellation
and reload, invalid/unavailable data, local file failure, and retained bytes.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
```

One clean full run passed: 1,173 tests in 26 suites. A second parallel full run
reproduced only the existing unrelated
`DiffRenderPresentationTests.cancelledOldTokenizationCannotPublishIntoReplacementContent()`
flake. The isolated `DiffRenderPresentationTests` suite then passed all 12
tests, including that race. The media loader has no dependency on the diff
tokenization surface; this is documented for the planned diff-test gate fix.

```bash
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS'
bundle exec ruby scripts/generate_xcodeproj.rb
git diff --check
! rg -n 'Data\(base64Encoded|CGImageSource|NSImage\(data:' App/Tools/ToolSurfaceView.swift
```

Passed: Release build, reproducible generator, whitespace check, and no body/
computed media decode in `ToolSurfaceView`.

### Fix-round self-review

- `ToolMediaLoadState` is ordinary `Sendable`; only immutable
  `DecodedToolMedia`, whose `CGImage` must cross the detached boundary, remains
  `@unchecked Sendable`.
- Cache reuse requires the immutable content generation rather than a mutable
  display/index ID, and cancellation cannot clear a replacement generation.
- The seven snapshot changes are intentional: six now show decoded previews
  instead of first-frame spinners, and one is the explicit loading-state
  reference.

## Fix Round 2

### RED

Added reducer regressions before reconciliation. A running image result followed
by a complete result with identical media payload failed because extraction
created a different UUID; a changed payload already produced a different UUID,
as required. Added preloaded-loader tests before the new snapshot injection
initializer; they failed to compile until that initializer existed.

### Review findings resolved

1. `ToolPresentation.refreshContent()` is now the sole reconciliation boundary.
   It walks freshly extracted media and reuses an old generation only for a
   complete semantic `ToolMediaItem` match, consuming each prior match once.
   This preserves duplicate equal items one-for-one without relying on display
   IDs, while changed bytes, URL, MIME type, name, kind, or ID retain their new
   UUID. Reducer tests cover running→complete identity retention and changed
   same-slot payload replacement.
2. Removed the settled snapshot host's fixed yields, sleep, and ignored
   cancellation. The six loaded snapshots inject a deterministic loader factory:
   local fixture bytes and eager `CGImage` are preloaded, while the known
   malformed inline fixture is preloaded unavailable. The production default
   factory remains asynchronous.
3. The loading snapshot now cleans up in `do`/`catch`: if snapshot I/O throws,
   it cancels the blocked task, opens its actor gate, awaits task completion,
   then rethrows. The success path performs the same release.

### Verification

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  '-only-testing:TenXAppTests/ToolMediaLoaderTests'
```

Passed: 15 focused loader tests, including both preloaded loaded/unavailable
states. The presentation/reducer regressions passed during all full-suite runs.

The seven media snapshots (six loaded light/dark cards plus the loading fixture)
were run three times through the normal test runner. Every run passed all seven
and the full suite: 1,177 tests in 26 suites. A final full run after adding the
presentation-to-loader cache regression passed 1,178 tests in 26 suites.

```bash
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release \
  -destination 'platform=macOS'
bundle exec ruby scripts/generate_xcodeproj.rb
git diff --check
! rg -n 'Data\(base64Encoded|CGImageSource|NSImage\(data:' App/Tools/ToolSurfaceView.swift
```

Passed: Release build, reproducible project generator, whitespace check, and
the no-body-decode guard. No snapshots changed in this round.
