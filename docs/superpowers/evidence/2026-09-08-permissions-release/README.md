# Approval defaults acceptance status

Status: native scope acceptance passed. Integration remains pending; all related PRs remain drafts and nothing is approved to merge.

## Verified

- Source commit: `ab4f9c95b885ef9e10ba5098e925c22c3dd19606`.
- The final signed Permissions QA bundle recorded in `manifest.json` was visibly launched. The update prompt was declined, so the tested build was not upgraded.
- Through the actual app menu, Settings → Safety was opened and `tools.approval` was searched. The runtime listed exactly two Tools keys.
- Native screenshot and matching accessibility evidence confirm the intended scope copy:
  - Global OMP defaults come from the isolated profile.
  - Per-tool policies can be overridden by project configuration and apply to new OMP sessions.
  - Approval mode can be overridden by project configuration and per-tool policy and applies to new OMP sessions.
  - `Yolo` was loaded from the isolated profile during acceptance.
- No setting was changed. The app exited successfully with Command-Q.
- Four focused checks passed before packaging: approved light/dark snapshots, exact OMP command construction, and ordered saves.
- Build command, build-log hash, package path, bundle identifier, executable hashes, and native evidence hashes are recorded in `manifest.json`. Existing source/build hashes remain unchanged.
- The parent native-accepted request matrix is tracked by [PR #37](https://github.com/NextStep-AI-inc/10x/pull/37): confirm/select/input, empty-composer Return, input Tab then Return, focus and scroll preservation, separate Cancel and 60-second timeout, multiple requests, and background unread behavior.
- Durable Stop is tracked separately by [PR #36](https://github.com/NextStep-AI-inc/10x/pull/36).
- No full suite was repeated. The six previously reproduced baseline activity snapshot failures remain recorded by PRs #32/#34.

## Remaining

Integration across the draft branches is still pending. The RPC exposes no active effective-policy field, and no Always Allow response exists.

Based on main `0be4353`. Keep this PR draft until integration passes. No merge or deployment.
