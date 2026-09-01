# Task 2 — Paginate Existing Tool, Source, and JSON Expansions

## Status

DONE

## Implementation

- Added `ToolSurfacePagination` policies: console `10/100`, collection `8/50`, JSON children `12/50`, and JSON scalar characters `2,000/4,000`.
- Replaced console, collection, JSON-child, and JSON-scalar Boolean expansion state with `ProgressiveReveal` state and `ProgressiveRevealButton`.
- Preserved full-data copy behavior: console copies `output`, source copies `presentation.text`, JSON scalar copies the complete `text`, and JSON raw copy remains complete.
- `SourceSurface` now initializes a `200`-line page policy, or its caller-provided preview limit with the same `200`-line page size. Its nonisolated `visibleLineCount(total:previewLineLimit:reveal:)` interface is reusable by Task 4.
- Added deterministic initial-state snapshot coverage containing 500 console lines, 150 collection items, 500 source lines, 200 JSON children, and an exact 20,000-character JSON scalar.
- Updated affected transcript snapshot references from unbounded controls to finite next-page controls.

## Files

- `App/Tools/ToolSurfaceView.swift`
- `App/Design/SourceSurface.swift`
- `Tests/TenXAppTests/ToolContentExtractorTests.swift`
- `Tests/TenXAppTests/RendererPaginationTests.swift`
- `Tests/TenXAppTests/ReferenceImages/renderer-pagination-initial.png`
- Seven existing transcript snapshot references under `Tests/TenXAppTests/ReferenceImages/`
- `10x.xcodeproj/project.pbxproj` (regenerated with the pinned generator)

## RED evidence

Command:

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/rendererPaginationPreservesExistingPreviews()'
```

Result: expected build failure. `ToolSurfacePagination` and `SourceSurface.visibleLineCount` were both missing.

## GREEN and verification evidence

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/RendererPaginationTests'
# PASS: 4 tests

xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/ViewSnapshotTests'
# PASS: 15 tests

xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
# PASS: 1,118 tests in 21 suites
```

I visually inspected `renderer-pagination-initial.png`: its initial state shows 10 console lines, 8 collection items, 20 source lines, 12 JSON children, and 2,000 scalar characters, with the expected finite next-page controls.

## Self-review

- Confirmed every reveal action advances by one policy page and only collapses after all data is visible.
- Confirmed source caller previews remain the initial visible limit and are not replaced by the default 200-line limit.
- Confirmed no copy action uses a rendered prefix.
- Confirmed all project-file changes came from `bundle exec ruby scripts/generate_xcodeproj.rb`.
- `git diff --check` is clean.

## Concerns

None. The full suite initially identified seven expected snapshot-reference changes caused by replacing unbounded labels; they were visually inspected and updated, then the full suite passed.
