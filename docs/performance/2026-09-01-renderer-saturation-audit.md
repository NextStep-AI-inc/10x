# Renderer saturation audit

Date: 2026-09-01
Baseline: `origin/main` at `d52f6dc`
Scope: SwiftUI surfaces that render data whose size or update rate is controlled by sessions, tools, providers, subprocesses, or stored user content.

## Incident evidence

The frozen process was the exact Release app built from `d52f6dc`, not an older app instance.

| Signal | Captured value |
| --- | --- |
| Process | PID 6567 from `/private/tmp/tenx-skill-completion-d52f6dc-release/.../10x` |
| CPU before sampling | 99.1% |
| RSS before sampling | approximately 624 MB |
| Physical footprint in `sample` | 905.1 MB |
| Main-thread samples | 1,408 of 1,408 inside the SwiftUI run-loop observer |
| SwiftUI graph flushes | 1,401 samples |
| AttributeGraph subgraph updates | 1,183 samples |
| Dominant work | recursive `LayoutEngineBox.sizeThatFits`, flex-frame, stack, styled-text, and lazy-list layout |
| Triggering displayed message | one `custom` / `skill-prompt` message, approximately 3.4 KB, followed by streaming output |

The stack is a renderer/layout storm. It is not a provider wait, socket loop, disk read, or model-side stall. The screenshot also showed Jump to latest, proving automatic following had already fallen behind while layout continued consuming the main thread.

## Root causes fixed in PR #18

```text
complete skill message
        |
        v
one unbounded selectable Text ----> laid out again for later stream snapshots
        |                                      |
        +------------------+-------------------+
                           v
             overlapping animated scroll/layout
                           |
                           v
                 AttributeGraph saturation
```

| Root cause | Previous behavior | Fix |
| --- | --- | --- |
| Displayed skill boundary | A full displayed custom `message_start` remained inflight and could be replaced by the following assistant start. | Displayed `custom` and `hookMessage` entries are complete at start, retained as a final row, and inserted before later output. |
| Unbounded raw text node | User and custom messages used one selectable, vertically fixed `Text`, regardless of size. | Plain transcript text is divided into lossless nodes capped at 1,024 characters while remaining one transcript row. |
| Stable-row invalidation | Custom messages and tool cards were rebuilt when unrelated transcript rows changed. | Message and tool views now have equatable render boundaries based on their rendered inputs. |
| Scroll animation overlap | Transcript publications can arrive every 50 ms while each automatic follow animation lasts 150 ms. | Automatic following is immediate. Only the explicit Jump to latest action animates. |

These are shared transcript fixes. They cover a large skill block, a large pasted user message, stable completed tool cards above a streaming answer, and any other raw custom/hook message.

## Historical pre-follow-up surface inventory

The inventory and R1–R6 findings below record the state immediately after the shared PR #18 transcript fix and before renderer-hardening Tasks 2–7. They are retained as incident context, not as claims about the current product. The post-hardening disposition for every finding follows this historical section.

### Baseline protections recorded before Tasks 2–7

| Surface | Guardrail at that point | Residual risk at that point |
| --- | --- | --- |
| Transcript container | Top-level `LazyVStack`; event snapshots coalesced to a 50 ms publication interval. | The row array is still normalized for each accepted snapshot, but expensive stable row bodies are isolated. |
| Raw user/custom messages | New 1,024-character text-node budget and equatable message boundary. | An intentionally unbroken token may gain a visual wrap at a segment boundary; source text remains exact and selectable. |
| Assistant prose | Semantic document blocks plus existing equatable assistant-content boundary. | A single enormous Markdown list/table or code fence can still create many child views. |
| Source tool output | Tool extractors usually request 12- or 20-line previews; source is rendered per line. | Assistant-authored fenced code has no preview limit. |
| Console output | Ten-line preview before Show all. | Show all is intentionally unbounded after explicit user action. |
| Tool collections | Eight-item preview before Show all. | Individual item detail strings can still be large. |
| JSON/data tree | Depth capped at 6, children previewed at 12, scalar text initially limited to 4 lines. | Show all can still expand a large branch by explicit action. |
| Message/tool images | Display size capped at 420×320 for messages and 200 points high for tool media. | Decode work is not cached; see finding R2. |
| Command browser | `LazyVStack`, one-line result rows, and a bounded panel. | Fuzzy ranking cost belongs to the command model, not SwiftUI layout. |
| Session search | Results capped at 200, shown in a `LazyVStack`; excerpts capped at 180 characters. | No renderer saturation path found. |
| Active/archived session lists | Lazy stacks and one-line labels; the rail collapses older sessions behind disclosure rows. | No unbounded text surface found. |

### Risks recorded before Tasks 2–7

| ID | Risk at that point | Historical code evidence | Severity | Historical recommendation |
| --- | --- | --- | --- | --- |
| R1 | Large expanded diffs can build and syntax-tokenize every visible changed line. Completed edit/AST-edit cards start expanded. | `DiffView.lineView` calls `SourceTokenizer.spans` from `body`; unchanged lines collapse, changed lines do not. | Medium | Add a changed-line preview budget and pre-tokenize into the presentation model in a focused diff-performance PR. The new tool-card equality boundary already prevents unrelated stream updates from repeating this work. |
| R2 | Tool media decodes base64 and constructs `NSImage` from computed view properties. Multiple property reads can repeat decode work on body evaluation. | `MediaItemView.decodedData` and `localImage` are computed under `body`. | Medium | Decode once when the immutable media item changes and hold the result in a small presentation value. Verify with a multi-megabyte image fixture before changing. |
| R3 | Active provider wheels deliberately redraw at 30 FPS. | `ProviderUsageWheelView` uses `TimelineView(.animation(minimumInterval: 1 / 30))` whenever `activeCount > 0`. | Medium-low | Profile the packaged app after the transcript fix. If the wheel consumes material idle CPU, replace the continuous sine pulse with a lower-frequency phase animation or pause it while the app is inactive. |
| R4 | The onboarding installer keeps every output line in state, renders them in a non-lazy `VStack`, and scrolls after every append. | `OnboardingInstallStepView.logView` uses `VStack` over the full `log`; `install()` appends every subprocess line. | Medium | Switch to `LazyVStack`, batch UI publication, and keep a bounded visible tail while retaining the full copyable log outside view state. |
| R5 | Rich Markdown lists, tables, quotes, and assistant code fences have no initial child-count preview. | `ContentListView`, `ContentTableView`, nested quote blocks, and `CodeBlockView` enumerate all parsed children. | Medium | Add block-specific preview disclosure only after reproducing a slow real payload. Do not globally truncate assistant responses. |
| R6 | Expanding Show all for console, collections, source, or JSON explicitly removes the preview bound. | Each surface switches from prefix/depth preview to the full collection after user action. | Low | Treat this as an explicit escape hatch. Add staged expansion only if an actual large payload remains unresponsive after user-triggered expansion. |

## Historical reason these risks were not folded into the shared transcript fix

R1–R6 were not on the captured hot stack at a distinguishable application symbol, and each required a different correct ceiling. Folding them into PR #18 without dedicated fixtures would have risked truncating useful output, weakening copy behavior, or degrading intentional animations. Tasks 2–7 subsequently added the focused safeguards and fixtures summarized below.

## Post-hardening resolution of R1–R6

| ID | Follow-up | Current safeguard | Status and residual |
| --- | --- | --- | --- |
| R1 | Task 3 | Diff presentation reveals changed lines globally in stages of 200. Visible-line tokenization uses a detached, cancellable cache; synchronous work is capped at 200 rows, 16,384 total characters, and 2,048 characters per line. Hidden rows perform no tokenization, and the exact raw diff remains retained. | Resolved for changed-row count and tokenization saturation. **Open:** one oversized visible diff line is not yet character-paged for display; the fixture's token cap does not prove that visible-string case fixed. |
| R2 | Task 5 | `ToolMediaLoader` performs one detached eager ImageIO decode per immutable content identity, cancels obsolete work, caches the stable result, and reconciles media generations semantically. | Resolved. The 5 MiB fixture proves one decode across two loads while retaining the complete encoded and decoded payloads. |
| R3 | Task 6 | The 30 FPS `TimelineView` was removed. Provider-wheel animation now runs at a one-second cadence only with active providers, an active scene, and reduced motion disabled, and stops on disappearance. | Resolved for continuous idle redraw. The exact packaged app also returned 0.0% CPU in all ten exercised samples; that launch did not separately force an active-provider animation state. |
| R4 | Task 7 | Installer output is retained in an observable buffer outside published view state, published in 100 ms batches, rendered in a `LazyVStack`, and exposed through a staged 200-line tail while preserving stable IDs and complete copy text. | Resolved for per-line publication, unbounded eager rendering, and scroll churn. Retaining the full copyable log is intentional. |
| R5 | Task 4 | Mixed Markdown and source share a global 160-unit initial/page budget. Source highlighting loads only visible lines through a detached, cancellable cache with the same synchronous token caps as diffs; source lines reveal characters in 2,048-character stages while raw content and streaming lineage remain intact. | Resolved for unbounded document-child and source-line work. The 5,000-unit fixture proves the global budget, hidden-work exclusion, and full retention. |
| R6 | Task 2, with Tasks 3, 4, and 7 for specialized surfaces | One-shot **Show all** expansion was replaced with staged policies: console 10/100, collections 8/50, JSON children 12/50, JSON scalars 2,000/4,000, source 200/200, diffs 200/200, documents 160/160, and installer tails 200/200. | Resolved for collection-, child-, scalar-, line-, and unit-count expansion. **Open:** one oversized visible console string is not character-paged; the console fixture proves line-count paging, not a per-line character ceiling. The diff single-line exception is recorded under R1. |

The open diff and console cases are deliberately not marked fixed by this audit. Their current paging controls bound the number of visible records, but not the display cost of one exceptionally large visible string.

## Verification gate

The fix is not considered verified until a fresh Release artifact demonstrates all of the following:

1. A skill-sized displayed custom message appears completely before assistant output.
2. The message retains the current raw monospace appearance and selectable text.
3. Streaming output remains interactive while the skill block is on screen.
4. CPU falls back toward idle after publications stop.
5. The main-thread sample no longer spends the entire interval in recursive transcript layout.

## Task 8 automated saturation gate

Run on 2026-09-02 from Task 7 HEAD `ee58292` plus the Task 8 fixture and audit changes. The fixtures use production presentations, pagination policies, page loaders, the media loader, and the installer buffer. They make no wall-clock assertions and do not construct giant SwiftUI snapshot trees.

| Fixture | Exact automated boundary proved |
| --- | --- |
| Diff | 10 files and 10,000 changed lines; 200 initial and 400 after one reveal; synchronous token cache/calls stay at zero for the oversized first line; detached cache/calls are exactly 200 then 400, stay off-main, exclude hidden rows, and retain the exact raw diff. This proves the tokenization ceiling, not display-character paging for one oversized visible diff line. |
| Console | 10,000 lines; 10 initial and 110 after one reveal; the complete copy payload remains exact. This proves line-count paging, not a character ceiling for one oversized visible console line. |
| Collection | 1,000 entries; 8 initial and 58 after one reveal; the final retained item remains available. |
| JSON | 5,000 object children and a 100,000-character scalar; children reveal 12 then 62, scalar characters reveal 2,000 then 6,000, maximum depth remains 6, and full retained values remain available. |
| Mixed document | Exactly 5,000 combined source/list/quote/table units; the global slice is 160 then 320. Source highlighting has zero synchronous calls for the oversized first line, then exactly 160 and 320 detached off-main calls with hidden lines excluded; the 10,000-character source row reveals 2,048 then 4,096 characters while full source text remains retained. |
| Inline media | One immutable 5 MiB media item; zero decode calls before load, one detached decode across two loads, one stable loaded item ID, and the complete encoded and decoded payloads remain retained. |
| Installer | 10,000 appended lines schedule one batch and publish no state before flush; the visible tail is exactly 200 then 400 with stable absolute IDs, and all 10,000 lines remain in `completeText`. |

### Automated evidence

| Check | Result |
| --- | --- |
| TDD missing-suite RED | One intentional failing placeholder test recorded `Task 8 oversized renderer fixtures are missing`; `/tmp/tenx-task8-red.log`. |
| Final Debug fixture suite | 7 tests in 1 suite passed in 0.108 seconds; `/tmp/tenx-task8-debug-fixtures-postreview.log`. |
| Release-configured fixture suite | 7 tests in 1 suite passed in 0.075 seconds under Release `-O -whole-module-optimization`; `/tmp/tenx-task8-release-fixtures-postreview.log`. |
| Complete Debug suite | 1,197 tests in 28 suites passed in 8.493 seconds on the third normal run; `/tmp/tenx-task8-full-suite-rerun-2.log`. A post-review normal run and the requested serial diagnostic are recorded below. |
| Universal Release build | Clean build succeeded at `/private/tmp/tenx-renderer-hardening-release/Build/Products/Release/10x.app`; executable architectures are `x86_64 arm64`; `/tmp/tenx-task8-universal-release-build.log`. |
| Artifact SHA-256 | `d5527bdbb9678cfc7c03128a222a248f3fc7c7a47dc7adbafa5515c763c91f30` for `10x.app/Contents/MacOS/10x`. |
| Signing | `codesign --verify --deep --strict` passed for the exact app. Identity is `Developer ID Application: NextStep AI Inc. (345S42BKPY)`, Team ID `345S42BKPY`, hardened runtime 26.5.0. |
| Project generation | Two consecutive generator runs produced project SHA-1 `4ba0d09933a23cc361f1936f38a68cf2a48d6803`; the new test adds the expected four generated project lines. |

The first two normal full-suite attempts each reported one different existing concurrency-sensitive failure: `cancelledOldTokenizationCannotPublishIntoReplacementContent()` could not start its gate under the fully parallel load, then `controllerReportsProviderAndRuntimeTransitionsFromRPCLifecycle()` missed an async retained-provider expectation. The complete diff presentation suite passed 12 tests in isolation, the Task 8 suite passed in both failed runs, and the third unchanged complete run passed all 1,197 tests. After self-review added only the explicit zero-before-media-load assertion, focused Debug and optimized Release fixtures passed again; a fourth normal full run repeated the existing diff gate timeout (`/tmp/tenx-task8-full-suite-final.log`). The requested `-parallel-testing-enabled NO` diagnostic ran all 1,197 tests serially and found one unrelated snapshot mismatch (`/tmp/tenx-task8-full-suite-serial.log`); that exact snapshot then passed alone as 1 test in 0 suites (`/tmp/tenx-task8-serial-snapshot-isolated.log`). No unrelated code or reference asset was changed.

The unmodified Release test command failed because the shipping module correctly disables testability (`/tmp/tenx-task8-release-fixtures.log`). `ENABLE_TESTABILITY=YES` alone then exposed existing tests that reference DEBUG-only Composer hooks (`/tmp/tenx-task8-release-fixtures-testable.log`). Adding the ledger-approved command-line-only DEBUG compilation condition compiled optimized code but initially left the host and test bundle with different Team IDs (`/tmp/tenx-task8-release-fixtures-optimized.log`). An ad-hoc signing probe aligned those two but conflicted with Sparkle library validation (`/tmp/tenx-task8-release-fixtures-optimized-adhoc.log`). The final optimized test host used the ledger-approved existing Developer ID identity for every copied test component. The exact standalone app was then clean-built without `ENABLE_TESTABILITY`, `DEBUG`, or a signing override.

### Exact-app launch evidence

The controller launched the exact signed Release artifact at `/private/tmp/tenx-renderer-hardening-release/Build/Products/Release/10x.app` from product commit `059d578823cba504a139fbdff29dbb08973c68fe`. The running executable path matched that artifact, its SHA-256 remained `d5527bdbb9678cfc7c03128a222a248f3fc7c7a47dc7adbafa5515c763c91f30`, and PID 29413 survived the verification flow.

Computer Use first confirmed a rendered update prompt. After selecting **Not now**, it confirmed a rendered workspace window and opened a persisted session containing expanded and collapsed tool history. Five two-second idle samples each reported 0.0% CPU with RSS between approximately 106,240 and 106,320 KB. After loading the persisted tool session, five further two-second samples each reported 0.0% CPU with RSS between approximately 147,856 and 148,320 KB. There was no persistent hot main thread, so the conditional one-second stack sample was not triggered.

This verifies that the exact packaged app renders its update and workspace surfaces, remains alive, and returns to idle both before and after loading persisted tool history. The available persisted session did not contain the original oversized superpowers skill block, so verification-gate items 1–3 were not reproduced manually with that exact shape. Item 4 is satisfied for the exercised persisted content. Item 5 was not directly stack-sampled because CPU never became persistently hot. The optimized production-boundary fixtures remain the deterministic coverage for the artificial saturation shapes; no shipping fixture hook was added.
