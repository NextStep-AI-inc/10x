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

## Fix Round 4

### Findings addressed

1. ContentDocument now carries collision-safe immediate-predecessor lineage in
   addition to its render UUID. TranscriptReducer snapshots the document for
   each stable message/segment ID before normalizing an inflight replacement.
   Identical semantic documents reuse the previous version, strict appends name
   exactly that previous version, and replacements start a lineage with no
   predecessor. ContentDocumentRenderState therefore decides in O(1): retain
   for the same version or its recorded immediate predecessor, otherwise reset
   to 160 units.
2. Source-line disclosure now probes only through current limit plus one page
   plus one character. A 2,049-character line advertises exactly one remaining
   character, while longer lines advertise at most the 2,048-character next
   page. The finite row label is applied to the row HStack only; the progressive
   reveal button remains its separately focusable, quantity-specific sibling.

### RED

The focused RED run at /tmp/10x-task4-fix4-red.log failed with the new lineage
regressions because ContentDocument had neither predecessorRenderVersion nor
assigningRenderLineage(after:). The tests were written before the production
implementation and cover skipped versus persisted immediate predecessors,
rapid inflight suffix replacement, exact stable segment identities, identical
finalization, exact 2,049-character disclosure, and bounded longer-line totals.

### GREEN and verification

ContentRenderSliceTests and SourceSurfaceTests passed 19 tests in 2 suites at
/tmp/10x-task4-fix4-focused.log. Relevant ViewSnapshotTests and
RendererPaginationTests passed 19 tests in 2 suites at
/tmp/10x-task4-fix4-snapshots.log, with no reference or asset changes. The full
suite passed 1,158 tests in 25 suites at
/tmp/10x-task4-fix4-full-suite.log. The Release build passed at
/tmp/10x-task4-fix4-release-build.log. After the build,
bundle exec ruby scripts/generate_xcodeproj.rb, a byte-diff check of
project.pbxproj, and git diff --check all passed; the generated project was
unchanged.

The mounted production SourceCard regression remains green for a
100,000-character line. A bounded AppKit fallback using both
accessibilityChildren and accessibilityChildrenInNavigationOrder exposed no
mounted descendants from NSHostingView, including after attaching it to an
NSWindow. Per the review stop condition, the hierarchy contract is additionally
covered by the pure finite row-label and quantity-specific button-label/count
assertion; no unreliable host-introspection assertion remains.

### Self-review

- Semantic Equatable behavior is unchanged: render UUID and predecessor UUID
  do not participate. Slices explicitly preserve both values.
- Full semantic and source-prefix comparisons occur only while constructing a
  replacement document. SwiftUI reconciliation performs UUID comparisons only
  and cannot infer lineage from task ordering.
- Segment lineage is keyed by the normalizer's existing stable message IDs, so
  each visible segment can only inherit from the same prior segment. A topology
  change that changes segment ordinal intentionally starts fresh rather than
  inheriting unrelated reveal state.
- The Release build still emits existing Swift concurrency warnings in
  MessageBlockView and ModelPickerFlyout; this round introduced no new build
  warnings.

## Fix Round 5

### Finding addressed

Normalized visible text runs now carry a collision-safe
`TranscriptRenderLineageKey` containing the base message ID and the typed
optional IDs of their immediate preceding and following tool-call boundaries.
The no-tool case uses the stable `(base message, nil, nil)` key. Ordinal message
IDs remain the UI identity only. `TranscriptReducer` snapshots prior documents
by the separate lineage key, and the normalizer can assign a predecessor only
after an exact key lookup. Adjacent tool insertion, removal, reordering, or ID
replacement therefore resets conservatively instead of transferring expansion
to an unrelated ordinal segment.

The lineage key is stored on `TranscriptMessage` but excluded from semantic
message equality, matching the existing treatment of document render UUIDs.
Stable surrounding boundaries retain immediate predecessor lineage during a
streaming append, and the existing UI segment IDs remain unchanged.

### RED

The regression was added before production changes. This command failed at
`/tmp/10x-task4-fix5-red.log`:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/toolTopologyInsertionDoesNotTransferLineageToReusedOrdinalSegmentID()'
```

The reused `assistant-1-segment-1` incorrectly received the prior occupant's
render UUID and retained a 320-unit reveal limit instead of having no
predecessor and resetting to 160. The result bundle is
`~/Library/Developer/Xcode/DerivedData/10x-bxbthukntyhepwdxepxgagdrmozo/Logs/Test/Test-10x-2026.09.01_20-16-27--0700.xcresult`.

### GREEN and verification

The final focused normalizer, reducer, semantic-equality, and content-state run
passed 16 tests at `/tmp/10x-task4-fix5-focused-final.log`:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/toolTopologyInsertionDoesNotTransferLineageToReusedOrdinalSegmentID()' '-only-testing:TenXAppTests/inflightSegmentsAssignLineageByStableToolBoundaries()' '-only-testing:TenXAppTests/rapidInflightReplacementUsesOnlyItsImmediateSemanticPredecessor()' '-only-testing:TenXAppTests/identicalInflightFinalizationReusesTheDocumentVersion()' '-only-testing:TenXAppTests/renderLineageKeyDoesNotChangeMessageSemanticEquality()' '-only-testing:TenXAppTests/normalizerPreservesTextToolTextOrder()' '-only-testing:TenXAppTests/ContentRenderSliceTests'
```

The relevant renderer and document snapshot suites passed 19 tests with no
reference or asset changes at `/tmp/10x-task4-fix5-snapshots.log`:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' '-only-testing:TenXAppTests/ViewSnapshotTests' '-only-testing:TenXAppTests/RendererPaginationTests'
```

The full suite passed 1,160 tests in 25 suites at
`/tmp/10x-task4-fix5-full-suite.log`, and the universal Release build passed at
`/tmp/10x-task4-fix5-release-build.log`:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'
xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS'
```

Finally, `bundle exec ruby scripts/generate_xcodeproj.rb`, a byte-hash check of
`10x.xcodeproj/project.pbxproj`, and `git diff --check` passed. The generated
project remained unchanged at SHA-1
`cc03cf8cd6586bb37efafe8786bb81e9476fd78f`.

### Self-review

- The lineage key is a typed three-field value, not a concatenated string or
  payload hash. Nil boundaries cannot alias tool IDs, and dictionary hash
  collisions still require exact structural equality.
- The normalizer advances the preceding boundary only for tool calls it
  actually emits, so duplicate or malformed tool blocks do not create phantom
  render boundaries.
- The topology-shift regression uses a strict source-prefix append and proves
  both nil predecessor assignment and the 320-to-160 render-state reset. The
  stable-boundary regression proves both adjacent runs retain their immediate
  predecessors while their ordinal UI IDs stay fixed.
- No source-line code or snapshot reference was changed. The Release build
  still reports the previously documented MessageBlockView and
  ModelPickerFlyout concurrency warnings; this round added no warnings.
