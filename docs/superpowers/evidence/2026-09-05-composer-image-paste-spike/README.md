# Composer image paste spike

**Date:** 2026-09-05
**Worktree:** `/Users/tannerpham/CS Projects/.worktrees/10x-composer-image-markup-preview`
**Branch:** `tannerpham/composer-image-markup-preview`
**Commit:** `2480e88`
**Parent:** `f9c4dfe` (Task 1 classification)
**Built binary:** `/tmp/10x-image-markup-spike/Build/Products/Debug/10x.app`
**Result:** `FAIL`
**Locked path:** `owned-nstextview`

A second `com.nextstep.tenx` instance (`/Applications/10x.app`) was already running. A Debug launch of this worktree hung on "Checking OMP and provider access" and never reached the workspace composer. The probe was exercised in the same Debug binary through a focused `ComposerView` whose editor was first responder (caret in "Describe the task"). Key events were real HID-level Command-V (`CGEvent` / `cliclick`), not `NSApp.sendEvent`.

## Cases

| Case | Result |
| --- | --- |
| Real screenshot on the clipboard, focused Command-V | No `Pasted image` strip. The draft text was unchanged. Image-only paste still does nothing. |
| Short string on the clipboard, focused Command-V | The string inserted into the draft. No image was staged. |
| Command-Shift-V, Option-Command-V, typing `v` | Did not stage an image. |

## Decision

Focused Command-V never staged an image through `.onKeyPress`. The key-router probe and extra `KeyEquivalent("v")` were reverted. Staging helpers `add(images:)` and `add(pasteboardContent:)` stay for Task 3B.

Continue to Task 3B. Skip Task 3A.
