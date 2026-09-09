# Persisted image-history verification

The native macOS Release app built from `6e3bec4d6aa4e000566c7f5a5eb8e05f89f40725` restores saved image pixels and reconciles a new image-bearing prompt exactly once. Verified September 7, 2026 with installed OMP `18.1.10` and Cursor Grok 4.6 Fast in an isolated QA profile.

## Verified

- Reopened the earlier recovery conversation, whose JSONL stores a `blob:sha256:` reference. Its previously missing 600×220 image now renders: [saved image](saved-image-reopened.png).
- Attached the same harmless reference PNG through the native file picker, then sent `IMAGE-REOPEN-VERIFIED: Describe the attached image in one sentence. Do not use tools.` The model described the pixels correctly. The UI showed exactly one new user message and image, with no duplicate pending receipt after persistence: [completed response](new-image-response-reconciled.png).
- Quit the app, relaunched the same Release bundle, and opened the saved rail row. Both original and new images, both user messages, and the final response remained visible: [after relaunch](new-image-persists-after-relaunch.png).
- Read-only JSONL inspection found two user entries total and one entry containing the new marker. Both image references use hash `3c0aeea889741d43192506fef1dff535e413fb7e472fd5534ce755f2ca7cbd38`. Final session-file SHA-256: `cf08e82a02b608d7afd9d7f72215e2286764ea00bcff8b67a551816f963db50e`.
- This ordinary prompt also generated and persisted the title “Describe the attached image,” which survived relaunch. This is one title-success case; the separate fallback-title gap remains open.

## Build and automated checks

Bundle: `/tmp/10x-audit-images-build/10x-images.app`, identifier `com.nextstep.tenx.imageqa`, display name `10x Images QA`. Post-signing executable SHA-256: `7c0b6d999c839d2588209f23d1f26c7d5ac4e1f863cedef3454eded96e80785f`.

Release arm64 build passed using `xcodebuild build -project 10x.xcodeproj -scheme 10x -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/10x-audit-images-release ONLY_ACTIVE_ARCH=YES ARCHS=arm64`. Log: `/tmp/10x-audit-images-release.log`.

The final 12-test focused run passed, including exact receipt matching, unchanged cache reuse, missing-then-created images, cancelled/replaced/changed session reads, and invalid references, wrong hashes, directories, symlinks, and FIFOs. The FIFO case blocked on the old implementation under a bounded 45-second test alarm and passes after adding nonblocking open before the regular-file check. Log: `/tmp/10x-task1-focused-suite-corrections.log`.

The first full application run executed 1,383 tests and reproduced only six known activity snapshot failures at the base. A second full run also hit the existing navigation timing test `openingASessionWhileItsNewSessionOpenIsInFlightReusesItsController`; it then passed in isolation. No baseline references were promoted. The full suite was not repeated after the bounded FIFO correction; all 12 relevant tests were rerun.

## Not verified

- Missing or corrupt blobs were exercised by automated loader tests, not by a new interactive corruption test.
- Unsent drafts across relaunch remain a separate INPUT item.
- Integration with newer main and the six baseline snapshot failures remain readiness gates. PR #34 stays draft; no merge or deployment occurred.

`manifest.json` records every direct screenshot and its hash. Raw sessions, configuration databases, and credentials are excluded. The runtime update prompt was dismissed with Not now so all captures use the built artifact above.
