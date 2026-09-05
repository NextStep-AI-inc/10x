# Composer Image Paste, Markup, and Preview

**Status:** Approved for implementation planning
**Date:** 2026-09-05
**Platform:** macOS 15+, Swift 6.1, SwiftUI
**Builds on:** composer attachments and transcript `MessageImageView`

## Goal

Let a user paste a screenshot into the composer with ⌘V, mark it up before
send, and open sent images for a closer look. The model must see the marks.
The transcript must show the same pixels the model received.

Attachment, drop, paperclip, downscale, and wire shape stay as they are.
This work adds focused paste, optional markup, and an in-app preview.

## Approved product decisions

- Markup is screenshot annotation baked into the pixels at send: pen, arrow,
  rectangle, text, and undo. One markup color: `TenXPalette.signalRedHex`.
  No color picker, blur, crop, or layers.
- The editor opens on demand from a staged thumbnail. Paste, drop, and
  paperclip only stage. Send as-is if the editor is never opened.
- Sent images open in an in-app lightbox. No extra window. No Quick Look.
- Strokes stay editable until Send. Send composites once. After send there
  is no original and no re-edit.
- Live editor and strip draw the encoded base plus a vector overlay. Bitmap
  compositing and re-encoding run only at send.
- Focused image paste is gated by a built-app spike, not by a synthetic
  key-event probe. Try the existing `onKeyPress` router first. If a real
  focused ⌘V does not stage the image (or breaks text paste), replace the
  composer `TextEditor` with an owned `NSTextView` representable. Never hook
  or mutate `SwiftUI.PlatformTextView`.

## Current baseline

Images already attach from the paperclip and from a drop. They are fitted to
a 1,568-pixel longest side, encoded as PNG when that stays under 1 MB, else
JPEG, and sent as `PromptImage`. The strip shows a 44-pixel thumbnail. User
and assistant image blocks render inline, boxed at most 420×320. A focused
`TextEditor` swallows paste: image-only clipboards do nothing; image-plus-text
pastes the text; a Finder image file pastes a path. `.onPasteCommand` never
fires while that editor is first responder. There is no markup and no
click-to-expand viewer.

`TranscriptAnnotation` is a transcript event label. It is not image markup.

Start from the current composer (`TextEditor`,
`ComposerCommandKeyRouting`, `ComposerTextViewConfigurator`), not the closed
PR #17 key-monitor branch. The paste spike may replace `TextEditor`; it
must not revive that monitor.

## User flow

```text
Clipboard / drop / paperclip
        |
        v
   Stage attachment          (encoded, downscaled, no editor)
        |
        |-- click thumbnail --> lightbox (edit)
        |                         draft strokes, vector overlay
        |                         Done writes strokes; Cancel discards
        |
        v
      Send
        |-- no strokes --> existing PromptImage bytes
        |-- strokes    --> composite once, re-encode, send those bytes
        |
        v
   Transcript thumbnail      (burned pixels only)
        |
        v
   Click --> lightbox (view)  zoom/pan, no toolbar
```

## Architecture

One overlay, two jobs: edit a staged image, or preview a sent one. Markup
lives on the attachment until Send, then it is burned into the pixels the
model and the transcript both see.

```text
NSPasteboard
    -> ComposerPasteboard.content
    -> ComposerView.add (existing)

ComposerAttachment
    base pixels + optional strokes
    -> strip / edit overlay   (vector, never composited)
    -> Send                   (ImageMarkupRenderer + existing encoder)
    -> PromptImage
    -> session file / MessageImageView
```

Four units, each testable without the window:

1. **`ComposerPasteboard`** — classify a pasteboard: image files, then image
   data, otherwise none. No event monitor.
2. **`ImageMarkup`** — pen, arrow, rectangle, and text strokes, plus undo on
   a draft list. Points are stored in the attachment’s fitted pixel space,
   not view space.
3. **`ImageMarkupRenderer`** — `base + strokes → CGImage`. Called only at
   send. The live editor and the strip do not call it.
4. **`ImagePreviewSession`** — which image is open, edit vs view, and the
   draft stroke list. Hosted as a dimmed overlay on `NewSessionView` and
   `ActiveSessionView`, not a sheet.

### Attachment model

`ComposerAttachment` stays the encoded, downscaled base (longest side 1,568,
PNG-or-JPEG rule unchanged) and gains an optional stroke list. Encoding still
happens when the image is added, so the strip can show size before any
markup. Opening the editor copies the list into a draft; Done writes it
back; Cancel, Esc, backdrop click, or opening another image throws the draft
away. Send is the only composite.

After send the session file and `MessageImageView` only ever see burned
pixels. The original unmarked bytes are not kept.

### Paste

A synthetic `NSEvent` sent through `NSApp.sendEvent` is not proof that a
real focused-editor ⌘V reaches SwiftUI `.onKeyPress` before AppKit’s menu
key equivalent (`Edit → Paste` / `paste:`). The first implementation task
is a built-app spike that uses a real screenshot on the clipboard and a
real ⌘V while the composer editor is first responder.

**Spike pass** (lock the key-router):

- Focused ⌘V with an image (or image file) on the clipboard stages it
  through the existing `add` path.
- Focused ⌘V with only text still inserts that text.
- ⌘⇧V, ⌥⌘V, and typing `v` are unchanged.

If that pass holds, add `v` to `ComposerCommandKeyRouting.keys` and classify
in `handleEditorKey`: plain ⌘V with image content returns `.handled` and
stages; anything else returns `.ignored`. Keep
`.onPasteCommand(of: [.png, .jpeg, .tiff])` as the unfocused fallback.

**Spike fail** (owned `NSTextView`, not a private hook):

If a real focused ⌘V never reaches `.onKeyPress`, or image paste still
does nothing, replace the composer `TextEditor` with an owned
`NSTextView` representable that overrides `paste(_:)`. Classify with
`ComposerPasteboard.content(of:)`. Images and image files stage and return
without calling `super`; text and everything else call through. That path
also covers `Edit → Paste`. Preserve today’s height overlay, focus, Return
routing, and command-browser keys.

Forbidden on every path: a window-local key monitor, an `isa` swap, a
`paste:` hook, or any swizzle of `SwiftUI.PlatformTextView`.

Record the spike outcome (pass or fail, and which path locked) in
`docs/superpowers/evidence/` before markup work continues. Classification
tests can land before the spike; routing-shape tests wait until the path
is locked.

### Send

Composite happens first, then `staged.map(\.promptImage)` and
`PendingUserSubmission` both see the burned bytes. The optimistic user
bubble matches what the model gets.

- No strokes: do not re-encode; send the existing attachment bytes.
- Strokes: draw onto the base, re-encode with the existing budget, replace
  the staged attachment’s `data` / `mimeType` / pixel size, then send.
- Composite or encode failure: Send does not start, draft and attachments
  stay (including the stroke list), and the existing red attachment line
  reports it.
- RPC failure after a successful composite: restore the already-burned
  attachment, same as the current restore path.

Existing limits stay: eight images; extras report the same skip line;
non-image files still become draft paths.

### Coordinate mapping

Pointer events map through the displayed image rect into the attachment’s
fitted pixel space. A window resize must not drift the marks. Points
outside the image rect are ignored: a backdrop click dismisses, it does
not start a stroke.

## Editor and lightbox chrome

One dimmed overlay, two modes, no sheet and no extra window. One overlay at
a time. Both the new-session composer and the active-session composer host
the same overlay.

**Edit** (click a staged thumbnail): image fitted in the overlay, no zoom.
Toolbar: pen, arrow, rectangle, text, undo. Drag draws with the selected
tool. Click places a text box; Return or click-away commits; Esc while
typing cancels that text. ⌘Z undoes the last stroke. Done writes the draft
stroke list back onto the attachment. Cancel, Esc (when not typing text),
or a click on the dimmed backdrop throws the draft away. Opening another
image implies Cancel on the current draft.

**View** (click any `MessageImageView` in the transcript): same chrome, no
toolbar. Scroll or pinch to zoom, drag to pan, double-click to reset. Esc
or backdrop click closes.

Session change or composer clear closes the overlay.

## Error handling

| Failure | Behavior |
| --- | --- |
| Clipboard has no image | ⌘V is ignored; the editor pastes text if any |
| Image cannot be decoded | Skip it; do not stage an empty attachment |
| Attachment limit (8) | Stage none of the overflow; existing skip line |
| Composite or encode fails at send | Block send; keep draft, attachments, and strokes; red attachment line |
| RPC send fails after composite | Restore the burned attachment (current restore path) |
| Transcript image bytes are unreadable | Existing “Image attachment” label |
| Overlay open across a session switch | Close the overlay; discard any draft |

## Testing

Logic is tested without the window. Chrome is snapshots plus a few state
tests. There are no live-pen compositing tests; that path does not exist.

**`ComposerPasteboard.content`**

Keep the existing cases: PNG-only → images; PNG + text → images; Finder
image URL → image files; `.txt` or plain text → none. Do not revive the
PR #17 key-monitor harness.

**Paste spike (first implementation task)**

Build the current composer, put a real screenshot on the clipboard, focus
the editor, and press ⌘V. Pass: the image stages and a following text
paste still inserts text. Fail: switch to the owned `NSTextView` path
above. A synthetic key event is not this test.

**⌘V routing (after the spike locks a path)**

If the key-router locked: `ComposerCommandKeyRouting` / `handleEditorKey`
— plain ⌘V with image content is `.handled`; text-only, ⌘⇧V, ⌥⌘V, and
bare `v` are `.ignored`. If the `NSTextView` locked: `paste(_:)` stages
images and calls through for text; drive tests with `paste:` /
`sendAction`, not synthetic ⌘V. Classification stays on the pasteboard
helper.

**`ImageMarkup`**

Append pen, arrow, rectangle, and text. Undo pops the last stroke. Undo on
empty is a no-op. Strokes store points in the attachment’s fitted pixel
space.

**View → pixel mapping**

A point in the displayed image rect maps to the same pixel after the
overlay is resized. Points outside the image rect are ignored.

**`ImageMarkupRenderer`**

Send-only. A 2×2 base plus one known stroke produces a pixel change at the
mapped coordinate and nowhere else. Output then runs through the existing
encoder. A stroke-less attachment is not re-encoded.

**`ImagePreviewSession`**

Open edit copies strokes into a draft. Done writes the draft back. Cancel,
Esc, backdrop, or open-another discards the draft. View mode has no draft.
Session change or composer clear closes the overlay.

**Send and transcript**

A marked send’s recorded `PromptImage` is not equal to the unmarked
original. A stroke-less send is byte-identical to today.
`PendingUserSubmission` uses the burned bytes.

**Snapshots** (existing harness, new references)

- Strip with an unmarked thumbnail
- Strip with a vector overlay on a marked thumbnail
- Lightbox edit (toolbar + image)
- Lightbox view (no toolbar)

No per-frame pen-move snapshots.

## Out of scope

- `Edit → Paste` while the `TextEditor` is focused, unless the paste spike
  fails and the owned `NSTextView` path is taken (that path covers the
  menu item as a side effect)
- Color picker, blur, crop, highlighter, or freeform shapes beyond pen /
  arrow / rectangle / text
- Re-editing a sent image
- Keeping the unmarked original after send
- Quick Look or a separate preview window
- Auto-opening the editor on paste, drop, or paperclip
- Replacing `TextEditor` unless the paste spike fails
- Changing the 8-image cap, the 1,568-pixel fit, or the PNG/JPEG budget
- Non-image clipboard content (files still become draft paths)
- Window-local key monitors or any runtime mutation of SwiftUI’s text view

## Implementation notes

- Add new Swift files under `App/` or `Tests/`, then run
  `ruby scripts/generate_xcodeproj.rb`. Do not hand-edit `project.pbxproj`.
- Reuse `TenXPalette` and `TenXTypography`. No new tokens, no shadow, no
  corner radius on the overlay chrome. Markup strokes use `signalRedHex`.
- Closed PR #17 (`ComposerPasteMonitor`) is a classification reference only.
  Do not merge that interceptor onto the current composer.
- The first implementation task is the built-app paste spike. Do not lock
  the key-router, and do not start markup, until that spike is recorded.
- Local `main` may still carry uncommitted paste-monitor files. Leave them
  there. Implement this spec on a branch from current `origin/main`.
