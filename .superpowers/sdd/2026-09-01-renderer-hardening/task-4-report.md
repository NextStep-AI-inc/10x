# Task 4 report — bounded assistant-document rendering

## RED

Ran after adding `ContentRenderSliceTests.swift` and regenerating the project:

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/nestedDocumentUsesOneGlobalBudget()'
```

Result: failed as expected. `ContentRenderSlicer` was not in scope at each new
slicer assertion. The test result is at
`~/Library/Developer/Xcode/DerivedData/10x-bxbthukntyhepwdxepxgagdrmozo/Logs/Test/Test-10x-2026.09.01_17-39-19--0700.xcresult`.

## GREEN

Implemented `ContentRenderSlicer` as a pure depth-first slicer with one mutable
budget. It retains non-empty list, quote, table, and source prefixes, preserves
the original `ContentDocument.source`, and makes sliced sources reuse their
original `SourceLine` values and full copy text. `ContentDocumentView` now owns
the sole 160/160 reveal state for document rendering. `CodeBlockView` disables
the standalone `SourceSurface` reveal so a sliced assistant document has no
nested code reveal control.

Commands and results:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/ContentRenderSliceTests'
```

Passed: 3 tests in 1 suite.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/contentDocumentBudgetSnapshot()'
```

Passed: 1 snapshot test.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/ViewSnapshotTests'
```

Passed: 15 tests in 1 suite.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
```

Passed: 1,135 tests in 23 suites.

```bash
bundle exec ruby scripts/generate_xcodeproj.rb
git diff --check
```

Passed with no output from `git diff --check`.

## Snapshot evidence

Recorded and inspected
`Tests/TenXAppTests/ReferenceImages/content-document-budget-initial.png`
(1600×7000). It shows complete visible table and list structures, source lines
1–128 with their original numbers, no source-level reveal button, and exactly
one `Show 160 more items` control after the bounded document prefix.

## Self-review

- The budget counts paragraph, heading, divider, image, and unsupported blocks
  as one unit; list items recursively; quote children recursively; table headers
  once plus each body row; and original source lines individually.
- Empty structural shells are omitted. A partial table is emitted only after
  consuming its header, and a source block is emitted only when at least one
  existing source line fits.
- Streaming appends do not mutate the `@State` reveal limit. The next render
  recomputes the total and retains the existing limit until the user activates
  the sole document button.
- The default standalone `SourceSurface` 200-line policy remains unchanged for
  tool surfaces; only `CodeBlockView` disables it for the already-sliced
  assistant-document path.
