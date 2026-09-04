# 10x interaction improvements

Status: approved interaction choices, implementation in progress. Tanner approved the selector preview and continuation on September 4, 2026. Draft PR #22. Base: `eb9537354188e2849c28fc3aa285c95e924b7260`.

## Scope and evidence

Resolve the September 4 audit's B01–B16 and requests U01–U10. Include F04 search-to-match, F05 native question cards, F06 session renaming. Defer F01 Changes panel, F02 task terminal, F03 file-context picker. Audit evidence is preserved at `/Users/tannerpham/Downloads/10x-Interaction-Audit-2026-09-04`; it describes an older build. Revalidate fixes already merged into main before changing them.

Work in the dedicated worktree. Preserve the main checkout's uncommitted composer paste changes. No merge, deployment, unrelated refactor, dependency change, or account configuration change. Use an isolated Release build for final UI verification.

## Submission and session state (U01, U02, U06; B01, B02, B13, B16)

Sending immediately displays one user bubble, including attachments, before runtime startup or first token. A small indicator beside Working… appears below it. Reconcile backend echoes without duplicates, including repeated identical prompts. Preserve content and an actionable error if startup/submission fails; don't blindly retry a request whose delivery is uncertain.

Use the same title-loading state in header and sidebar, with a restrained shimmer instead of temporary Untitled Session. Title generation is independent of turn activity. If work ends without a generated title, use the first nonempty line of the prompt as a bounded fallback; saved sessions retain their actual names. User renaming takes precedence over late generated titles.

Session number: falling/pulsing blue line while working, solid blue when ready, yellow when explicit input/approval is required, red on terminal failure, neutral when stopped by the user. Selection remains independently visible. Supply accessible status text and static Reduce Motion equivalents. Tool errors during continuing work do not mark the session failed.

Persist new-session draft/attachments across Settings and session navigation. Command-N focuses the composer. Navigation during startup reuses its controller and eventual persisted session identity. Recovery exposes the failed step and available sanitized diagnostics without an unexplained Stopped label.

B01's main-thread freeze is separate from first-token visuals. Verify the recent renderer/backpressure fixes against the original realistic task and larger output; do not claim an animation fixes responsiveness.

## Composer and queue (U07; B03–B05)

Move Steer/Follow up to the right-hand Send group. Default primary action is Steer: Enter and Send perform it while streaming; Command-Enter performs Follow up. Shift-Enter inserts a newline. When idle, sending starts the next turn. Selecting the alternate primary action swaps its label and shortcut hints. Expose valid configurable bindings and default action in 10x Settings; disallow ambiguous duplicate bindings.

Stop is a separate control available while working regardless of draft/attachments. Steer changes current work at the runtime's supported boundary, not by pretending to interrupt a running tool. Show each pending message and delivery kind immediately, with queued/sending/failed state. Offer edit/cancel only where the real runtime contract supports it safely; never imply that locally removing a receipt cancels backend work.

Typing code preserves ASCII quotes and double hyphens. Preserve existing image paste, drag/drop, command browser and multiline editing behavior.

## Streaming position (U08; B08, B14)

Following is explicit user intent. At bottom, follow text, tool changes, activity and content reflow to an actual bottom sentinel. User upward scrolling unlocks following. Jump to latest scrolls to that sentinel and re-enables following immediately. Geometry growth alone never unlocks it. While unlocked, preserve the visible anchor on resize, disclosure changes and session navigation. Avoid automatic scrolling animations during streaming. Search navigation unlocks follow until Jump to latest.

## Provider/account wheels (U03–U05)

Keep all providers visible. Only the hovered provider/account enlarges. Multi-account providers use a stack: the account directly under the pointer grows and comes above the accounts behind/below it. Stable pointer regions prevent oscillation; leaving restores original size/order. Account identity and all computable usage limits remain distinct.

Click pins complete details for that provider/account while other providers remain selectable. Escape, outside click and a visible close action dismiss details. Keep hover and pinned selection separate. Active geometry scales with the wheel; use existing truthful account attribution and static Reduce Motion treatment. Preserve explicit account-routing confirmation and scopes already present in main.

## Model picker (U09; B12)

Implement the approved preview: approximately 440-point popover, existing stepped outline, favorites above the model catalog, provider identity visible, star action independent of row selection. Persist provider/model identities in 10x preferences. Search filters favorites and catalog. Favorites do not include effort presets.

Use a segmented effort bar with full supported labels, selected segment filled with the app's emphasis color. Six levels can wrap into two rows of three at constrained widths; never clip Extra high. Do not invent unsupported levels. Preserve Fast mode and keyboard selection. The approved preview is a design reference, not app verification:
`/Users/tannerpham/.codex/visualizations/2026/09/04/01a06dfb-9e80-7d51-8223-d53e1046ffaf/effort-selector-preview.html`.

## Settings (U10)

Two labeled groups of category tabs on one horizontal row: OMP left, smaller 10x group right aligned. One selected content view. At narrow widths OMP tabs scroll within remaining space; 10x stays anchored. Keep one search field with results grouped by owner.

10x owns composer shortcuts/default send action, favorites and preferred editor. OMP owns runtime model defaults, agent/tool policies, permissions, memory/extensions and its terminal UI. Put config path/count within OMP content. Keep native controls available when OMP load fails. Preserve existing values, reset behavior, focus links and provider management. Label terminal-only effects accurately after checking the actual setting. Do not add empty categories or new speculative preferences.

## Transcript accuracy and archives (B06, B07, B09–B11, B15)

Decode real OMP phase/task plans into populated task cards. Never turn code expressions into file links; retain valid relative/absolute file links. Suppress genuinely empty assistant rows without losing tools or delayed text. Render structured advisory content legibly and consistently in live/history views, with truthful state and no invented resolution. Tool duration labels must identify their measured interval rather than imply conflicting process wall times are identical. Archive rows expose Restore as an obvious action.

## Added features (F04–F06)

Search selection opens the session at the actual matching message, highlights the match, and loads required older history. Preserve stable entry identity and the query; missing/deleted matches fail gracefully and don't jump to unrelated text.

Native question cards use the runtime's actual question/extension request protocol, with supported choices and free text, keyboard submission, explicit cancelled/answered state, duplicate-submit prevention, and visible failures. Yellow status follows explicit outstanding requests. Do not infer a native request from prose or claim a tool is available when it is not.

Rename is available from session management and the current header. Cancel leaves the title unchanged; blank names are rejected; save errors retain editing content. Successful rename persists through reload and updates rail, header and search. Avoid competing runtime controllers for a session already open.

## Verification and delivery

Use focused behavioral regression tests with delayed/failing transport where needed, then exercise the real Release UI. Verify draft navigation; send/echo/startup failure; Stop with content; queue receipts; bottom-follow/unlock/jump; resize; model favorites and full effort labels; account hover/pinned details; both settings groups; question answer/cancel; rename/reopen; search into older history; restore; task/file/advisory content.

Use realistic development on a disposable fixture. For provider-dependent behavior use Cursor Grok 4.6, Anthropic Opus 5 and OpenAI GPT 5.6 Sol with medium/high effort, not every provider for every UI check. Preserve global defaults after testing. Capture screenshots/recordings and list exact steps. Review spec compliance, then code quality and the live appearance. Final report lists Verified, Not verified and For Tanner to test. Leave PR unmerged.
