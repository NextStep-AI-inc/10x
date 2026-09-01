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

## Surface inventory

### Protected now or already bounded

| Surface | Existing or new guardrail | Residual risk |
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

### Remaining independent risks

| ID | Risk | Evidence in code | Severity | Recommendation |
| --- | --- | --- | --- | --- |
| R1 | Large expanded diffs can build and syntax-tokenize every visible changed line. Completed edit/AST-edit cards start expanded. | `DiffView.lineView` calls `SourceTokenizer.spans` from `body`; unchanged lines collapse, changed lines do not. | Medium | Add a changed-line preview budget and pre-tokenize into the presentation model in a focused diff-performance PR. The new tool-card equality boundary already prevents unrelated stream updates from repeating this work. |
| R2 | Tool media decodes base64 and constructs `NSImage` from computed view properties. Multiple property reads can repeat decode work on body evaluation. | `MediaItemView.decodedData` and `localImage` are computed under `body`. | Medium | Decode once when the immutable media item changes and hold the result in a small presentation value. Verify with a multi-megabyte image fixture before changing. |
| R3 | Active provider wheels deliberately redraw at 30 FPS. | `ProviderUsageWheelView` uses `TimelineView(.animation(minimumInterval: 1 / 30))` whenever `activeCount > 0`. | Medium-low | Profile the packaged app after the transcript fix. If the wheel consumes material idle CPU, replace the continuous sine pulse with a lower-frequency phase animation or pause it while the app is inactive. |
| R4 | The onboarding installer keeps every output line in state, renders them in a non-lazy `VStack`, and scrolls after every append. | `OnboardingInstallStepView.logView` uses `VStack` over the full `log`; `install()` appends every subprocess line. | Medium | Switch to `LazyVStack`, batch UI publication, and keep a bounded visible tail while retaining the full copyable log outside view state. |
| R5 | Rich Markdown lists, tables, quotes, and assistant code fences have no initial child-count preview. | `ContentListView`, `ContentTableView`, nested quote blocks, and `CodeBlockView` enumerate all parsed children. | Medium | Add block-specific preview disclosure only after reproducing a slow real payload. Do not globally truncate assistant responses. |
| R6 | Expanding Show all for console, collections, source, or JSON explicitly removes the preview bound. | Each surface switches from prefix/depth preview to the full collection after user action. | Low | Treat this as an explicit escape hatch. Add staged expansion only if an actual large payload remains unresponsive after user-triggered expansion. |

## Why the other risks are not folded into this fix

R1–R6 are not on the captured hot stack at a distinguishable application symbol, and each has a different correct ceiling. Changing all of them without a fixture would risk truncating useful output, weakening copy behavior, or degrading intentional animations. PR #18 removes the shared transcript invalidation loop first, then the Release verification determines whether any independent surface is still hot.

## Verification gate

The fix is not considered verified until a fresh Release artifact demonstrates all of the following:

1. A skill-sized displayed custom message appears completely before assistant output.
2. The message retains the current raw monospace appearance and selectable text.
3. Streaming output remains interactive while the skill block is on screen.
4. CPU falls back toward idle after publications stop.
5. The main-thread sample no longer spends the entire interval in recursive transcript layout.
