# Composer input report

Status: DONE

## Verified

- File picking now accepts regular files. Images still use `ComposerAttachmentEncoder`; every other selected or dropped file inserts its absolute path through the active `NSTextView` at the current selection.
- AppKit insertion preserves surrounding text, advances the selection after long paths containing spaces, participates in undo, and rejects a stale editor after its composer marker leaves the window.
- Marked text is left to the input method before command-flyout or Return routing can consume a key. After composition ends, the existing command and Return routing applies unchanged.
- Attachment and model failures render independently in attachment-first order. Exact duplicates render once, and clearing the attachment value leaves the model message.
- The paperclip help and accessibility label state that images attach and other files insert paths.
- Parent approved and promoted `Tests/TenXAppTests/ReferenceImages/composer-independent-warnings.png` after reviewing both simultaneous warnings.

TDD evidence:

- `/tmp/10x-input-task1-red.log`: the two editor bridge tests failed to compile because `ComposerTextEditorBridge` did not exist.
- `/tmp/10x-input-task1-green.log`: 2 editor bridge tests passed.
- `/tmp/10x-input-task2-red.log`: marked-text and independent-feedback tests failed because the new seams did not exist.
- `/tmp/10x-input-task2-green.log`: 2 marked-text and independent-feedback tests passed.
- `/tmp/10x-input-ime-command-red.log`: the command-flyout composition regression failed to compile because the input-method gate did not exist.

Final focused command:

```sh
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' -derivedDataPath /tmp/10x-derived-input \
  '-only-testing:TenXAppTests/composerEditorInsertsLongFilePathsAtTheCurrentSelectionAndSupportsUndo()' \
  '-only-testing:TenXAppTests/composerEditorRejectsAnEditorAfterItsMarkerLeavesTheView()' \
  '-only-testing:TenXAppTests/markedTextReturnCommitsCompositionBeforeAnOrdinaryReturnRoutes()' \
  '-only-testing:TenXAppTests/commandFlyoutReturnDefersToMarkedTextBeforeActivation()' \
  '-only-testing:TenXAppTests/composerFeedbackKeepsAttachmentAndModelFailuresIndependent()' \
  '-only-testing:TenXAppTests/composerIndependentWarningsSnapshot()' \
  '-only-testing:TenXAppTests/composerReturnRoutingRecognizesOnlyConfiguredShortcuts()' \
  '-only-testing:TenXAppTests/onlyImageFilesAreTreatedAsAttachable()' \
  '-only-testing:TenXAppTests/anAttachmentEncodesIntoThePromptContractShape()' \
  '-only-testing:TenXAppTests/agentSlashCommandClearsOnlyAcceptedAttachmentIdentities()'
```

Result: 10 tests passed in 0.305 seconds. Log: `/tmp/10x-input-focused-final.log`. `git diff --check` also passed.

## Not verified

- Native picker/drop interaction and a live CJK input method were reserved for parent acceptance.
- Release build, packaging, and the full suite were outside this worker's scope and were not run.

## For parent to test

- In the packaged app, select one image and one ordinary file with the caret inside existing text. Confirm the image remains staged, the path appears at the caret with surrounding text intact, and focus returns.
- With an available CJK input method, press Return while a candidate is marked, then press ordinary Return after composition commits.

## Parent native acceptance, September 8

Final source `2b4723f79e91eb4c390e7d880a5259c98fdc7220` switches the picker from a nested blocking modal loop to asynchronous completion. Native path insertion, focus, Undo/Redo, image staging, and independent warnings passed. Eleven focused checks and arm64 Release build passed. Live CJK remains pending approval; native drag/drop was not separately repeated. See `docs/superpowers/evidence/2026-09-08-input-release/README.md` for proof and integration limits.
