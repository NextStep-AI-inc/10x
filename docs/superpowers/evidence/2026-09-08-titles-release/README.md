# Session titles and metadata acceptance status

Status: BLOCKED at native acceptance. The arm64 Release build passed and the isolated package passed ad hoc signature verification. The Mac remained locked at the final native-access check. This package has not been launched.

## Verified

- Source commit: `edf8ff914750e8fd66e68e83883109f48737ac03`.
- Six title checks and three metadata/navigation checks passed, including persisted fallback titles, generated-name precedence, manual-rename/replacement guards, real temporary git branches, and retained RPC identity.
- Build command, build-log hash, package path, bundle identifier, and unsigned/packaged executable hashes are recorded in `manifest.json`.
- No full suite was repeated. The six previously reproduced baseline activity snapshot failures remain recorded by PRs #32/#34.

## Remaining

Verify generated/fallback/manual/duplicate names and relaunch in the native app. Change a branch only in an owned QA repository through a real tool turn, then switch away/back after an external QA-only branch change.

Stacked on PR #42. Integrate its later 4d74a5e durable draft-send correction before final stack acceptance.

Keep this PR draft until its native and integration gates pass. No merge or deployment.
