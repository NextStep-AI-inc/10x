# Deliberate composer input acceptance

Status: **DONE_WITH_CONCERNS** for the exercised native input flow. Live CJK input remains unverified, so PR #43 stays draft along with the audit stack.

## Verified

- Final production source: `2b4723f79e91eb4c390e7d880a5259c98fdc7220`. The signed arm64 Release package is `/tmp/10x-input-async-panel-build/10x-input.app`, bundle ID `com.nextstep.tenx.inputqa`. `async-panel-package.json` records its executable hash and proves the compiled source patch exactly matches the committed change.
- The real native picker inserted a long ordinary file path containing spaces before `AFTER`, preserving `BEFORE | ` and all trailing text. The path wrapped within the composer. Focus returned to the editor; Command-Z restored the original text and Command-Shift-Z restored the insertion.
- A valid 600×220 PNG remained a staged image alongside the ordinary path. Selecting a deliberately invalid PNG preserved that image and displayed the attachment warning separately from the controlled model-loading failure. Removing the image cleared the attachment warning while the model error remained.
- Eleven focused AppKit, actual SwiftUI binding, stale-editor, marked-text/command-flyout routing, image transport, and independent-warning/snapshot checks passed. `focused-tests.txt` preserves the result; exact command and log hash are recorded below and in `native-verification.json`.
- The Release build/typecheck and strict ad hoc signature verification passed. The QA app was quit, and a process check confirmed it closed.

## Native correction

The initial blocking picker returned the correct URL but insertion left the original draft unchanged. A neutral diagnostic found the correct editor and caret: text storage grew from 14 to 220 UTF-16 units, then SwiftUI restored 14 during the edit notification. `native-failed-modal-trace.txt` preserves that observation. Switching the picker to AppKit's asynchronous completion API made the actual insertion and native Undo/Redo pass. The original `NSTextView.insertText` implementation is retained; temporary diagnostics and unsuccessful edit/focus experiments are absent from production.

The added small SwiftUI test verifies binding propagation; it did not reproduce the blocking-picker failure. The native before/after observations are the regression evidence for that correction.

## Evidence and limits

Primary screenshots: `native-mid-caret-file.jpg`, `native-file-and-image.jpg`, and `native-dual-warnings.jpg`. Matching accessibility captures include Undo, Redo, and warning clearing; provider-account rows were removed. The parent inspected the insertion and combined-warning images.

The native model warning comes from the isolated controlled RPC fixture, which rejects model enumeration. It did not change a real provider or send a model prompt. The invalid-image message still uses the existing generic image-limit wording; improving that wording is a follow-up, outside this correction.

Live CJK candidate composition remains unverified. Only the U.S. keyboard is enabled; approval to temporarily add Pinyin is pending. Actual AppKit marked-text and command-menu routing tests passed. Native drag-and-drop was not separately repeated; the picker exercised the deliberate insertion path, and shared insertion/transport tests passed. No full suite was repeated; the six baseline activity snapshot failures remain recorded by PRs #32/#34.

Disk drafts and unconfirmed-send relaunch passed native acceptance separately in PR #42. This branch is based on PR #39; the combined audit stack is not yet integrated or verified. No merge or deployment occurred.

## Reproduce focused checks

`xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` with the eleven `-only-testing:TenXAppTests/...()` selectors in `focused-tests.txt` passed. Full invocation and output: `/tmp/10x-input-async-panel-focused-final.log`.
