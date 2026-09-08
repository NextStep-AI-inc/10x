# Composer draft and route recovery acceptance status

Status: BLOCKED at native acceptance. The arm64 Release build passed and the isolated package passed ad hoc signature verification. The Mac remained locked at the final native-access check. This package has not been launched.

## Verified

- Source commit: `4d74a5ee36a17ac07505e9dc7f5a14f605ffd55b`.
- Fourteen final store/send-boundary checks passed, including failed disk writes, delayed flushes, newer draft content, and invalidated pipelines. Earlier lifecycle and last-valid-route checks passed.
- Build command, build-log hash, package path, bundle identifier, and unsigned/packaged executable hashes are recorded in `manifest.json`.
- No full suite was repeated. The six previously reproduced baseline activity snapshot failures remain recorded by PRs #32/#34.

## Remaining

Stage distinct text/images in two sessions, quit/relaunch, verify route and contents, then exercise uncertain acknowledgment without an automatic resend. Keep subsequent input distinct.

Stacked on PR #38. Production 4d74a5e includes the final durable send barrier; retain it when integrating Titles and the later Stop/scroll changes.

Keep this PR draft until its native and integration gates pass. No merge or deployment.
