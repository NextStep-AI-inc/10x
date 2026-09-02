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

## Fix Round 1

### Findings addressed

1. `ContentDocumentRenderState` is a pure source-identity-aware value. A strict
   prefix append carries the existing 160/160 reveal limit forward; a
   non-prefix replacement derives a fresh 160 limit before asynchronous state
   synchronization. The view does not mutate state while deriving its body.
2. `SourcePresentation(language:text:)` now retains raw numbered plain spans.
   `SourcePageLoader` is the shared `@MainActor` cache/cancellation boundary:
   it sync-primes at most 200 rows, 16,384 characters, and 2,048 characters per
   row, then tokenizes only newly visible overflow in a detached task. Its
   injectable `@Sendable` tokenizer and content ID plus task UUID prevent hidden
   work and stale publication. Copy text and original line numbers remain on
   `SourcePresentation`.
3. `SourceCard` is pagination-free. `CodeBlockView` uses it directly; only the
   standalone `SourceSurface` owns its 200/200 reveal state.

### RED

After first adding the document-state and source-loader tests and regenerating
the project, this focused test command failed as expected because
`ContentDocumentRenderState` was not yet in scope in the append/replacement
tests:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/ContentRenderSliceTests' '-only-testing:TenXAppTests/SourcePageLoaderTests'
```

Output: `/tmp/10x-task4-fix1-red.log`; result bundle:
`~/Library/Developer/Xcode/DerivedData/10x-bxbthukntyhepwdxepxgagdrmozo/Logs/Test/Test-10x-2026.09.01_19-01-51--0700.xcresult`.

### GREEN and verification

Focused parser, slicer, and loader run passed 11 tests in 2 suites. It covers
append retention, first replacement slice reset, raw parser lines, zero calls
for hidden lines, one finite 160→320 visible page, all sync ceilings, and
stale async replacement. Commands/results:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/sourcePresentationPreservesIndentationAsUntokenizedSource()' '-only-testing:TenXAppTests/MessageContentParserTests' '-only-testing:TenXAppTests/ContentRenderSliceTests' '-only-testing:TenXAppTests/SourcePageLoaderTests'
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/contentDocumentBudgetSnapshot()'
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/ViewSnapshotTests'
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/RendererPaginationTests'
```

Passed: 11 focused tests, 1 document snapshot, 15 ViewSnapshot tests, and 4
RendererPagination tests.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS'
ruby scripts/generate_xcodeproj.rb
git diff --check
```

Passed: 1,142 tests in 24 suites, Release build, reproducible project
generation, and whitespace validation.

### Snapshot evidence

`content-document-budget-initial.png` stayed green. The extracted source card
changed the existing `renderer-pagination-initial.png` raster only in the
lower-source-card strip: 103,706 pixels bounded to x=0…1439 and y=2091…2171
(81 pixels tall). I visually inspected both 1600×4800 images before promoting
the actual: syntax colors, line numbers, card geometry, controls, and the
`Show 200 more lines` pagination label are equivalent. The reference change is
deterministic source-card extraction rasterization, not asynchronous loading or
a semantic/layout regression.

### Self-review

- `SourcePageLoader` is `@MainActor`; its detached task captures only raw
  `Sendable` lines and tokenizer. Publication checks cancellation, task UUID,
  and captured content ID.
- No production caller remains of `SourceTokenizer.lines`; no document slicer
  or SwiftUI body tokenizes source.
- The only reference update is the visually inspected standalone pagination
  raster described above.

## Fix Round 2

### Findings addressed

1. ContentDocument now stores a construction-time structural render identity.
   ContentDocumentRenderState retains reveal only for the same identity or a
   strict longer source-prefix append; image-only and same-source structural
   replacements derive a fresh 160-unit first slice. The view task is keyed by
   this stored identity.
2. SourcePresentation has a stored immutable UUID content key, excluded from
   semantic Equatable comparison. Slicing explicitly preserves that key.
   SourceCard captures it once for its body, task, and row cache lookups.
3. SourceLine retains raw text and offers a capped character probe.
   SourcePageLoader probes at most 2,049 characters on the main actor before
   sync priming a safe line; detached page work alone reads raw overflow lines.
   The 200-row, 16,384-total-character, and 2,048-per-line ceilings remain
   exact.

### RED

Added image-only and same-source structural replacement tests, source-key
preservation, a 4,000,000-character first-line test, and an exact 201-line
sync-prime cap test before implementation. The first focused RED run failed at
/tmp/10x-task4-fix2-red.log because the new test lacked Foundation for Data;
after correcting that test import, the production contract RED at
/tmp/10x-task4-fix2-red-structure.log failed because
SourceLine.characterCount(cappedAt:) did not yet exist.

### GREEN and verification

Focused state/loader/slicer run passed 14 tests. Relevant snapshot run passed
1 document snapshot, 4 renderer pagination snapshots, and 15 ViewSnapshot
tests. The full suite passed 1,146 tests in 24 suites. The multi-megabyte test
proves zero sync tokenizer calls/cache entries, an exact 2,049-character
bounded probe, and one later detached tokenizer call. The 201-row test proves
exactly 200 sync cache/tokenizer entries and no row-201 tokenization. No
snapshot reference changed.

Exact commands: xcodebuild test -project 10x.xcodeproj -scheme 10x -destination platform=macOS;
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination platform=macOS;
ruby scripts/generate_xcodeproj.rb; git diff --check. The Release build and
generator/diff checks passed after the final implementation change.

### Self-review

- The structural fingerprint combines block tags, content, and collection
  counts, including image data/mime type and nested list/table/quote shape.
  View-path comparisons are O(1); the only source scan is the strict
  append-prefix check.
- UUID cache keys never concatenate or hash hidden source text in SwiftUI
  body. Source replacement cancels and rejects stale loader publication by key
  and task UUID.
- The bounded probe walks no more than its supplied cap. Sync tokenization
  happens only after a line is known to be at most 2,048 characters.

## Fix Round 3

### Findings addressed

1. ContentDocument now carries a stored UUID renderVersion, rather than a
   payload hash. It is ignored by semantic Equatable comparison, preserved by
   every document slice, and used for state/task identity. Only the same
   version or a strict longer source prefix retains an existing document
   reveal.
2. SourceLineView now owns a 2,048/2,048 line-local ProgressiveReveal. Its
   production SourceLineRenderPresentation prefixes span values without
   materializing the whole line, makes a finite accessibility string with a
   truncation cue, and gives the next action a finite 2,048-character page.
   SourceCard keys every line view by source UUID plus line number.

### RED

Added document-version propagation/state tests, span-boundary rendering,
4,000,000-character pure page tests, and a 100,000-character mounted
SourceCard regression before production changes. The initial focused run at
/tmp/10x-task4-fix3-red.log failed as expected because
SourceLineRenderPresentation did not exist.

### GREEN and verification

ContentRenderSliceTests and SourceSurfaceTests passed 12 tests in 2 suites at
/tmp/10x-task4-fix3-focused.log. The expanded focused state/source/loader run
passed 19 tests in 3 suites at /tmp/10x-task4-fix3-focused-all.log. Relevant
ViewSnapshotTests and RendererPaginationTests passed 19 tests in 2 suites at
/tmp/10x-task4-fix3-snapshots.log, with no reference or asset changes. The
full suite passed 1,151 tests in 25 suites at
/tmp/10x-task4-fix3-full-suite.log.

The final Release build passed at /tmp/10x-task4-fix3-release-build.log.
After that build, ruby scripts/generate_xcodeproj.rb and git diff --check
passed; the generator added only SourceSurfaceTests.swift entries.

### Self-review

- Version equality is collision-safe UUID equality. Reconstructed identical
  documents are allowed to reset instead of accidentally retaining expansion.
- The 4,000,000-character source test verifies an initial representation no
  larger than 2,048 characters and a one-page representation no larger than
  4,096; the mounted SourceCard test renders a production card with a
  100,000-character line without creating a large snapshot asset.
- SourceLineRenderPresentation only joins its already prefix-bounded spans;
  accessibility never reads SourceLine.plainText. The existing full source
  payload remains bound to Copy.
