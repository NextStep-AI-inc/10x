# Deliberate composer input

The authorized INPUT roadmap requires deliberate file insertion, independent error feedback, and safe Return behavior during CJK composition. Unsent draft persistence is handled by PR #42. This slice uses the existing prompt text/image transport and standard AppKit text APIs.

## Design

Allow regular files in the existing paperclip picker. Images continue through the existing image encoder and staging limits; other files insert their absolute paths into the prompt at the current selection. They are references in text, not uploaded file payloads. Use the existing editor/configurator bridge to retain the actual NSTextView and selection when the picker takes focus, then use standard insertion APIs to preserve undo, surrounding text, and focus. Preserve long paths including spaces; separate multiple paths clearly. Do not inspect file contents, create a new attachment wire type, replace the editor, install global keyboard hooks, or mutate SwiftUI-private classes. Dropped files should use the same shared insertion path when the editor is available. Fall back to the existing safe draft append only when no valid current editor exists.

Change the picker label/help to explain this distinction concisely: images are attached; other files insert paths. Show attachment and model errors independently, suppressing an exact duplicate only if necessary. Clearing one warning must not clear the other.

Before handling plain Return, respect NSTextView marked text. While composing, return ignored so the input method commits its candidate; the existing Send/Steer/follow-up rules apply after composition ends. Do not change unrelated keyboard shortcuts or approval-card focus.

## Ownership and constraints

- Worktree `/tmp/10x-audit-input`, branch `codex/active-session-input`, base `d20ff7c` (PR #39).
- Worker owns `App/Sessions/ComposerView.swift`, `ComposerTextViewConfigurator.swift`, a minimal colocated input helper only if existing seams require it, focused composer tests, and targeted `ViewSnapshotTests.swift` fixtures. New Swift files require `ruby scripts/generate_xcodeproj.rb` with pinned xcodeproj 1.27.0; never edit the generated project manually.
- Read writing-ui and visual-ui before UI work. Reuse current typography, palette, warnings, and editor configuration. Other sessions own other worktrees; do not revert their changes.
- No dependencies, provider/config mutation, schema, auto-send, whole-editor refactor, merge, push, native UI, or full app suite. Use isolated DerivedData `/tmp/10x-derived-input` exclusively.

## Task 1: Insert selected files through the current editor

- [ ] Add a behavioral check with an actual NSTextView: insert a long path containing spaces at a middle selection; surrounding text, selection advance, and undo remain correct. Reject a stale editor belonging to a different composer if the bridge can outlive its view.
- [ ] Broaden the existing picker to regular files. Preserve image encoding and mixed file/image selection. Share path insertion with the existing drop path without changing image transport or loading ordinary file bytes.
- [ ] Verify the prompt carries file paths in `message` and only images in `images`; reuse existing RPC tests where possible instead of mirroring the encoder.

## Task 2: Respect composition and independent errors

- [ ] Add a marked-text Return regression using the existing routing seam: composition commits without sending, while an ordinary later Return follows the existing send behavior. Cover the actual AppKit `setMarkedText`/`hasMarkedText` seam without assuming that pasting CJK text proves IME behavior.
- [ ] Render distinct attachment and model messages simultaneously. Add one focused combined-warning snapshot and verify clearing the attachment warning preserves the model warning.
- [ ] Run affected editor/routing/presentation checks with valid nonzero selectors. Parent reviews new snapshot candidates before promotion. Commit bounded implementation and report exact commands, counts, paths, and limitations.

## Task 3: Parent acceptance

- [ ] Review the change and approved snapshot; build Release for arm64 and package an isolated QA app.
- [ ] In the real composer, place the caret inside text, select an image and a long-path ordinary file, then verify the image remains staged, the path appears at the caret, surrounding text remains, and focus returns. Check warning independence without sending a file unintentionally.
- [ ] Exercise an available CJK input method through the native Return key. If no input method is available without changing the user's system configuration, report that limitation separately from the AppKit composition regression.
- [ ] Save evidence, update INPUT roadmap/PR, retain draft status for stack integration and recorded baseline issues, and leave merge to Tanner.

## Preflight

The picker and Return handling share a standard NSTextView bridge and therefore belong in one slice. File insertion has no runtime protocol dependency: the existing RPC prompt already supports the required text plus staged images. No draft persistence or title behavior is added here.
