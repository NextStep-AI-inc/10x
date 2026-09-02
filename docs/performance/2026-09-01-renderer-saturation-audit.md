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
| R1 | Task 3 plus follow-ups `bcd4007`, `8267358`, `3a06598`, and `4aa087c` | Diff presentation reveals changed lines globally in stages of 200. Visible-line tokenization uses a detached, cancellable cache; synchronous and asynchronous work are each capped at 200 rows, 16,384 total characters, and 2,048 characters per line. Oversized individual lines remain plain instead of entering the tokenizer. Hidden rows perform no tokenization, and each body pass slices only through the visible prefix rather than rebuilding the complete hidden row array. Context disclosure adds exactly the newly requested context count to the global budget, preserving already visible changed lines across multiple collapsed blocks without revealing an extra changed tail. Shared `ProgressiveTextPresentation` limits each visible diff string and its accessibility value to 2,048 characters initially and adds 4,000 per action. Equivalent refreshed payloads keep their O(1) render UUID. | Resolved for changed-row count, multi-context accounting, tokenization, hidden-row materialization, render identity, and single-visible-string saturation. The exact raw diff remains retained, and **Copy patch** continues to use that complete payload rather than the displayed prefix. |
| R2 | Task 5 | `ToolMediaLoader` performs one detached eager ImageIO decode per immutable content identity, cancels obsolete work, caches the stable result, and reconciles media generations semantically. | Resolved. The 5 MiB fixture proves one decode across two loads while retaining the complete encoded and decoded payloads. |
| R3 | Task 6 | The 30 FPS `TimelineView` was removed. Provider-wheel animation now runs at a one-second cadence only with active providers, an active scene, and reduced motion disabled, and stops on disappearance. | Resolved for continuous idle redraw. The exact packaged app also returned 0.0% CPU in all ten exercised samples; that launch did not separately force an active-provider animation state. |
| R4 | Task 7 | Installer output is retained in an observable buffer outside published view state, published in 100 ms batches, rendered in a `LazyVStack`, and exposed through a staged 200-line tail while preserving stable IDs and complete copy text. | Resolved for per-line publication, unbounded eager rendering, and scroll churn. Retaining the full copyable log is intentional. |
| R5 | Task 4 plus follow-ups `3a06598` and `4aa087c` | Mixed Markdown and source share a global 160-unit initial/page budget. Source highlighting loads only visible lines through a detached, cancellable cache with the same synchronous and asynchronous token caps as diffs; oversized individual lines remain plain. Source reveal state is keyed to the content generation, equivalent refreshed payloads keep that generation, replacements return to the initial page before their visible slice is derived, and fully expanded documents retain a **Show fewer** control. Source lines reveal characters in 2,048-character stages while raw content and streaming lineage remain intact. | Resolved for unbounded document-child and source-line work, stale reveal state, redundant refresh tokenization, and recovery from full expansion. The 5,000-unit fixture proves the global budget, hidden-work exclusion, and full retention. |
| R6 | Task 2, Tasks 3, 4, and 7 for specialized surfaces, plus follow-ups `bcd4007`, `a22e7f8`, `8267358`, and `4aa087c` | One-shot **Show all** expansion was replaced with staged policies: console 10/100, collections 8/50, JSON children 12/50, JSON scalars 2,000/4,000, source 200/200, diffs 200/200, documents 160/160, and installer tails 200/200. Shared tool strings use the independent `ProgressiveTextPresentation` budget of 2,048 characters initially and 4,000 per action. `ConsoleRenderPresentation` takes the bounded prefix before body materialization: its initial probe is at most 6,049 characters and 111 lines. `DataScalarRenderPresentation` likewise derives the JSON disclosure total from a bounded probe instead of `text.count`. Progress history independently reveals 8 entries initially and 50 per action. Shared disclosure copy pluralizes the final unit while retaining localized number grouping. | Resolved for collection-, history-, child-, scalar-, line-, unit-, producer-preprocessing-, and single-visible-string expansion. Console line reveal (10 initial, +100 per action) and character reveal (2,048 initial, +4,000 per action) are independent; display and accessibility stay finite while **Copy** retains the exact raw output. |

The diff single-string exception recorded in the first post-hardening review is closed by `bcd4007`. The console display cap added there still split the complete raw output before applying the prefix; `a22e7f8` closes that producer-side preprocessing gap. Record-count paging and character paging remain independent so revealing more rows does not silently remove the per-string display and accessibility ceiling.

Three context-isolated reviewers inspected `084f711` and all requested changes. Follow-up `3a06598` closes every `SHOULD_FIX`: async source/diff tokenization now shares the finite synchronous ceilings, source replacement resets reveal state before rendering, diff slicing no longer materializes all hidden rows during body recomputation, unchanged source/diff refreshes retain render generations, the cancellation test uses a direct start signal instead of main-actor polling, and collapsed-context copy states the actual next page size.

A fresh context-isolated renderer, UI/accessibility, and verification review inspected pushed head `9b6ce13`. Follow-up `4aa087c` closes every unique `SHOULD_FIX` from that round: multiple collapsed diff blocks preserve existing changed lines and reveal their promised page, fully expanded documents retain their collapse control, and the shared visible/accessibility disclosure copy handles singular units without losing localized thousands separators.

## Verification gate

The fix is not considered verified until a fresh Release artifact demonstrates all of the following:

1. A skill-sized displayed custom message appears completely before assistant output.
2. The message retains the current raw monospace appearance and selectable text.
3. Streaming output remains interactive while the skill block is on screen.
4. CPU falls back toward idle after publications stop.
5. The main-thread sample no longer spends the entire interval in recursive transcript layout.

## Task 8 automated saturation gate

The original gate ran on 2026-09-02 from Task 7 HEAD `ee58292` plus the Task 8 fixture and audit changes. Follow-up `bcd4007` expanded the suite from 7 to 11 fixtures for the shared string presentation and independently paged progress history; `a22e7f8` moved console probing and line extraction behind the same finite production presentation; `8267358` added bounded JSON-scalar disclosure probing and an O(1) diff render identity, bringing the suite to 13 fixtures. Review remediation `3a06598` strengthened those same fixtures so oversized visible lines remain outside both synchronous and asynchronous tokenizers. The fixtures use production presentations, pagination policies, page loaders, the media loader, and the installer buffer. They make no wall-clock assertions and do not construct giant SwiftUI snapshot trees.

| Fixture | Exact automated boundary proved |
| --- | --- |
| Diff | 10 files and 10,000 changed lines; 200 initial and 400 after one reveal; synchronous token cache/calls stay at zero for the oversized first line; detached cache/calls are exactly 199 then 399 because that oversized line remains plain. All tokenization stays off-main, excludes hidden rows, and retains the exact raw diff. A separate 100,000-character diff-span fixture proves visible spans and accessibility text stop at 2,048 characters while the full raw value remains retained. The render-identity fixture proves the state/cache identifier is a bounded UUID rather than the raw patch. |
| Console and shared tool strings | 10,000 console lines reveal 10 initially and 110 after one line-page action. Initial `ConsoleRenderPresentation` work inspects/materializes at most 6,049 characters and scans at most 111 lines; one line-page action remains finite and independent of character reveal. A 100,000-character single-line console reveals 2,048 initially and 6,048 after one character-page action, with matching bounded accessibility, while **Copy** retains the exact 100,000-character raw output. A 3,000-character terminal-page fixture proves the reveal total advertises only the actual remainder. |
| Collection | 1,000 entries; 8 initial and 58 after one reveal; the final retained item remains available. |
| Progress history | 1,000 entries; 8 initial and 58 after one reveal through its independent policy; the final retained entry remains available. |
| JSON | 5,000 object children and a 100,000-character scalar; children reveal 12 then 62, scalar characters reveal 2,000 then 6,000, maximum depth remains 6, and full retained values remain available. A 4,000,000-character scalar fixture proves disclosure totals advance through bounded 2,000/+4,000 probes rather than a full `text.count`. |
| Mixed document | Exactly 5,000 combined source/list/quote/table units; the global slice is 160 then 320. Source highlighting has zero synchronous calls for the oversized first line, then exactly 159 and 319 detached off-main calls because that line remains plain; hidden lines stay excluded. The 10,000-character source row reveals 2,048 then 4,096 characters while full source text remains retained. |
| Inline media | One immutable 5 MiB media item; zero decode calls before load, one detached decode across two loads, one stable loaded item ID, and the complete encoded and decoded payloads remain retained. |
| Installer | 10,000 appended lines schedule one batch and publish no state before flush; the visible tail is exactly 200 then 400 with stable absolute IDs, and all 10,000 lines remain in `completeText`. |

### Automated evidence

| Check | Result |
| --- | --- |
| TDD missing-suite RED | One intentional failing placeholder test recorded `Task 8 oversized renderer fixtures are missing`; `/tmp/tenx-task8-red.log`. |
| Initial Task 8 Debug fixture suite | 7 tests in 1 suite passed in 0.108 seconds; `/tmp/tenx-task8-debug-fixtures-postreview.log`. |
| Final post-producer-correction Debug fixture suite | 11 tests in 1 suite passed in 0.105 seconds at `a22e7f8`; `/tmp/tenx-console-bounded-saturation-final.log`. |
| Final fixture suite | 13 tests passed at product commit `8267358`, including the 4,000,000-character JSON scalar and bounded diff-identity regressions; `/tmp/tenx-final-renderer-saturation-after-import.log`. |
| Initial Task 8 Release-configured fixture suite | 7 tests in 1 suite passed in 0.075 seconds under Release `-O -whole-module-optimization`; `/tmp/tenx-task8-release-fixtures-postreview.log`. This fixture host was not rerun after `bcd4007`. |
| Post-string-correction snapshots | 17 existing snapshots passed unchanged at `bcd4007` in two focused runs (8 plus 9); `/tmp/tenx-single-string-snapshots.log` and `/tmp/tenx-single-string-additional-snapshots.log`. After the producer-side correction, 4 focused light/dark snapshots also passed unchanged; `/tmp/tenx-console-bounded-snapshots.log`. |
| Complete Debug suite | 1,197 tests in 28 suites passed in 8.493 seconds on the third normal run; `/tmp/tenx-task8-full-suite-rerun-2.log`. A post-review normal run and the requested serial diagnostic are recorded below. |
| Final complete Debug suite | 1,203 tests in 28 suites passed in 7.903 seconds at product commit `8267358`; `/tmp/tenx-final-full-suite.log`. |
| Independent-review remediation | At product commit `3a06598`, the complete Debug suite passed 1,214 tests in 28 suites with zero failures or skips. Two expected light/dark diff snapshots were visually inspected before promotion; the only change is truthful **Show 2 more unchanged lines** copy. The generated project reproduced byte-for-byte with SHA-1 `4274f80e67022da07f18e7e1b9b9884b57544500`. |
| Final independent-review remediation | At product commit `4aa087c`, 53 focused renderer/document/source/snapshot tests passed, followed by the complete Debug suite: 1,217 tests with zero failures or skips (`Test-10x-2026.09.02_09-13-31--0700.xcresult`). One full-run pagination snapshot variance was isolated to missing number grouping, corrected without promoting an asset, and the unchanged snapshot then passed alone and in the final full suite. Two generator runs again produced project SHA-1 `4274f80e67022da07f18e7e1b9b9884b57544500`. |
| Pre-correction signed universal Release build | Product commit `059d578` clean-built at `/private/tmp/tenx-renderer-hardening-release/Build/Products/Release/10x.app`; executable architectures are `x86_64 arm64`; `/tmp/tenx-task8-universal-release-build.log`. |
| Pre-correction artifact SHA-256 | `d5527bdbb9678cfc7c03128a222a248f3fc7c7a47dc7adbafa5515c763c91f30` for the `059d578` app executable. |
| Pre-correction signing | `codesign --verify --deep --strict` passed for the exact `059d578` app. Identity is `Developer ID Application: NextStep AI Inc. (345S42BKPY)`, Team ID `345S42BKPY`, hardened runtime 26.5.0. |
| Final optimized universal Release compile | At `a22e7f8`, an unsigned Release build compiled both `arm64` and `x86_64`; `/tmp/tenx-console-bounded-release.log`. |
| Developer ID packaging attempts | Developer ID builds after the string corrections failed while signing Sparkle with `errSecInternalComponent`. Direct keychain inspection reports the login keychain is locked; the installed identity remains discoverable. |
| Final local Release artifact | Product commit `8267358` compiled universally (`x86_64 arm64`), was ad-hoc signed locally, and passed `codesign --verify --deep --strict` at `/private/tmp/tenx-renderer-hardening-final-local/Build/Products/Release/10x.app`; executable SHA-256 `67234a15b7ff9f360e8be06c69f3f420f13b91897f99c7c5217dc293bc317e7a`; `/tmp/tenx-final-local-release-build.log`. This is a local test artifact, not a Developer ID distributable. |
| Project generation | Two consecutive final generator runs produced project SHA-1 `4274f80e67022da07f18e7e1b9b9884b57544500`. |

The first two normal full-suite attempts each reported one different existing concurrency-sensitive failure: `cancelledOldTokenizationCannotPublishIntoReplacementContent()` could not start its gate under the fully parallel load, then `controllerReportsProviderAndRuntimeTransitionsFromRPCLifecycle()` missed an async retained-provider expectation. The complete diff presentation suite passed 12 tests in isolation, the Task 8 suite passed in both failed runs, and the third unchanged complete run passed all 1,197 tests. After self-review added only the explicit zero-before-media-load assertion, focused Debug and optimized Release fixtures passed again; a fourth normal full run repeated the existing diff gate timeout (`/tmp/tenx-task8-full-suite-final.log`). The requested `-parallel-testing-enabled NO` diagnostic ran all 1,197 tests serially and found one unrelated snapshot mismatch (`/tmp/tenx-task8-full-suite-serial.log`); that exact snapshot then passed alone as 1 test in 0 suites (`/tmp/tenx-task8-serial-snapshot-isolated.log`). Follow-up `3a06598` replaced the scheduler-sensitive main-actor polling gate with a direct semaphore start signal; the subsequent normal 1,214-test run passed. No unrelated code or reference asset was changed.

The unmodified Release test command failed because the shipping module correctly disables testability (`/tmp/tenx-task8-release-fixtures.log`). `ENABLE_TESTABILITY=YES` alone then exposed existing tests that reference DEBUG-only Composer hooks (`/tmp/tenx-task8-release-fixtures-testable.log`). Adding the ledger-approved command-line-only DEBUG compilation condition compiled optimized code but initially left the host and test bundle with different Team IDs (`/tmp/tenx-task8-release-fixtures-optimized.log`). An ad-hoc signing probe aligned those two but conflicted with Sparkle library validation (`/tmp/tenx-task8-release-fixtures-optimized-adhoc.log`). The final optimized test host used the ledger-approved existing Developer ID identity for every copied test component. The exact standalone app for product commit `059d578` was then clean-built without `ENABLE_TESTABILITY`, `DEBUG`, or a signing override. That signed build predates the later single-string fixes. The final product code has a verified local ad-hoc artifact; a Developer ID distributable still requires unlocking the login keychain.

### Pre-correction exact-app launch evidence

The controller launched the exact signed Release artifact at `/private/tmp/tenx-renderer-hardening-release/Build/Products/Release/10x.app` from product commit `059d578823cba504a139fbdff29dbb08973c68fe`. This evidence predates `bcd4007` and `a22e7f8` and therefore does not verify the shared single-string or bounded console-producer corrections. The running executable path matched that artifact, its SHA-256 remained `d5527bdbb9678cfc7c03128a222a248f3fc7c7a47dc7adbafa5515c763c91f30`, and PID 29413 survived the verification flow.

Computer Use first confirmed a rendered update prompt. After selecting **Not now**, it confirmed a rendered workspace window and opened a persisted session containing expanded and collapsed tool history. Five two-second idle samples each reported 0.0% CPU with RSS between approximately 106,240 and 106,320 KB. After loading the persisted tool session, five further two-second samples each reported 0.0% CPU with RSS between approximately 147,856 and 148,320 KB. There was no persistent hot main thread, so the conditional one-second stack sample was not triggered.

For product commit `059d578`, this verifies that the exact packaged app renders its update and workspace surfaces, remains alive, and returns to idle both before and after loading persisted tool history. The available persisted session did not contain the original oversized superpowers skill block, so verification-gate items 1–3 were not reproduced manually with that exact shape. Item 4 is satisfied for the exercised persisted content. Item 5 was not directly stack-sampled because CPU never became persistently hot. At `a22e7f8`, the production-boundary fixtures are the deterministic coverage for the artificial single-string and console-producer saturation shapes; no shipping fixture hook was added. Developer ID verification of the final product remains pending.

### Final local artifact evidence

The final product commit `8267358` was compiled as a universal Release app and ad-hoc signed for local testing at `/private/tmp/tenx-renderer-hardening-final-local/Build/Products/Release/10x.app`. PID 45514 survived after launch, and five two-second samples each reported 0.0% CPU with RSS 68,976 KB. macOS was locked, so Computer Use could not confirm that final window visibly rendered; this is process and idle evidence only. The original oversized skill-block interaction remains the user-owned manual gate after unlock. Developer ID packaging remains blocked solely by the locked login keychain.

### Post-independent-review local artifact evidence

Product commit `3a06598` compiled as a universal `x86_64 arm64` Release app at `/private/tmp/tenx-pr19-review-fixes-release/Build/Products/Release/10x.app`. The local artifact was ad-hoc signed, passed `codesign --verify --deep --strict`, and has executable SHA-256 `cb3d94ee23e44fbc445becb446ed2fcc8fb309df9e54958638afb7fbf24ec4f8`.

Computer Use confirmed the exact artifact's update prompt and, after selecting **Not now**, a visibly rendered workspace with the composer and provider dock. PID 71327 survived the flow; five post-launch samples each reported 0.0% CPU with RSS 119,088 KB. The original oversized superpowers payload was unavailable in persisted content, so the exact user interaction remains the manual gate; the production-boundary tests cover its line, character, and generation shapes.

### Final independent-review artifact evidence

Product commit `4aa087c` compiled as a universal `x86_64 arm64` Release app at `/private/tmp/tenx-pr19-rereview-release/Build/Products/Release/10x.app`. The local artifact was ad-hoc signed, passed `codesign --verify --deep --strict`, and has executable SHA-256 `807d2fdd45eaad0d5e2a18cb07cf1b65af877d44264f1a5013bb32d5f12333ee`.

Computer Use confirmed the exact artifact's update prompt and, after selecting **Not now**, a visibly rendered workspace with the composer and provider dock. PID 82928 survived the flow; five consecutive samples each reported 0.0% CPU with RSS stable between 125,792 and 125,840 KB. The original oversized superpowers payload remains unavailable in persisted content, so that exact user interaction remains the manual gate.

### Streaming-normalization follow-up evidence

Product commit `d7f70c5` compiled as a universal `x86_64 arm64` Release app at `/private/tmp/tenx-stream-normalization-release/Build/Products/Release/10x.app`. The local artifact was ad-hoc signed and passed `codesign --verify --deep --strict`. Developer ID packaging remains blocked by the locked login keychain's `errSecInternalComponent` response.

Computer Use confirmed the exact artifact's startup and workspace windows, then invoked `/skill:using-superpowers` in a dedicated session. The complete injected skill remained present through its final **User Instructions** section, the session returned to an inactive composer, and a post-load input-and-clear probe responded immediately. An 80-sample, 0.5-second CPU/RSS trace of PID 98894 began at 0.0% CPU and 138,240 KB RSS, briefly peaked at 113.7% CPU and 153,424 KB RSS while the skill content was processed and rendered, then returned to 0.3–0.7% CPU with RSS stable at 153,312 KB; a later idle sample reported 0.0% CPU and 151,936 KB RSS. Because CPU returned toward idle rather than remaining hot, no main-thread stack sample was triggered.

The deterministic saturation fixture separately sends 32 cumulative updates growing beyond 2 MiB and proves zero reductions before flush, exactly one reduction after flush, byte-equal final visible content, and intact beginning and ending sentinels. After the history-order correction, the full arm64 suite passed 1,227 logical tests with zero failures or skips, and the generated Xcode project reproduced without a diff.

Final follow-up head `9efde34` then compiled as a universal Release app at `/private/tmp/tenx-pr20-final-release/Build/Products/Release/10x.app`, was ad-hoc signed, and passed strict deep signature verification; the executable SHA-256 is `37e628943d5ca965fbf60be299efb9f2cbca32be8d9edc29efbf553bb49d8a53`. Computer Use loaded the persisted skill session in this exact artifact and confirmed the complete skill block precedes its later assistant/tool output. Five one-second idle samples each reported 0.0% CPU with RSS stable between 126,592 and 126,640 KB.
