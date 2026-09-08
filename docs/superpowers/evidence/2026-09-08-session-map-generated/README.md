# Generated Session Map evidence

Status: **In progress.** Canonical source derivation and records/settings are implemented and reviewed, with native settings evidence below. Isolated generation, the current-writer corpus, and live catch-up integration remain in progress. No model-generation success is claimed here.

## Source provenance and checks

- Branch: `codex/session-map-plans`; draft PR [#30](https://github.com/NextStep-AI-inc/10x/pull/30).
- Initial source implementation: `7f9636a4daf7ca9e9badcf6919a45136d3dd9331`.
- Reviewed correction: `3f6c54120cacaf7b1a993e4f6043802591edfda6`.
- Fifteen focused Debug arm64 source/digest/planning tests pass in 0.004 seconds. Log: `/tmp/10x-f59a-session-map-task7-fix1-green.log`.
- The tests cover canonical split-message/tool identity, live/cold agreement, terminal-turn deduplication, changed existing entries, bounded attention/digest content, structured status evidence, and observed Markdown excerpts with containment, UTF-8 and byte limits.
- Four focused regressions reproduced the three review findings before correction: failed/acknowledged todo arguments emitted Done evidence, a later edit retained an earlier captured plan, and excerpt hashes included omitted text. All four then passed. Logs: `/tmp/10x-f59a-session-map-task7-fix1-red.log` and `/tmp/10x-f59a-session-map-task7-fix1-affected-green.log`.
- The scoped re-review found all three findings addressed and no new Critical/Important breakage. Excerpt hashes represent final retained bytes; source fingerprints remain computed before prompt truncation.

## Settings visual checkpoint

The controller inspected the three new settings-row snapshot candidates (checker Off, unavailable writer, and resolved writer/checker) before approving reference promotion. Provider/model/effort subtitles are visible beneath their menus. The revised unavailable writer state displays the unattended control Off and disabled while retaining its stored preference. The controller also inspected the intended light/dark Settings navigation updates; General and Composer remain beside Map. Only these five reference updates were approved.

The actual Release build at `452c9f34db5643a9dce6b05387501fe6ac33032d` also passed menu keyboard selection/Escape, image-only checker choices, unattended toggling, Map deep-link/navigation/search, General/Composer preservation, light/dark minimum-window layout and scrolling, and return to the exact synthetic draft/attachment/chat model. [Settings evidence and verification limits](settings.md) records the captures and commands. Full Tab traversal and spoken VoiceOver remain manual cells. Snapshot references live under `Tests/TenXAppTests/ReferenceImages/` with names `session-map-settings-{off,unavailable,resolved}.png` and `continuous-settings{,-dark}.png`.

The reviewed correction `666f5b82abbaa634ea307ea33bca3b1cdba32e15` refreshes the catalog after Settings closes and rejects older load results. Two regressions reproduced the fault, then 24 focused tests passed in 0.274 seconds. The exact corrected Release build passed the affected native close/reopen check. Record lineage now has one persisted source, and explicit unsupported-schema and occupied-canonical migration tests pass. The scoped re-review found all three findings addressed with no new Critical/Important breakage.

## Current writer preflight

On 2026-09-08, read-only OMP config and catalog queries resolved `smol` to `cursor/composer-2.5-fast`. The catalog advertised text/image input and no thinking-effort metadata for that model. This establishes configuration/catalog availability only; authentication and generation remain unverified. The checker preference remains Off. The eventual live gate will use synthetic input and isolated preferences.

The installed CLI exposes the required no-session/tools/extensions/skills/rules/title flags and RPC mode. The implementation will use the existing OmpKit client and process environment; this preflight is not a substitute for running the new completion path.

## Other evidence and open gates

- [Native Map foundation](../2026-09-08-session-map/README.md).
- [System flyer overlay and actual two-cycle recording](../2026-09-08-system-flyers/README.md).
- The last full app suite remains red with the documented baseline failures; no new full-suite claim is made here.
- Pointer-only flyer hover, inactive scheduling, and spoken VoiceOver retain their reported manual gaps.
- Later-base harness-notice compatibility remains unverified because automatic approval review rejected `git merge --no-edit origin/main` with “approval required by policy, but AskForApproval is set to Never.” The denied operation has not been retried or bypassed.
- No merge, release, or deployment is included.
