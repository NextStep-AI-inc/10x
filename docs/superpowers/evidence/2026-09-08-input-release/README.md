# Deliberate composer input acceptance status

Status: BLOCKED at native acceptance. The arm64 Release build passed and the isolated package passed ad hoc signature verification. The Mac remained locked at the final native-access check. This package has not been launched.

## Verified

- Source commit: `a07dee103e9b249e34623c0ed924b9873fccae42`.
- Ten focused AppKit, marked-text/command-menu routing, transport, independent-warning, and approved snapshot checks passed.
- Build command, build-log hash, package path, bundle identifier, and unsigned/packaged executable hashes are recorded in `manifest.json`.
- No full suite was repeated. The six previously reproduced baseline activity snapshot failures remain recorded by PRs #32/#34.

## Remaining

Use the native picker/drop surface with an image and a long ordinary path at a middle selection; confirm surrounding text, focus, undo, image staging, and warning independence. Exercise a live CJK input method if available without changing user configuration.

Stacked on PR #39. Integrate PR #42's disk drafts before combined relaunch acceptance.

Keep this PR draft until its native and integration gates pass. No merge or deployment.
