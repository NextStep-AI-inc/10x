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
