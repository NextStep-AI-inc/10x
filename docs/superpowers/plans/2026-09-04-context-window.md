# Context Window Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development for bounded UI and parser work; parent integrates and verifies.

**Goal:** Implement the approved compact context meter beside the active-session model selector and a detailed usage popover, plus the three pending interaction corrections.

**Architecture:** Read totals from OMP `get_state.contextUsage`. Request the built-in `/context` report only on opening details, route its output through the existing single event reader, and parse the known category contract conservatively. Treat report failure as a local detail error; never fail a running session or invent categories. Protect asynchronous results with the existing pipeline generation and an event fence. Keep the runtime/dependencies unchanged.

**Tech Stack:** SwiftUI, Observation, OmpKit RPC, Swift Testing, Xcode Release build.

## Tasks
- [ ] Typed data and focused tests: `App/Sessions/SessionContextUsage.swift`, `Tests/TenXAppTests/SessionContextUsageTests.swift`. Validate counts/capacity, use percent units correctly, retain overflow truth, parse the installed report's known labels and omitted zero categories. Malformed/changed reports produce unavailable details.
- [ ] UI: `App/Sessions/ContextUsageControl.swift` and `ContextUsagePopover.swift`. Match approved preview with four-bar compact label, native popover, total/capacity, remaining, five category rows, estimate/freshness, and local loading/retry states.
- [ ] Integration: `SessionController.swift`, `ComposerView.swift`. Refresh totals at lifecycle boundaries without applying stale runtime state. Clear obsolete breakdowns. Retrieve report without composer bubbles, draft changes, model calls, or transcript pollution. Keep generation fences and bounded requests.
- [ ] Pending corrections: rings → steer/follow up → send; remove question eyebrow; read/historical sessions black, observed background completion blue until read, yellow input, red error.
- [ ] Regenerate project with `ruby scripts/generate_xcodeproj.rb`; run meaningful parser/controller/read-state checks and full affected snapshot suite. Inspect changed images before accepting baselines.
- [ ] Build Release, diagnose prior runtime startup block before a fresh verification launch, then click the actual compact control in the packaged application and capture evidence. Verify real provider behavior where context differs; explicitly report unavailable providers or blocked live flows.
- [ ] Commit implementation and evidence notes; update existing PR #22 without merging. Include unverified scope honestly.

## Checks
`xcodebuild test -project 10x.xcodeproj -scheme 10x -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/10x-interaction-tests ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO`

`xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/10x-interaction-release-final ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER=com.tannerpham.tenx.interactionimprovements`
