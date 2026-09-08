# Local audit integration acceptance

Status: **DONE_WITH_CONCERNS**. All thirteen pinned feature heads are combined with main in `codex/active-session-audit-integration`, and the feasible combined native acceptance flow passed. Thirteen of the fourteen original audit items have completed their recorded native acceptance. INPUT still lacks live CJK candidate composition. Four pre-existing activity snapshot mismatches remain; the full app suite is not green.

[Visual progress gallery](progress-gallery.html) · [Full audit roadmap](../../plans/2026-09-07-active-session-audit-roadmap.md) · [Local integration plan](../../plans/2026-09-08-audit-local-integration.md)

## Build and git identity

| Field | Recorded value |
| --- | --- |
| Worktree | `/tmp/10x-audit-integration` |
| Branch | `codex/active-session-audit-integration` |
| Main baseline | `0be4353f7ee2d72813d41d6195422f34ef213c22` |
| Combined source merge | `8b0c63bca96e2970914e744433109174727cbda5` |
| Release source commit | `fa22abbb1263bcc3cfd78edbfefb21053c7f664f` |
| Reviewed snapshot commit | `439dd79` |
| QA package | `/tmp/10x-integration-build/10x-integration.app` |
| Bundle identifier | `com.nextstep.tenx.integrationqa` |
| Executable SHA-256 | `e73d9fa47da9d5ad284ccd44ffdc22426eaaac27c2d517c397fcf379fef8e97e` |
| QA profile | `/tmp/10x-session-recovery-home` |

The local integration was explicitly approved on September 8. The thirteen feature PRs (#32–#39 and #41–#45) remain separate drafts; this integration branch is unpublished. No GitHub merge or deployment was performed. [The pinned inputs and conflict resolutions](merge-record.json) retain normal git ancestry. The generated Xcode project was regenerated with the repository script. Changes after the Release source commit are test references and evidence, with no packaged production-code changes. [Handoff integrity checks](handoff-integrity.json) confirm the package hash, unchanged production source, unchanged timer/tail/child files, and report links.

## Verified

### Build and tests

| Check | Result | Evidence |
| --- | --- | --- |
| OmpKit suite | Reported 222 tests passing; three opt-in live cases explicitly skipped | [Test summaries and log hashes](test-results.json) |
| Full combined app suite | 1,591 tests in 43 suites ran; 20 snapshot issues, zero behavioral failures; two runtime-schema checks explicitly skipped | [Test summaries](test-results.json), [first-run image hashes](combined-first-run.json) |
| Snapshot attribution | Six known selectors first ran at main. Four combined activity actuals are byte-identical to baseline failures; the two subagent selectors pass in the combined suite | [Main baseline](main-baseline.json) |
| Intentional snapshot updates | All 16 changed references visually inspected; the focused rerun passed all 16 | [Review](snapshot-review.md), [test summaries](test-results.json) |
| arm64 Release | Build succeeded; separate bundle packaged; ad-hoc deep/strict signature verification passed | [Build manifest](native-build.json) |
| Progress gallery | Browser rendered all 15 content images at 1280 px without horizontal overflow; comparison toggle, full-size native/snapshot images, Escape, Tab containment, and opener focus restoration passed | [Browser screenshot](progress-gallery-browser.png), [full-image screenshot](progress-gallery-lightbox.png) |

The full app suite was not rerun after replacing the 16 reviewed references. Only the affected 16 selectors were rerun, as planned. The remaining four baseline references were preserved, rather than updated to hide those failures. No production changes were needed after the combined suite or native acceptance.

The gallery is a self-contained HTML file. Its local preview is `http://127.0.0.1:56418/`; it uses embedded images and has no external dependencies. The preview remains available for the requested handoff. The page can also be opened directly from the file above. Its generator is `progress-gallery/build-gallery.js`.

### Original fourteen-item acceptance ledger

Individual feature evidence is retained and was not replaced by claims that every scenario was repeated after integration. The combined run concentrates on overlapping controls, state, and recovery. Reused native checks were completed in this same audit session.

| Item | Acceptance result and evidence |
| --- | --- |
| SAVE | **Passed.** Real warm/cold persistent creation and disk recovery in [feature acceptance](../2026-09-07-session-continuity-recovery/README.md); combined real-provider history survived quit/relaunch. |
| OPEN | **Passed.** First-action existing-session open in [feature acceptance](../2026-09-07-session-continuity-recovery/README.md); combined saved route reopened the intended real session with its draft and image. |
| ERROR | **Passed.** Distinct failed-new, failed-existing, rejection, and process-exit paths in [feature acceptance](../2026-09-07-session-continuity-recovery/README.md); combined unconfirmed-send recovery restored without replay. |
| STOP | **Passed.** Foreground/background termination and staged-image retention in [feature acceptance](../2026-09-07-reliable-session-stop/README.md); combined Command-period from a pending input field cleared requests, recorded Stopped, and retained the composer draft. |
| QUEUE | **Passed.** Steering, rejection, repeated messages, and consumption in [feature acceptance](../2026-09-07-stop-and-queue/README.md); combined native follow-up displayed count 1, later cleared, and persisted once. |
| ORDER | **Passed.** Parallel live/completed/reopened source order in [feature acceptance](../2026-09-07-readable-response-turns/README.md); combined real turn displayed its reads, edits, and completion with correct per-file links. |
| TURNS | **Passed.** Quiet intervals, duration, disclosure, search, and reading behavior in [feature acceptance](../2026-09-07-readable-response-turns/README.md); combined completion showed 10.6 seconds, and warm session switching retained the opened review and reading position. |
| SIGNALS | **Passed.** Nonintrusive request arrival, explicit navigation, background completion, and acknowledgement in [feature acceptance](../2026-09-08-session-attention/README.md); combined pending-request navigation and typing, Stop, and background queue completion passed. |
| REVIEW | **Passed.** Actual single- and multi-file tool results, deduplication, and excluded shell/pre-existing changes in [feature acceptance](../2026-09-08-review-release/README.md); combined actual two-file edit indexed both paths and opened the correct diff and Cursor file. |
| CONTEXT | **Passed.** Real OMP compaction from 94,526 to 71,401 estimated tokens plus controlled capability cases in [feature acceptance](../2026-09-08-context-compaction/README.md); combined busy, failure, and Stop feedback passed. |
| TITLES | **Passed.** Automatic/fallback/manual duplicate naming, missing-project recovery, relaunch, and branch refresh in [feature acceptance](../2026-09-08-titles-release/README.md); combined actual tool branch change updated the header, and the saved route restored after relaunch. |
| PERMISSIONS | **Passed within supported runtime scope.** Native request matrix and [Settings scope evidence](../2026-09-08-permissions-release/README.md); combined confirm/select/Stop and Global OMP defaults wording passed without changing policy values. |
| INPUT | **Partially passed; live CJK remains open.** [Native insertion/warning checks](../2026-09-08-input-release/README.md), [durable draft acceptance](../2026-09-08-drafts-release/README.md), and combined picker-at-caret, Undo/Redo, separate drafts, image/relaunch, independent warnings, and unconfirmed recovery passed. AppKit marked-text routing tests pass; actual Pinyin candidate composition has not run. |
| DETAILS | **Passed.** Native advancing timer/output, Show more/Copy, Cursor paths, child transcript, and recent tools in [feature acceptance](../2026-09-08-tool-details/README.md). The timer/tail/child implementation is unchanged from the accepted feature head and combined regression coverage passes, so the timed fixture was not repeated. Combined preferred-editor and diff navigation were repeated. |

### Combined native evidence

- **Real provider turn and changed files:** The native composer sent a bounded request in the neutral `integration-native` project using Cursor Grok 4.6 Fast. It ran `pwd`, created `qa-integration-b`, and edited only `integration-alpha.txt` and `integration-beta.txt`. The project HEAD did not change. The completed turn showed both tool-reported paths; beta opened the correct +1/−1 diff and then the actual file in Cursor. [Native turn](native-real-turn.ax.txt), [diff screenshot](native-diff-review.jpg), [project result](native-project-result.json), [editor path](native-editor-path.ax.txt).
- **Draft and navigation continuity:** The native picker inserted a long text-file path immediately before `AFTER` without losing the prefix or suffix. Native Undo/Redo worked. A retained text plus `context.png`; B retained distinct text. A → B → A preserved A's text/image, opened review, and reading position. Normal quit/relaunch restored A's route/text/image, and B's separate draft remained. [Insertion at caret](native-mid-caret-file.ax.txt), [warm return](native-warm-draft-return.jpg), [cold A](native-cold-route-draft-a.jpg), [cold B](native-cold-draft-b.ax.txt).
- **Unconfirmed send:** The actual Send button submitted text plus the image once to the controlled runtime, which withheld acknowledgement and history persistence. After quit/relaunch, the original draft/image and recovery banner returned. The control trace still held exactly one prompt across two process launches, and the session file still held only its header. No resend was clicked. [Recovery screenshot](native-unconfirmed-recovered.jpg), [control](native-unconfirmed-control.jsonl), [counts](native-unconfirmed-summary.json).
- **Pending requests and Stop:** With three requests already pending, typing retained focus and the older reading position. Explicit header/composer actions reached the requests. Confirm and select each produced one response. Command-period from the third input field sent abort, cleared pending UI, recorded Stopped, and retained the main draft. These combined screenshots were captured after request arrival; the earlier feature evidence proves behavior during arrival. [Pending reading view](native-reading-with-pending-requests.jpg), [request state](native-three-requests-arrived.ax.txt), [stopped](native-pending-stopped.jpg), [control](native-attention-control.jsonl).
- **Queue and background completion:** A real follow-up displayed count 1 while shell work was active. After switching away and returning, completion was unread until acknowledged; the count cleared. Both distinct follow-up markers appear once in persisted history. `native-queue-count-one` is the count proof; `native-queue-accepted` was captured after the first follow-up had already completed. [Count screenshot](native-queue-count-one.jpg), [consumed state](native-queue-consumed.ax.txt), [persisted entries](native-queue-delivery.json).
- **Compaction and warnings:** Controlled failure kept the retry action available; busy compaction showed progress and could be stopped into the documented disconnected/restart state. A valid staged image remained while invalid-image and model-load warnings appeared together. Removing the image cleared only the attachment warning. [Failure screenshot](native-compaction-failure.jpg), [busy](native-compacting.ax.txt), [stopped](native-compaction-stopped.ax.txt), [both warnings](native-dual-warnings.jpg), [attachment warning cleared](native-attachment-warning-cleared.ax.txt).
- **Policy scope:** The actual Settings navigation displayed Global OMP defaults in current-main's OMP/10x settings layout. This integration added scope wording; the settings redesign was already on main. No policy setting was changed. [Settings screenshot](native-global-scope.jpg).

## Not verified and known concerns

- **Live CJK:** Only the U.S. keyboard is configured. The pending request is to temporarily add Apple's Pinyin input, exercise actual candidate composition and Return, then remove it. Computer-use policy requires confirmation for that system-preference change. No keyboard preference was changed. Native drag/drop was not separately repeated; picker insertion is the demonstrated native path.
- **Full green suite:** Four pre-existing activity snapshot mismatches remain. Two runtime-schema app checks and three OmpKit live opt-in checks were explicitly skipped. Real provider acceptance is recorded separately; it does not turn those skipped test cases into passes.
- **Bounded reuse:** The combined run did not repeat the full timed child-output fixture, the actual successful context compaction, every rejection/steering case, or every title variant. Their individual native evidence and combined regression results are linked above. PNG preservation during compaction and the short compaction timeout are regression-only. The Continue-after-warm-up-timeout correction has focused regression evidence; the final native relaunch exercised the normal prepared path.
- **Runtime/provider follow-up:** Long shell work exposed raw background-job notices and one premature model completion response before the background job ended. The model subsequently continued waiting after a runtime notice. The queue followed actual agent-turn boundaries and persisted each accepted prompt once; this does not prove all background jobs finish before a queued turn begins. This adjacent behavior was recorded without expanding the app changes.
- **Earlier feature concerns:** One initial SIGNALS app instance exited cleanly with no established cause; the subsequent native matrix completed. Optional startup warm-up timeouts and the generic eight-image invalid-image copy remain documented follow-ups. No unrelated hardening was added.
- **Publishing:** This is local acceptance only. The branch has not been pushed, PRs are still drafts, and no GitHub merge or deployment has been performed.

## For Tanner to test

1. Open the visual gallery above for the before/after comparisons and full-size native screenshots.
2. Launch `/tmp/10x-integration-build/10x-integration.app` for the combined experience. It uses the isolated QA profile and should restore **Combined native acceptance fixture** with an unsent draft and image. Switch to **Integration acceptance baseline** and back to inspect the separate drafts; use a new session if sending a new prompt. The controlled **Unconfirmed draft acceptance** session intentionally withholds acknowledgement and rejects replay, so it is evidence rather than a normal conversation fixture.
3. The only missing original native acceptance gate is live CJK. The existing Pinyin permission request remains pending; it is not a request to merge or deploy.

At handoff the integration QA app and its task-owned runtimes were closed, confirmed by process inspection. Cursor remains open with the neutral fixture file tabs used for editor navigation. The gallery preview server is intentionally retained as the requested artifact. All other work stays committed in this local worktree; the branch HEAD identifies the final report commit.
