# Readable response turns: Release acceptance

Status: **DONE_WITH_CONCERNS**. ORDER and TURNS passed their native acceptance on the feature branch. PR #35 remains draft pending base integration and the six previously reproduced baseline snapshot failures. No merge was performed.

## Verified

- Production commit: `b4bf0b09ff99566f9cb7fcbff676fb0762cd54ce` on `codex/active-session-turns`.
- Release build: `xcodebuild` for arm64 with signing disabled; `/tmp/10x-turns-passive-scroll-release.log` ends in `BUILD SUCCEEDED`.
- Native artifact: `/tmp/10x-turns-passive-scroll-build/10x-turns.app`, bundle `com.nextstep.tenx.turnspassiveqa`. Executable SHA-256: `b656cebd8d527d1d40ce14a43bacaf572cebba6616ba71e78212044adba8f2ce`.
- Final focused viewport, disclosure, render-row, and search selection: **33 tests passed** in `/tmp/10x-turns-passive-focused.log`. Earlier projection/activity/summary selections passed; approved summary snapshots and nearby regressions passed 23 checks in `/tmp/10x-turn-snapshots-regressions-final.log`.
- Actual OMP 18.1.10 with Cursor Grok 4.6 Fast displayed text, a 30-second command, then final text in source order, both live and reopened. Two later parallel commands completed FAST before SLOW; their cards retained the original SLOW/FAST call order. `runtime-order-verification.json` preserves only the relevant command IDs and completion timestamps.
- The previously freezing gesture now returns in about 0.5 seconds: collapse the first tool group, expand the second group's SLOW command, and scroll upward 0.6 page. The same gesture froze the original and default-anchor candidates. Passive visibility observation replaces the continuously bound scroll position.
- Switching to another session and back retained the staged `TURNS-KEEPS-READING-POSITION` draft, collapsed first group, expanded SLOW command, and visible reading target (approximately 12 pixels of layout variation). Jump to latest returned to the final completed summary. Search through the app's actual actions menu found `PARALLEL-SLOW` and exposed its tool card in Slim mode.
- Sending `Reply with VIEWPORT-SEND-ACK without using tools or changing files.` from the older expanded SLOW card also retained that position through the real 4.5-second response. The explicit Jump action then reached the new reply. `before-send-while-reading.png`, `after-send-keeps-reading-position.png`, and `completion-keeps-reading-position.png` capture this final-build check.
- A controlled RPC session exercised a three-second initial quiet interval and a fourteen-second interval after a tool completed. Working remained visible during both intervals; the final response showed Completed at 22 seconds, in BEFORE TOOL / tool / AFTER TOOL order, with no remaining Working indicator. This is UI lifecycle evidence, not a model performance measurement.
- The isolated QA app was quit after acceptance. User app instances and projects were not modified.

## Evidence

Final-build screenshots: `passive-scroll-responsive.png`, `reading-position-after-session-switch.png`, `search-reveals-slim-tool.png`, `quiet-initial-working-final.png`, `quiet-after-tool-working-final.png`, and `quiet-turn-completed-final.png`.

`ordered-completed-turn.png` and `initial-quiet-working.png` are earlier acceptance captures. `baseline-scroll-comparison.png` and `diagnostic-scroll-without-binding.png` are diagnostic comparisons, not the final artifact. The manifest hashes every image and labels its role.

## Not verified

- These commits have not been merged into main or integrated with the other audit PRs. The app's six existing activity snapshot mismatches remain documented by the earlier recovery/image-history work; references were not rewritten to hide them. A full app suite was not repeated after each scroll correction; the affected behavioral selection and native failure path were rerun instead.
- Exact per-tool durations in older transcripts are outside this slice. They can include an assistant-start fallback; PR #41 addresses reliable tool start markers separately. Completed response duration is derived from response timing, not a sum of those tool labels.
- Provider coverage here is Cursor Grok plus the controlled lifecycle fixture. Other providers, macOS versions, and a distribution-signed build were not exercised.

## For Tanner to test

After integrating the stack, use your normal long conversation to switch sessions while reading older content, search into a collapsed tool, and return to latest. The isolated QA build is evidence for this branch, not an installed replacement.
