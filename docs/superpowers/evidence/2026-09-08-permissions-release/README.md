# Approval defaults acceptance status

Status: BLOCKED at native acceptance. The arm64 Release build passed and the isolated package passed ad hoc signature verification. The Mac remained locked at the final native-access check. This package has not been launched.

## Verified

- Source commit: `ab4f9c95b885ef9e10ba5098e925c22c3dd19606`.
- Four focused checks passed: approved light/dark snapshots, exact OMP command construction, and ordered saves.
- Build command, build-log hash, package path, bundle identifier, and unsigned/packaged executable hashes are recorded in `manifest.json`.
- No full suite was repeated. The six previously reproduced baseline activity snapshot failures remain recorded by PRs #32/#34.

## Remaining

Inspect the native Settings scope copy. Complete the separate confirm/select/input/cancel/timeout/multiple-request and typing-focus matrix with PR #37. The runtime has no active effective-policy field or Always Allow response.

Based on main 0be4353. Integrate with the attention and durable Stop changes before combined acceptance.

Keep this PR draft until its native and integration gates pass. No merge or deployment.
