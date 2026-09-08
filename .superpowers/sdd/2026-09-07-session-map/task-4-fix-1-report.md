# Task 4 fix 1 report

## Status

DONE

## Review findings addressed

- Every graph card now includes compact status text plus a distinct non-color mark. Proposed uses a plus, Planned uses a list, Exists retains the dashed border and hollow circle, Active uses cyan, Done uses a check, and Failed uses the error mark and red outline.
- Node measurement and rendering now share `SessionMapNodeView.renderedSubtitle(for:)`. Measurement includes the complete `kind · group` subtitle and the new compact status row.
- Active nodes append `Live activity` to their accessibility label. The same active-node fact is passed to the native graph button and the native relationship list so both accessible representations agree.
- `isActive` changes now update pulse state while retaining the Reduce Motion guard.
- The graph fixture adds a Proposed node and file-targeted Done evidence for its file-bearing document node. The existing label evidence remains for other fixture consumers. A focused test proves the validated fixture contains all six statuses.
- Corrected the original Task 4 report: shell focus and VoiceOver driving belongs to Task 6; transcript Jump navigation and Reduce Motion behavior belongs to Task 12.

## TDD evidence

### RED

Command:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/10x-f59a-session-map-derived -only-testing:'TenXAppTests/sessionMapGroupedNodeMeasurementIncludesRenderedSubtitle()' -only-testing:'TenXAppTests/sessionMapGraphFixtureCoversEveryNodeStatus()' -only-testing:'TenXAppTests/sessionMapAccessibilityDistinguishesLiveActivity()'
```

Log: `/tmp/10x-f59a-session-map-task4-fix1-red.log`

Result: 3 tests executed and all 3 failed at assertions. The old measurement returned 104 points below the required 112-point fixture bound; the parsed fixture contained only Exists, Planned, Active and Failed; and active accessibility omitted `Live activity`.

### GREEN

Command:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/10x-f59a-session-map-derived -only-testing:'TenXAppTests/sessionMapFocusHighlightsOnlyDirectConnections()' -only-testing:'TenXAppTests/sessionMapWalkthroughKeepsFocusAfterStatusUpdate()' -only-testing:'TenXAppTests/sessionMapRemovedFlowStepResetsSelection()' -only-testing:'TenXAppTests/sessionMapAccessibilityNamesRelationshipsWithoutNodeIDs()' -only-testing:'TenXAppTests/sessionMapGroupedNodeMeasurementIncludesRenderedSubtitle()' -only-testing:'TenXAppTests/sessionMapGraphFixtureCoversEveryNodeStatus()' -only-testing:'TenXAppTests/sessionMapAccessibilityDistinguishesLiveActivity()'
```

Log: `/tmp/10x-f59a-session-map-task4-fix1-interaction-green-final.log`

Result: 7 tests executed, 7 passed, 0 issues.

Snapshot command:

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/10x-f59a-session-map-derived -only-testing:'TenXAppTests/sessionMapGraphSnapshots()'
```

Log: `/tmp/10x-f59a-session-map-task4-fix1-snapshot-green-final.log`

Result: 1 test executed, 8 references compared, 1 test passed, 0 issues. Logs contain only the known AppIntents/linkd host noise.

## Native image inspection

All eight updated `.actual.png` candidates were inspected before promotion by the implementer and controller. Both inspections confirmed visible status text, distinct Proposed/Planned marks, actual Done rendering, fitted label/subtitle/status rows, and readable dimmed-node text in both appearances.

Promoted references:

- `Tests/TenXAppTests/ReferenceImages/session-map-graph-normal.png`
- `Tests/TenXAppTests/ReferenceImages/session-map-graph-normal-dark.png`
- `Tests/TenXAppTests/ReferenceImages/session-map-graph-hover.png`
- `Tests/TenXAppTests/ReferenceImages/session-map-graph-hover-dark.png`
- `Tests/TenXAppTests/ReferenceImages/session-map-graph-focused.png`
- `Tests/TenXAppTests/ReferenceImages/session-map-graph-focused-dark.png`
- `Tests/TenXAppTests/ReferenceImages/session-map-graph-walkthrough.png`
- `Tests/TenXAppTests/ReferenceImages/session-map-graph-walkthrough-dark.png`

Each reference is 880 × 1640 pixels at 2× backing scale for a 440 × 820 point view.

## Files changed

- `App/SessionMap/SessionMapNodeView.swift`
- `App/SessionMap/SessionMapInteraction.swift`
- `App/SessionMap/SessionMapGraphView.swift`
- `App/SessionMap/SessionMapFixtures.swift`
- `Tests/TenXAppTests/SessionMapInteractionTests.swift`
- Eight existing `Tests/TenXAppTests/ReferenceImages/session-map-graph-*.png` files
- `.superpowers/sdd/2026-09-07-session-map/task-4-report.md`
- `.superpowers/sdd/2026-09-07-session-map/task-4-fix-1-report.md`

No source or test file was added, so the generated Xcode project did not require regeneration.

## Self-review

- Confirmed node label and subtitle text retain their normal readable foreground while only status marks, outlines and unrelated edges dim.
- Confirmed the live activity marker remains separate from model-authored status both visually and semantically.
- Confirmed the defaulted `isActive` parameter preserves existing accessibility-label call sites and outputs.
- Confirmed fixture validation uses correct file evidence without weakening validator rules.
- `git diff --check` passed. The focused source scan found no `any`/`as` casts or banned UI copy.

## Deferred checks

Task 6 owns real shell focus and VoiceOver driving. Task 12 owns real transcript Jump navigation and Reduce Motion behavior for that jump.
