# Composer Image Paste, Markup, and Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Worktree:** `/Users/tannerpham/CS Projects/.worktrees/10x-composer-image-markup-preview` on `tannerpham/composer-image-markup-preview`. Do not edit `/Users/tannerpham/CS Projects/10x`. Local `main` may still carry uncommitted paste-monitor files; leave them there.

**Goal:** Paste a screenshot into the composer with ⌘V, mark it up before send, and open sent images in an in-app lightbox, so the model and the transcript see the same burned pixels.

**Architecture:** Classification is a pasteboard helper. Focused paste is gated by a built-app spike: keep the `onKeyPress` router if a real ⌘V stages an image, otherwise replace the composer `TextEditor` with an owned `NSTextView`. Markup is a stroke list on `ComposerAttachment`, drawn as a vector overlay until Send, then composited once by `ImageMarkupRenderer` and re-encoded with the existing budget. One `ImagePreviewSession` drives a dimmed overlay on `NewSessionView` and `ActiveSessionView` (edit a staged image, or view a sent one).

**Tech Stack:** Swift 6.1, SwiftUI, AppKit, macOS 15+, Swift Testing (`@Test` / `#expect`), generated Xcode project (`ruby scripts/generate_xcodeproj.rb`).

**Spec:** `docs/superpowers/specs/2026-09-05-composer-image-markup-preview-design.md`

## Global Constraints

- Swift 6 with `SWIFT_STRICT_CONCURRENCY = complete`. No `as!`, no force unwraps in production code.
- Platform: macOS 15+, Swift 6.1, SwiftUI.
- Colors come only from `TenXPalette`; fonts only from `TenXTypography`. No new tokens, no shadow, no corner radius on the overlay chrome. Markup strokes use `TenXPalette.signalRedHex`.
- The Xcode project is generated. Membership is static. After creating any new `.swift` file under `App/` or `Tests/`, run `ruby scripts/generate_xcodeproj.rb` immediately, before the next `xcodebuild`. That includes the failing-test file: regenerate before the red `-only-testing` run, and regenerate again after adding any later source file. A red run that executes 0 tests is not a failure and is not a pass; the named test must appear in the log. Never hand-edit `project.pbxproj`.
- Test command: `xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS'`. Filter a single Swift Testing function with `-only-testing:'TenXAppTests/functionName()'` (the trailing parentheses are required).
- Snapshot recording uses the `TEST_RUNNER_` prefix: `TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild test …`.
- Closed PR #17 (`ComposerPasteMonitor`) is a classification reference only. Do not merge that interceptor. Forbidden on every path: a window-local key monitor, an `isa` swap, a `paste:` hook, or any swizzle of `SwiftUI.PlatformTextView`.
- Do not lock the key-router, and do not start markup (Task 4+), until the paste spike is recorded in `docs/superpowers/evidence/2026-09-05-composer-image-paste-spike/README.md`.
- Attachment, drop, paperclip, 8-image cap, 1,568-pixel fit, PNG-or-JPEG budget, and `PromptImage` wire shape stay as they are.
- Paste, drop, and paperclip only stage. Do not auto-open the editor.
- Send is the only composite. Live editor and strip draw the encoded base plus a vector overlay.
- After send there is no unmarked original and no re-edit.
- `TranscriptAnnotation` is a transcript event label. It is not image markup.
- User-facing copy has no em dashes. Error line for a failed composite: `Could not prepare marked images for send.`
- Pasted bitmap name stays `Pasted image`.
- Burned stroke pixels use the literal light `signalRedHex` (`0xFF3B24`) so the model and transcript do not change with appearance. Live overlays use `TenXPalette.color(TenXPalette.signalRedHex)`.

## File Structure

| File | Responsibility |
| --- | --- |
| `App/Sessions/ComposerPasteboard.swift` (create) | Classify a pasteboard: image files, then image data, otherwise none. No event monitor. |
| `Tests/TenXAppTests/ComposerPasteboardTests.swift` (create) | Classification cases from the spec. No key-monitor harness. |
| `docs/superpowers/evidence/2026-09-05-composer-image-paste-spike/README.md` (create) | Built-app spike outcome and which paste path locked. |
| `App/Sessions/ComposerView.swift` (modify) | Stage from classified paste; `handleEditorKey` or owned text view; send-prep error line. |
| `App/Sessions/ComposerPromptTextView.swift` (create only if spike fails) | Owned `NSTextView` representable that overrides `paste(_:)`. |
| `App/Sessions/ComposerPasteKeyRouting.swift` (create only if spike passes) | Pure ⌘V decision: stage vs ignore. |
| `Tests/TenXAppTests/ComposerPasteKeyRoutingTests.swift` (create only if spike passes) | Routing-shape tests after the key-router locks. |
| `Tests/TenXAppTests/ComposerPromptTextViewTests.swift` (create only if spike fails) | `paste(_:)` stages images and calls through for text. |
| `App/Sessions/ImageMarkup.swift` (create) | Tools, strokes, draft undo, view-to-pixel mapping. |
| `Tests/TenXAppTests/ImageMarkupTests.swift` (create) | Append, undo, mapping after resize, ignore outside rect. |
| `App/Sessions/ImageMarkupRenderer.swift` (create) | Send-only `base + strokes → CGImage`. |
| `Tests/TenXAppTests/ImageMarkupRendererTests.swift` (create) | Pixel change at the mapped coordinate. |
| `App/Sessions/ImageMarkupSend.swift` (create) | Prepare attachments for send: identity if no strokes, else composite + existing encoder. |
| `Tests/TenXAppTests/ImageMarkupSendTests.swift` (create) | Byte-identical unmarked send; marked `PromptImage` differs; failure keeps strokes. |
| `App/Sessions/ComposerAttachment.swift` (modify) | Stroke list; `replacingMarkup`. |
| `App/Sessions/ImagePreviewSession.swift` (create) | Which image is open, edit vs view, draft strokes. |
| `Tests/TenXAppTests/ImagePreviewSessionTests.swift` (create) | Open/Done/Cancel/open-another/session-clear. |
| `App/Sessions/ImagePreviewOverlay.swift` (create) | Dimmed overlay chrome, toolbar, viewport. |
| `App/Sessions/ImageMarkupOverlay.swift` (create) | Vector stroke drawing in the displayed image rect. |
| `App/Sessions/ComposerAttachmentsView.swift` (modify) | Click thumbnail to edit; draw markup overlay. |
| `App/Sessions/MessageBlockView.swift` (modify) | `MessageImageView` tap opens view mode. |
| `App/Sessions/MessageBubbleView.swift` (modify) | User-bubble images use the same tap. |
| `App/Sessions/NewSessionView.swift` (modify) | Host the overlay; close on focus-request / clear. |
| `App/Sessions/ActiveSessionView.swift` (modify) | Host the overlay; close on session change / clear. |
| `App/Sessions/SessionController.swift` (modify) | Composite before receipt and RPC; restore burned bytes; `attachmentMessage`. |
| `App/Application/AppModel.swift` (modify) | Composite before `makeSessionController`; `newSessionAttachmentMessage`. |
| `Tests/TenXAppTests/SessionControllerTests.swift` (modify) | `sendPrompt` prepare-failure and RPC-restore integration. |
| `Tests/TenXAppTests/AppModelNavigationTests.swift` (modify) | `startNewSession` prepare-failure and burned-receipt integration. |
| `Tests/TenXAppTests/ViewSnapshotTests.swift` (modify) | Four new references from the spec. |
| `Tests/TenXAppTests/PendingUserSubmissionTests.swift` (modify) | Burned bytes land on the optimistic message. |

Do not create `ComposerPasteMonitor` or any `NSEvent.addLocalMonitorForEvents` helper.

---

### Task 1: Classify the pasteboard

**Files:**
- Create: `App/Sessions/ComposerPasteboard.swift`
- Create: `Tests/TenXAppTests/ComposerPasteboardTests.swift`
- Modify: `10x.xcodeproj/project.pbxproj` via `ruby scripts/generate_xcodeproj.rb` only

**Interfaces:**
- Consumes: `ComposerAttachmentEncoder.isImage(_:)`, `NSPasteboard`.
- Produces:
  - `enum ComposerPasteboard.Content` with `imageFiles([URL])`, `images([NSImage])`, `none`
  - `static func content(of pasteboard: NSPasteboard) -> Content`

Classification order is a product rule: image files first (so a Finder copy keeps its name), then image data, otherwise none. A `.txt` file URL or plain text is `none`. PNG plus text is still `images`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TenXAppTests/ComposerPasteboardTests.swift`:

```swift
import AppKit
import Testing
@testable import TenXApp

@Test func anImageOnTheClipboardStagesAsImageData() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.setData(try solidPNG(width: 8, height: 8), forType: .png)

    guard case .images(let images) = ComposerPasteboard.content(of: pasteboard) else {
        Issue.record("expected image data, got \(ComposerPasteboard.content(of: pasteboard))")
        return
    }
    #expect(images.count == 1)
}

@Test func anImageCopiedWithTextStillStagesTheImage() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.setData(try solidPNG(width: 8, height: 8), forType: .png)
    pasteboard.setString("https://example.com/image.png", forType: .string)

    guard case .images = ComposerPasteboard.content(of: pasteboard) else {
        Issue.record("expected image data, got \(ComposerPasteboard.content(of: pasteboard))")
        return
    }
}

@Test func anImageFileCopiedInFinderStagesTheFile() {
    let url = URL(filePath: "/tmp/screenshot.png")
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.writeObjects([url as NSURL])

    guard case .imageFiles(let urls) = ComposerPasteboard.content(of: pasteboard) else {
        Issue.record("expected image files, got \(ComposerPasteboard.content(of: pasteboard))")
        return
    }
    #expect(urls == [url])
}

@Test func aNonImageFilePasteIsLeftToTheEditor() {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.writeObjects([URL(filePath: "/tmp/notes.txt") as NSURL])

    guard case .none = ComposerPasteboard.content(of: pasteboard) else {
        Issue.record("expected none, got \(ComposerPasteboard.content(of: pasteboard))")
        return
    }
}

@Test func plainTextPasteIsLeftToTheEditor() {
    let pasteboard = NSPasteboard.withUniqueName()
    pasteboard.clearContents()
    pasteboard.setString("hello", forType: .string)

    guard case .none = ComposerPasteboard.content(of: pasteboard) else {
        Issue.record("expected none, got \(ComposerPasteboard.content(of: pasteboard))")
        return
    }
}

private func solidPNG(width: Int, height: Int) throws -> Data {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.unlockFocus()
    let tiff = try #require(image.tiffRepresentation)
    let representation = try #require(NSBitmapImageRep(data: tiff))
    return try #require(representation.representation(using: .png, properties: [:]))
}
```

Do not add `isPasteShortcut`, `ComposerPasteMonitor`, or any window harness.

- [ ] **Step 2: Generate the project, then run tests to verify they fail**

The new test file is not in the target until the project is regenerated. Run this generate before the red `xcodebuild`. A run that executes 0 tests is not a red result.

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/anImageOnTheClipboardStagesAsImageData()'
```

Expected: the named test runs and fails to compile, `cannot find 'ComposerPasteboard' in scope`.

- [ ] **Step 3: Write the implementation**

Create `App/Sessions/ComposerPasteboard.swift`:

```swift
import AppKit

enum ComposerPasteboard {
    enum Content {
        case imageFiles([URL])
        case images([NSImage])
        case none
    }

    static func content(of pasteboard: NSPasteboard) -> Content {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL],
           urls.contains(where: { ComposerAttachmentEncoder.isImage($0) }) {
            return .imageFiles(urls)
        }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           images.isEmpty == false {
            return .images(images)
        }
        return .none
    }
}
```

Do not add `Equatable` on `Content`. Tests use `guard case`. `NSImage` is not `Equatable`.

- [ ] **Step 4: Generate the project again, then run the tests**

Step 3 added a source file that is not yet in the target. Regenerate before this pass run.

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/anImageOnTheClipboardStagesAsImageData()' \
  -only-testing:'TenXAppTests/anImageCopiedWithTextStillStagesTheImage()' \
  -only-testing:'TenXAppTests/anImageFileCopiedInFinderStagesTheFile()' \
  -only-testing:'TenXAppTests/aNonImageFilePasteIsLeftToTheEditor()' \
  -only-testing:'TenXAppTests/plainTextPasteIsLeftToTheEditor()'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/ComposerPasteboard.swift \
  Tests/TenXAppTests/ComposerPasteboardTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(composer): classify clipboard images without a key monitor

Finder image URLs win over bitmap data so a copied file keeps its name.
Text and non-image files stay none so the editor can paste them.
EOF
)"
```

---

### Task 2: Built-app paste spike (gate)

**Files:**
- Modify: `App/Sessions/ComposerView.swift`
- Create: `docs/superpowers/evidence/2026-09-05-composer-image-paste-spike/README.md`

**Interfaces:**
- Consumes: `ComposerPasteboard.content(of:)`, existing `add(urls:)`, existing `ComposerAttachmentEncoder.attachment(from:name:)`.
- Produces: a probe in `handleEditorKey` that stages image content on plain ⌘V; an evidence note that locks Task 3A or Task 3B.

This is a real screenshot and a real ⌘V in a built app. A synthetic `NSEvent` sent through `NSApp.sendEvent` is not this test. Do not add routing-shape unit tests yet.

- [ ] **Step 1: Add staging helpers and the key-router probe**

In `ComposerView`, next to `add(urls:)` / `add(providers:)`:

```swift
    fileprivate func add(images: [NSImage]) {
        var skipped: [String] = []
        for image in images {
            guard attachments.count < ComposerAttachmentEncoder.maximumCount else {
                skipped.append("Pasted image")
                continue
            }
            guard let attachment = ComposerAttachmentEncoder.attachment(
                from: image,
                name: "Pasted image")
            else {
                skipped.append("Pasted image")
                continue
            }
            attachments.append(attachment)
        }
        report(skipped: skipped)
    }

    fileprivate func add(pasteboardContent: ComposerPasteboard.Content) {
        switch pasteboardContent {
        case .imageFiles(let urls):
            add(urls: urls)
        case .images(let images):
            add(images: images)
        case .none:
            break
        }
    }
```

Add `KeyEquivalent("v")` to `ComposerCommandKeyRouting.keys`.

In `handleEditorKey`, after the command-browser branch and before the Return guard:

```swift
        if press.key == KeyEquivalent("v") {
            let relevant = press.modifiers.intersection([.command, .shift, .option, .control])
            if relevant == [.command] {
                let content = ComposerPasteboard.content(of: .general)
                switch content {
                case .images, .imageFiles:
                    add(pasteboardContent: content)
                    return .handled
                case .none:
                    return .ignored
                }
            }
            return .ignored
        }
```

Keep `.onPasteCommand(of: [.png, .jpeg, .tiff])` as the unfocused fallback.

- [ ] **Step 2: Build a Debug app from this worktree**

```bash
xcodebuild -project 10x.xcodeproj -scheme 10x -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/10x-image-markup-spike \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Expected: `BUILD SUCCEEDED`. Launch the binary directly, not `open`, so another worktree's instance is not activated:

```bash
/tmp/10x-image-markup-spike/Build/Products/Debug/10x.app/Contents/MacOS/10x
```

Confirm the window is visible before claiming the spike can be run. Record the commit SHA in the evidence file.

- [ ] **Step 3: Run the real paste cases**

With the composer editor first responder (caret blinking in Describe the task or Send a message):

1. Copy a real screenshot. Press Command-V. The strip must show a `Pasted image` thumbnail.
2. Copy a short string. Press Command-V. The string must insert into the draft. Existing staged images stay.
3. Press Command-Shift-V, Option-Command-V, and type `v`. Those must not stage an image.

Do not treat a synthetic key event as a substitute.

- [ ] **Step 4: Record the outcome**

Write `docs/superpowers/evidence/2026-09-05-composer-image-paste-spike/README.md` with: date, commit SHA, `PASS` or `FAIL`, locked path (`key-router` or `owned-nstextview`), and what each real keypress did.

**Spike pass:** focused ⌘V stages the image and a following text paste still inserts text. Lock `key-router` and continue to Task 3A. Skip Task 3B.

**Spike fail:** a real focused ⌘V never reaches `.onKeyPress`, image paste still does nothing, or text paste breaks. Lock `owned-nstextview`, revert the `handleEditorKey` probe and the extra `KeyEquivalent("v")` if they do nothing useful, and continue to Task 3B. Skip Task 3A.

- [ ] **Step 5: Commit**

If PASS, commit the probe plus the evidence. If FAIL, commit the evidence and the revert of a useless probe.

```bash
git add App/Sessions/ComposerView.swift \
  docs/superpowers/evidence/2026-09-05-composer-image-paste-spike/README.md
git commit -m "$(cat <<'EOF'
test(composer): record the built-app image paste spike

A synthetic Command-V is not proof. This commit records whether a
focused TextEditor saw a real screenshot paste so routing can lock
one path.
EOF
)"
```

Stop. Do not start Task 4 until this evidence file exists and names a locked path.

---

### Task 3A: Lock the key-router (only if the spike passed)

**Files:**
- Create: `App/Sessions/ComposerPasteKeyRouting.swift`
- Create: `Tests/TenXAppTests/ComposerPasteKeyRoutingTests.swift`
- Modify: `App/Sessions/ComposerView.swift`

**Interfaces:**
- Consumes: `ComposerPasteboard.Content`, `KeyEquivalent`, `EventModifiers`.
- Produces:
  - `enum ComposerPasteKeyRouting.Decision: Equatable { case stage, ignore }`
  - `static func decision(key: KeyEquivalent, modifiers: EventModifiers, content: ComposerPasteboard.Content) -> Decision`

- [ ] **Step 1: Write the failing tests**

Create `Tests/TenXAppTests/ComposerPasteKeyRoutingTests.swift`:

```swift
import AppKit
import SwiftUI
import Testing
@testable import TenXApp

@Test func plainCommandVWithImageContentIsHandled() {
    #expect(
        ComposerPasteKeyRouting.decision(
            key: KeyEquivalent("v"),
            modifiers: [.command],
            content: .images([NSImage()])) == .stage)
    #expect(
        ComposerPasteKeyRouting.decision(
            key: KeyEquivalent("v"),
            modifiers: [.command],
            content: .imageFiles([URL(filePath: "/tmp/a.png")])) == .stage)
}

@Test func textOnlyCommandVIsIgnored() {
    #expect(
        ComposerPasteKeyRouting.decision(
            key: KeyEquivalent("v"),
            modifiers: [.command],
            content: .none) == .ignore)
}

@Test func shiftedOptionedOrBareVIsIgnored() {
    #expect(
        ComposerPasteKeyRouting.decision(
            key: KeyEquivalent("v"),
            modifiers: [.command, .shift],
            content: .images([NSImage()])) == .ignore)
    #expect(
        ComposerPasteKeyRouting.decision(
            key: KeyEquivalent("v"),
            modifiers: [.command, .option],
            content: .images([NSImage()])) == .ignore)
    #expect(
        ComposerPasteKeyRouting.decision(
            key: KeyEquivalent("v"),
            modifiers: [],
            content: .images([NSImage()])) == .ignore)
}
```

- [ ] **Step 2: Generate the project, then run tests to verify they fail**

The new test file is not in the target until the project is regenerated. Run this generate before the red `xcodebuild`. A run that executes 0 tests is not a red result.

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/plainCommandVWithImageContentIsHandled()'
```

Expected: the named test runs and fails to compile, `cannot find 'ComposerPasteKeyRouting' in scope`.

- [ ] **Step 3: Write the implementation and call it from `handleEditorKey`**

Create `App/Sessions/ComposerPasteKeyRouting.swift`:

```swift
import SwiftUI

enum ComposerPasteKeyRouting {
    enum Decision: Equatable, Sendable {
        case stage
        case ignore
    }

    static func decision(
        key: KeyEquivalent,
        modifiers: EventModifiers,
        content: ComposerPasteboard.Content
    ) -> Decision {
        guard key == KeyEquivalent("v") else { return .ignore }
        let relevant = modifiers.intersection([.command, .shift, .option, .control])
        guard relevant == [.command] else { return .ignore }
        switch content {
        case .images, .imageFiles:
            return .stage
        case .none:
            return .ignore
        }
    }
}
```

Replace the Task 2 inline probe in `handleEditorKey` with:

```swift
        let pasteContent = ComposerPasteboard.content(of: .general)
        if ComposerPasteKeyRouting.decision(
            key: press.key,
            modifiers: press.modifiers,
            content: pasteContent) == .stage
        {
            add(pasteboardContent: pasteContent)
            return .handled
        }
```

`KeyEquivalent("v")` stays in `ComposerCommandKeyRouting.keys`. `.onPasteCommand` stays.

- [ ] **Step 4: Generate the project again, then run the tests**

Step 3 added a source file that is not yet in the target. Regenerate before this pass run.

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/plainCommandVWithImageContentIsHandled()' \
  -only-testing:'TenXAppTests/textOnlyCommandVIsIgnored()' \
  -only-testing:'TenXAppTests/shiftedOptionedOrBareVIsIgnored()'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/ComposerPasteKeyRouting.swift \
  App/Sessions/ComposerView.swift \
  Tests/TenXAppTests/ComposerPasteKeyRoutingTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(composer): stage focused image paste through the key router

Plain Command-V with image content is handled and staged. Text-only
Command-V, shifted or optioned V, and typing v stay ignored.
EOF
)"
```

---

### Task 3B: Lock the owned NSTextView (only if the spike failed)

**Files:**
- Create: `App/Sessions/ComposerPromptTextView.swift`
- Create: `Tests/TenXAppTests/ComposerPromptTextViewTests.swift`
- Modify: `App/Sessions/ComposerView.swift`

**Interfaces:**
- Consumes: `ComposerPasteboard.content(of:)`, existing height overlay, focus, Return routing, command-browser keys.
- Produces:
  - `final class ComposerPromptTextView: NSTextView` with `var onPasteImages: ((ComposerPasteboard.Content) -> Void)?`
  - `override func paste(_ sender: Any?)`
  - `struct ComposerPromptEditor: NSViewRepresentable`

Drive tests with `paste(_:)`, not synthetic Command-V. This path also covers Edit → Paste.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TenXAppTests/ComposerPromptTextViewTests.swift`. Restore `NSPasteboard.general` in `defer` because `NSTextView.paste` reads it:

```swift
import AppKit
import Testing
@testable import TenXApp

@MainActor
@Test func pasteStagesClipboardImagesAndDoesNotInsertThemAsText() throws {
    let pasteboard = NSPasteboard.general
    let previous = pasteboard.pasteboardItems
    pasteboard.clearContents()
    pasteboard.setData(try solidPNG(width: 8, height: 8), forType: .png)
    defer {
        pasteboard.clearContents()
        if let previous { pasteboard.writeObjects(previous) }
    }

    let view = ComposerPromptTextView(usingTextLayoutManager: false)
    var staged: ComposerPasteboard.Content?
    view.onPasteImages = { staged = $0 }
    view.paste(nil)

    guard case .images(let images) = staged else {
        Issue.record("expected images, got \(String(describing: staged))")
        return
    }
    #expect(images.isEmpty == false)
    #expect(view.string.isEmpty)
}

@MainActor
@Test func pasteInsertsPlainTextThroughTheTextView() {
    let pasteboard = NSPasteboard.general
    let previous = pasteboard.pasteboardItems
    pasteboard.clearContents()
    pasteboard.setString("hello paste", forType: .string)
    defer {
        pasteboard.clearContents()
        if let previous { pasteboard.writeObjects(previous) }
    }

    let view = ComposerPromptTextView(usingTextLayoutManager: false)
    var staged: ComposerPasteboard.Content?
    view.onPasteImages = { staged = $0 }
    view.paste(nil)

    #expect(staged == nil)
    #expect(view.string == "hello paste")
}

private func solidPNG(width: Int, height: Int) throws -> Data {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.unlockFocus()
    let tiff = try #require(image.tiffRepresentation)
    let representation = try #require(NSBitmapImageRep(data: tiff))
    return try #require(representation.representation(using: .png, properties: [:]))
}
```

- [ ] **Step 2: Generate the project, then run tests to verify they fail**

The new test file is not in the target until the project is regenerated. Run this generate before the red `xcodebuild`. A run that executes 0 tests is not a red result.

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/pasteStagesClipboardImagesAndDoesNotInsertThemAsText()'
```

Expected: the named test runs and fails to compile, `cannot find 'ComposerPromptTextView' in scope`.

- [ ] **Step 3: Write the text view and swap it for `TextEditor`**

Create `App/Sessions/ComposerPromptTextView.swift` with:

- `ComposerPromptTextView.paste(_:)` classifying via `ComposerPasteboard.content(of: .general)`. Images and image files call `onPasteImages` and return. `none` calls `super.paste`.
- `keyDown(with:)` mapping Return, Escape, Tab, arrows, page/home/end, and single characters to `KeyEquivalent` / `EventModifiers`. If `onHandleKey` returns true, do not call super.
- `ComposerPromptEditor: NSViewRepresentable` wrapping the text view in an `NSScrollView`, binding `string` through `NSTextViewDelegate.textDidChange`, disabling quote/dash/text substitutions, font 14, no rich text.

In `ComposerView.editor`, replace `TextEditor(text: $draft)` with `ComposerPromptEditor` that calls `add(pasteboardContent:)` and `handleEditorKey(key:modifiers:)`. Keep the hidden measuring `Text`, focus task, Return routing, and command-browser routing. Drop `ComposerTextViewConfigurator` from this editor. Remove `KeyEquivalent("v")` from `ComposerCommandKeyRouting.keys` if it was only the failed probe.

- [ ] **Step 4: Generate the project again, then run the tests**

Step 3 added a source file that is not yet in the target. Regenerate before this pass run.

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/pasteStagesClipboardImagesAndDoesNotInsertThemAsText()' \
  -only-testing:'TenXAppTests/pasteInsertsPlainTextThroughTheTextView()'
```

Expected: PASS. Re-run the built-app screenshot Command-V from Task 2 against this path and add a one-line confirmation to the evidence file.

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/ComposerPromptTextView.swift \
  App/Sessions/ComposerView.swift \
  Tests/TenXAppTests/ComposerPromptTextViewTests.swift \
  docs/superpowers/evidence/2026-09-05-composer-image-paste-spike/README.md \
  10x.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(composer): paste images through an owned NSTextView

The key-router never saw a focused Command-V. paste(_:) stages
image content and calls through for text, which also covers
Edit -> Paste.
EOF
)"
```

---

### Task 4: Markup strokes, undo, and view-to-pixel mapping

**Files:**
- Create: `App/Sessions/ImageMarkup.swift`
- Create: `Tests/TenXAppTests/ImageMarkupTests.swift`

**Interfaces:**
- Consumes: `CGPoint`, `CGSize`, `CGRect`.
- Produces:
  - `enum ImageMarkupTool: String, Equatable, Sendable { case pen, arrow, rectangle, text }`
  - `enum ImageMarkupStroke: Equatable, Sendable`
  - `struct ImageMarkupDraft: Equatable, Sendable` with `append` and `undo`
  - `enum ImageMarkupGeometry` with `displayedRect`, `pixel(from:)`, `viewPoint(from:)`

Points are stored in the attachment's fitted pixel space. `(0, 0)` is the top-left of the fitted bitmap. `+x` is right, `+y` is down.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TenXAppTests/ImageMarkupTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import TenXApp

@Test func draftAppendsEveryToolAndUndoPopsTheLastStroke() {
    var draft = ImageMarkupDraft()
    draft.append(.pen(points: [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)]))
    draft.append(.arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 10)))
    draft.append(.rectangle(origin: CGPoint(x: 2, y: 3), size: CGSize(width: 4, height: 5)))
    draft.append(.text(origin: CGPoint(x: 8, y: 8), value: "here"))
    #expect(draft.strokes.count == 4)

    draft.undo()
    #expect(draft.strokes.count == 3)
    guard case .rectangle = draft.strokes.last else {
        Issue.record("expected rectangle to remain after undo")
        return
    }

    draft.undo()
    draft.undo()
    draft.undo()
    draft.undo()
    #expect(draft.strokes.isEmpty)
}

@Test func aPointInTheDisplayedRectMapsToTheSamePixelAfterResize() {
    let imageSize = CGSize(width: 100, height: 50)
    let small = ImageMarkupGeometry.displayedRect(imageSize: imageSize, in: CGSize(width: 200, height: 100))
    let large = ImageMarkupGeometry.displayedRect(imageSize: imageSize, in: CGSize(width: 400, height: 200))
    let smallPixel = ImageMarkupGeometry.pixel(
        from: CGPoint(x: small.midX, y: small.midY), imageSize: imageSize, displayedRect: small)
    let largePixel = ImageMarkupGeometry.pixel(
        from: CGPoint(x: large.midX, y: large.midY), imageSize: imageSize, displayedRect: large)
    #expect(smallPixel != nil)
    #expect(largePixel != nil)
    #expect(smallPixel?.x == largePixel?.x)
    #expect(smallPixel?.y == largePixel?.y)
}

@Test func aPointOutsideTheDisplayedRectIsIgnored() {
    let imageSize = CGSize(width: 100, height: 50)
    let rect = ImageMarkupGeometry.displayedRect(imageSize: imageSize, in: CGSize(width: 200, height: 200))
    let outside = CGPoint(x: 1, y: 1)
    #expect(rect.contains(outside) == false)
    #expect(ImageMarkupGeometry.pixel(from: outside, imageSize: imageSize, displayedRect: rect) == nil)
}
```

- [ ] **Step 2: Generate the project, then run tests to verify they fail**

The new test file is not in the target until the project is regenerated. Run this generate before the red `xcodebuild`. A run that executes 0 tests is not a red result.

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/draftAppendsEveryToolAndUndoPopsTheLastStroke()'
```

Expected: the named test runs and fails to compile, `cannot find 'ImageMarkupDraft' in scope`.

- [ ] **Step 3: Write the implementation**

Create `App/Sessions/ImageMarkup.swift`:

```swift
import CoreGraphics
import Foundation

enum ImageMarkupTool: String, Equatable, Sendable {
    case pen
    case arrow
    case rectangle
    case text
}

enum ImageMarkupStroke: Equatable, Sendable {
    case pen(points: [CGPoint])
    case arrow(start: CGPoint, end: CGPoint)
    case rectangle(origin: CGPoint, size: CGSize)
    case text(origin: CGPoint, value: String)
}

struct ImageMarkupDraft: Equatable, Sendable {
    var strokes: [ImageMarkupStroke] = []

    mutating func append(_ stroke: ImageMarkupStroke) {
        strokes.append(stroke)
    }

    mutating func undo() {
        _ = strokes.popLast()
    }
}

enum ImageMarkupGeometry {
    static func displayedRect(imageSize: CGSize, in bounds: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return .zero
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2,
            width: width,
            height: height)
    }

    static func pixel(
        from viewPoint: CGPoint,
        imageSize: CGSize,
        displayedRect: CGRect
    ) -> CGPoint? {
        guard displayedRect.width > 0, displayedRect.height > 0, displayedRect.contains(viewPoint) else {
            return nil
        }
        return CGPoint(
            x: (viewPoint.x - displayedRect.minX) / displayedRect.width * imageSize.width,
            y: (viewPoint.y - displayedRect.minY) / displayedRect.height * imageSize.height)
    }

    static func viewPoint(
        from pixel: CGPoint,
        imageSize: CGSize,
        displayedRect: CGRect
    ) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return displayedRect.origin }
        return CGPoint(
            x: displayedRect.minX + pixel.x / imageSize.width * displayedRect.width,
            y: displayedRect.minY + pixel.y / imageSize.height * displayedRect.height)
    }
}
```

- [ ] **Step 4: Generate the project again, then run the tests**

Step 3 added a source file that is not yet in the target. Regenerate before this pass run.

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/draftAppendsEveryToolAndUndoPopsTheLastStroke()' \
  -only-testing:'TenXAppTests/aPointInTheDisplayedRectMapsToTheSamePixelAfterResize()' \
  -only-testing:'TenXAppTests/aPointOutsideTheDisplayedRectIsIgnored()'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/ImageMarkup.swift \
  Tests/TenXAppTests/ImageMarkupTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(composer): store image markup in fitted pixel space

Pen, arrow, rectangle, and text append to a draft. Undo pops the
last stroke. View points map through the displayed rect so a
resize cannot drift the marks.
EOF
)"
```

---

### Task 5: Send-only markup renderer

**Files:**
- Create: `App/Sessions/ImageMarkupRenderer.swift`
- Create: `Tests/TenXAppTests/ImageMarkupRendererTests.swift`

**Interfaces:**
- Consumes: `ImageMarkupStroke`, `TenXPalette.signalRedHex`.
- Produces: `static func render(base: CGImage, strokes: [ImageMarkupStroke]) -> CGImage?`

Called only at send. Live views never call it. `(0, 0)` is top-left. Disable antialiasing so a 2x2 test can name a single pixel. Burn literal light `0xFF3B24`, not the dark counterpart. Do not add a public `TenXPalette.nsColor`; that helper is private.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TenXAppTests/ImageMarkupRendererTests.swift`:

```swift
import AppKit
import CoreGraphics
import Testing
@testable import TenXApp

@Test func aKnownStrokeChangesOnlyTheMappedPixel() throws {
    let base = try #require(solidCGImage(width: 2, height: 2, color: .white))
    let rendered = try #require(
        ImageMarkupRenderer.render(
            base: base,
            strokes: [.rectangle(origin: CGPoint(x: 1, y: 0), size: CGSize(width: 1, height: 1))]))
    #expect(rendered.width == 2)
    #expect(rendered.height == 2)
    #expect(pixel(rendered, x: 1, y: 0) != pixel(base, x: 1, y: 0))
    #expect(pixel(rendered, x: 0, y: 0) == pixel(base, x: 0, y: 0))
    #expect(pixel(rendered, x: 0, y: 1) == pixel(base, x: 0, y: 1))
    #expect(pixel(rendered, x: 1, y: 1) == pixel(base, x: 1, y: 1))
}

@Test func renderingLeavesTheBaseSizeUnchanged() throws {
    let base = try #require(solidCGImage(width: 4, height: 2, color: .white))
    let rendered = try #require(
        ImageMarkupRenderer.render(
            base: base,
            strokes: [.pen(points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)])]))
    #expect(rendered.width == 4)
    #expect(rendered.height == 2)
}

private func solidCGImage(width: Int, height: Int, color: NSColor) throws -> CGImage {
    let representation = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    color.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()
    return try #require(representation.cgImage)
}

private func pixel(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
    var values: [UInt8] = [0, 0, 0, 0]
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: &values,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return (0, 0, 0, 0) }
    context.interpolationQuality = .none
    context.draw(
        image,
        in: CGRect(x: -CGFloat(x), y: CGFloat(y) - CGFloat(image.height) + 1,
                   width: CGFloat(image.width), height: CGFloat(image.height)))
    return (values[0], values[1], values[2], values[3])
}
```

If the sampler origin is off by a flip, fix `pixel(_:x:y:)` so it samples the same space the renderer writes. Do not loosen the test to "any pixel changed."

- [ ] **Step 2: Generate the project, then run tests to verify they fail**

The new test file is not in the target until the project is regenerated. Run this generate before the red `xcodebuild`. A run that executes 0 tests is not a red result.

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/aKnownStrokeChangesOnlyTheMappedPixel()'
```

Expected: the named test runs and fails to compile, `cannot find 'ImageMarkupRenderer' in scope`.

- [ ] **Step 3: Write the implementation**

Create `App/Sessions/ImageMarkupRenderer.swift`. Draw `base` into a same-size context, flip to top-left pixel space, disable antialiasing, stroke in `NSColor(srgbRed: 1, green: 59.0/255, blue: 36.0/255, alpha: 1)` (`signalRedHex`). 

- `.pen`: one point fills a 1x1; two or more points stroke a polyline of width 1.
- `.arrow`: line plus a 6-pixel head.
- `.rectangle`: stroke the integral rect. A 1x1 also fills so the 2x2 test paints exactly that pixel.
- `.text`: `NSAttributedString` at 14pt medium, same red, drawn with a flipped `NSGraphicsContext`.

- [ ] **Step 4: Generate the project again, then run the tests**

Step 3 added a source file that is not yet in the target. Regenerate before this pass run.

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/aKnownStrokeChangesOnlyTheMappedPixel()' \
  -only-testing:'TenXAppTests/renderingLeavesTheBaseSizeUnchanged()'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/ImageMarkupRenderer.swift \
  Tests/TenXAppTests/ImageMarkupRendererTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(composer): composite markup into pixels only at send

The renderer draws signal-red strokes onto the fitted base. Live
views never call it. A 2x2 fixture changes only the mapped pixel.
EOF
)"
```

---

### Task 6: Attachment strokes and send preparation

**Files:**
- Modify: `App/Sessions/ComposerAttachment.swift`
- Create: `App/Sessions/ImageMarkupSend.swift`
- Create: `Tests/TenXAppTests/ImageMarkupSendTests.swift`
- Modify: `Tests/TenXAppTests/PendingUserSubmissionTests.swift`

**Interfaces:**
- Consumes: `ComposerAttachment`, `ImageMarkupRenderer.render`, `ComposerAttachmentEncoder.attachment(from:name:)`.
- Produces:
  - `ComposerAttachment.markup: [ImageMarkupStroke]` default `[]`
  - `func replacingMarkup(_ strokes: [ImageMarkupStroke]) -> ComposerAttachment`
  - `enum ImageMarkupSend.Failure { case compositeFailed, encodeFailed }`
  - `static func prepare(_ attachments: [ComposerAttachment]) -> Result<[ComposerAttachment], ImageMarkupSend.Failure>`

`snapshotAttachment` and `ComposerAttachmentEncoder` keep compiling because `markup` defaults to `[]`. After a successful composite the returned attachment keeps the same `id` and `name`, has empty `markup`, and new `data` / `mimeType` / pixel size from the existing encoder.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TenXAppTests/ImageMarkupSendTests.swift`:

```swift
import AppKit
import Testing
@testable import TenXApp

@MainActor
@Test func aStrokeLessAttachmentIsNotReencoded() throws {
    let original = try #require(ComposerAttachmentEncoder.attachment(
        from: solidImage(width: 16, height: 12),
        name: "plain.png"))
    let prepared = try ImageMarkupSend.prepare([original]).get()
    #expect(prepared.count == 1)
    #expect(prepared[0].id == original.id)
    #expect(prepared[0].data == original.data)
    #expect(prepared[0].mimeType == original.mimeType)
    #expect(prepared[0].markup.isEmpty)
}

@MainActor
@Test func aMarkedSendProducesDifferentPromptImageBytes() throws {
    let original = try #require(ComposerAttachmentEncoder.attachment(
        from: solidImage(width: 16, height: 12),
        name: "marked.png"))
    let marked = original.replacingMarkup([
        .rectangle(origin: CGPoint(x: 1, y: 1), size: CGSize(width: 4, height: 4))
    ])
    let prepared = try ImageMarkupSend.prepare([marked]).get()
    #expect(prepared[0].data != original.data)
    #expect(prepared[0].promptImage != original.promptImage)
    #expect(prepared[0].markup.isEmpty)
    #expect(prepared[0].id == original.id)
}

@MainActor
@Test func pendingSubmissionUsesThePreparedBytes() throws {
    let original = try #require(ComposerAttachmentEncoder.attachment(
        from: solidImage(width: 16, height: 12),
        name: "pending.png"))
    let marked = original.replacingMarkup([
        .rectangle(origin: CGPoint(x: 1, y: 1), size: CGSize(width: 4, height: 4))
    ])
    let prepared = try ImageMarkupSend.prepare([marked]).get()
    let receipt = PendingUserSubmission(
        text: "look",
        attachments: prepared,
        minimumUserIndex: 0,
        state: .sending)
    #expect(receipt.message.document.images.count == 1)
    #expect(receipt.message.document.images[0].data == prepared[0].data)
    #expect(receipt.message.document.images[0].data != original.data)
}

@MainActor
private func solidImage(width: Int, height: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor.systemTeal.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.unlockFocus()
    return image
}
```

- [ ] **Step 2: Generate the project, then run tests to verify they fail**

The new test file is not in the target until the project is regenerated. Run this generate before the red `xcodebuild`. A run that executes 0 tests is not a red result.

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/aStrokeLessAttachmentIsNotReencoded()'
```

Expected: the named test runs and fails to compile, `cannot find 'ImageMarkupSend' in scope` or `has no member 'replacingMarkup'`.

- [ ] **Step 3: Write the implementation**

Add to `ComposerAttachment` (all existing fields stay `let`):

```swift
    let markup: [ImageMarkupStroke]

    init(
        id: UUID = UUID(),
        name: String,
        data: Data,
        mimeType: String,
        pixelWidth: Int,
        pixelHeight: Int,
        markup: [ImageMarkupStroke] = []
    ) {
        self.id = id
        self.name = name
        self.data = data
        self.mimeType = mimeType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.markup = markup
    }

    func replacingMarkup(_ strokes: [ImageMarkupStroke]) -> ComposerAttachment {
        ComposerAttachment(
            id: id, name: name, data: data, mimeType: mimeType,
            pixelWidth: pixelWidth, pixelHeight: pixelHeight, markup: strokes)
    }
```

Create `App/Sessions/ImageMarkupSend.swift`:

```swift
import AppKit

enum ImageMarkupSend {
    enum Failure: Equatable, Sendable {
        case compositeFailed
        case encodeFailed
    }

    static func prepare(
        _ attachments: [ComposerAttachment]
    ) -> Result<[ComposerAttachment], Failure> {
        var prepared: [ComposerAttachment] = []
        prepared.reserveCapacity(attachments.count)
        for attachment in attachments {
            if attachment.markup.isEmpty {
                prepared.append(attachment)
                continue
            }
            guard
                let image = NSImage(data: attachment.data),
                let base = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                let rendered = ImageMarkupRenderer.render(base: base, strokes: attachment.markup)
            else { return .failure(.compositeFailed) }
            let nsImage = NSImage(
                cgImage: rendered,
                size: NSSize(width: rendered.width, height: rendered.height))
            guard let encoded = ComposerAttachmentEncoder.attachment(
                from: nsImage,
                name: attachment.name)
            else { return .failure(.encodeFailed) }
            prepared.append(
                ComposerAttachment(
                    id: attachment.id,
                    name: attachment.name,
                    data: encoded.data,
                    mimeType: encoded.mimeType,
                    pixelWidth: encoded.pixelWidth,
                    pixelHeight: encoded.pixelHeight,
                    markup: []))
        }
        return .success(prepared)
    }
}
```

- [ ] **Step 4: Generate the project again, then run the tests**

Step 3 added a source file that is not yet in the target. Regenerate before this pass run.

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/aStrokeLessAttachmentIsNotReencoded()' \
  -only-testing:'TenXAppTests/aMarkedSendProducesDifferentPromptImageBytes()' \
  -only-testing:'TenXAppTests/pendingSubmissionUsesThePreparedBytes()'
```

Expected: PASS. Existing `ComposerAttachmentTests` still compile because `markup` defaults to `[]`.

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/ComposerAttachment.swift \
  App/Sessions/ImageMarkupSend.swift \
  Tests/TenXAppTests/ImageMarkupSendTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(composer): prepare marked attachments only at send

Unmarked bytes stay identical. Marked attachments composite once,
re-encode with the existing budget, and drop the stroke list.
EOF
)"
```

---

### Task 7: Preview session state

**Files:**
- Create: `App/Sessions/ImagePreviewSession.swift`
- Create: `Tests/TenXAppTests/ImagePreviewSessionTests.swift`

**Interfaces:**
- Consumes: `ComposerAttachment.ID`, `ImageMarkupStroke`, `ContentImage`.
- Produces: `struct ImagePreviewSession: Equatable` with `openEdit`, `openView`, `commit`, `cancel`, `close`.

View mode has no draft. Opening another image implies Cancel on the current draft.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TenXAppTests/ImagePreviewSessionTests.swift`:

```swift
import Foundation
import Testing
@testable import TenXApp

@Test func openEditCopiesStrokesIntoADraftAndDoneWritesThemBack() {
    var session = ImagePreviewSession()
    let id = UUID()
    let existing: [ImageMarkupStroke] = [
        .text(origin: CGPoint(x: 4, y: 5), value: "old")
    ]
    session.openEdit(attachmentID: id, strokes: existing)
    #expect(session.showsToolbar)
    session.draft.append(.pen(points: [CGPoint(x: 1, y: 1)]))
    let committed = session.commit()
    #expect(committed?.attachmentID == id)
    #expect(committed?.strokes.count == 2)
    #expect(session.isOpen == false)
}

@Test func cancelEscBackdropOrOpenAnotherDiscardsTheDraft() {
    var session = ImagePreviewSession()
    let first = UUID()
    session.openEdit(attachmentID: first, strokes: [])
    session.draft.append(.arrow(start: .zero, end: CGPoint(x: 2, y: 2)))
    session.cancel()
    #expect(session.isOpen == false)
    #expect(session.draft.strokes.isEmpty)

    session.openEdit(attachmentID: first, strokes: [])
    session.draft.append(.rectangle(origin: .zero, size: CGSize(width: 1, height: 1)))
    session.openEdit(attachmentID: UUID(), strokes: [])
    #expect(session.draft.strokes.isEmpty)
}

@Test func viewModeHasNoDraftAndClearClosesTheOverlay() {
    var session = ImagePreviewSession()
    session.openView(image: ContentImage(data: Data([0x00]), mimeType: "image/png"))
    #expect(session.isOpen)
    #expect(session.showsToolbar == false)
    #expect(session.draft.strokes.isEmpty)
    session.close()
    #expect(session.isOpen == false)
}
```

- [ ] **Step 2: Generate the project, then run tests to verify they fail**

The new test file is not in the target until the project is regenerated. Run this generate before the red `xcodebuild`. A run that executes 0 tests is not a red result.

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/openEditCopiesStrokesIntoADraftAndDoneWritesThemBack()'
```

Expected: the named test runs and fails to compile, `cannot find 'ImagePreviewSession' in scope`.

- [ ] **Step 3: Write the implementation**

Create `App/Sessions/ImagePreviewSession.swift`:

```swift
import Foundation

struct ImagePreviewSession: Equatable {
    enum Mode: Equatable {
        case edit(attachmentID: UUID)
        case view
    }

    private(set) var mode: Mode?
    var draft = ImageMarkupDraft()
    private(set) var viewImage: ContentImage?

    var isOpen: Bool { mode != nil }
    var showsToolbar: Bool {
        if case .edit = mode { return true }
        return false
    }

    mutating func openEdit(attachmentID: UUID, strokes: [ImageMarkupStroke]) {
        mode = .edit(attachmentID: attachmentID)
        draft = ImageMarkupDraft(strokes: strokes)
        viewImage = nil
    }

    mutating func openView(image: ContentImage) {
        mode = .view
        draft = ImageMarkupDraft()
        viewImage = image
    }

    mutating func commit() -> (attachmentID: UUID, strokes: [ImageMarkupStroke])? {
        guard case .edit(let id) = mode else { return nil }
        let strokes = draft.strokes
        close()
        return (id, strokes)
    }

    mutating func cancel() {
        close()
    }

    mutating func close() {
        mode = nil
        draft = ImageMarkupDraft()
        viewImage = nil
    }
}
```

`openEdit` overwrites any current draft (open-another implies Cancel).

- [ ] **Step 4: Generate the project again, then run the tests**

Step 3 added a source file that is not yet in the target. Regenerate before this pass run.

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/openEditCopiesStrokesIntoADraftAndDoneWritesThemBack()' \
  -only-testing:'TenXAppTests/cancelEscBackdropOrOpenAnotherDiscardsTheDraft()' \
  -only-testing:'TenXAppTests/viewModeHasNoDraftAndClearClosesTheOverlay()'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/ImagePreviewSession.swift \
  Tests/TenXAppTests/ImagePreviewSessionTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(composer): keep image preview edit drafts off the attachment

Opening edit copies strokes. Done writes them back. Cancel, Esc,
backdrop, or opening another image throws the draft away.
EOF
)"
```

---

### Task 8: Wire send so the model and receipt see burned pixels

**Files:**
- Modify: `App/Sessions/SessionController.swift`
- Modify: `App/Application/AppModel.swift`
- Modify: `App/Sessions/ComposerView.swift`
- Modify: `App/Sessions/NewSessionView.swift`
- Modify: `App/Sessions/ActiveSessionView.swift`
- Modify: `Tests/TenXAppTests/SessionControllerTests.swift`
- Modify: `Tests/TenXAppTests/AppModelNavigationTests.swift`

**Interfaces:**
- Consumes: `ImageMarkupSend.prepare(_:)`.
- Produces: `SessionController.attachmentMessage: String?`; `AppModel.newSessionAttachmentMessage: String?`; send and start-session blocked on prepare failure; RPC restore uses the prepared (burned) attachments; red line `Could not prepare marked images for send.`

`ImageMarkupSend.prepare` is already tested in Task 6. That is not enough for this task. Do not reuse `prepareFailureKeepsTheOriginalStrokes` or any other helper-only test as Task 8 Step 1. Those tests stay green even when `send(...)` and `startNewSession` never call prepare.

These tests call `SessionController.sendPrompt` and `AppModel.startNewSession`. If either entry point skips prepare, or if `startNewSession` only rejects failure and still hands the unmarked bytes to `prepareInitialSubmission`, they stay red.

Place prepare after the existing availability guards and before any mutation: no receipt, no draft clear, no `makeSessionController`, no `Task`. On RPC failure, restore `prepared`, not the pre-composite `staged` list. `PendingUserSubmission` is created from `prepared`.

- [ ] **Step 1: Write the failing tests**

Add `import AppKit` to `Tests/TenXAppTests/SessionControllerTests.swift` if it is missing. Append the two `@Test` methods inside `SessionControllerTests`. Put `markupSendSolidImage` next to the file-level `fakeManager` helpers, not inside the suite:

```swift
@MainActor @Test func sendPromptDoesNothingWhenMarkedImagesCannotBePrepared() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let commandLogURL = directory.appending(path: "commands.log")
    let manager = commandLoggingFakeManager(commandLogURL: commandLogURL)
    let controller = SessionController(processManager: manager)
    await controller.openNew(projectURL: directory)

    let broken = ComposerAttachment(
        name: "broken.png",
        data: Data([0x00, 0x01]),
        mimeType: "image/png",
        pixelWidth: 1,
        pixelHeight: 1,
        markup: [.pen(points: [CGPoint(x: 0, y: 0)])])
    controller.draft = "keep this draft"
    controller.attachments = [broken]

    await controller.sendPrompt()

    #expect(controller.draft == "keep this draft")
    #expect(controller.attachments.count == 1)
    #expect(controller.attachments[0].id == broken.id)
    #expect(controller.attachments[0].data == broken.data)
    #expect(controller.attachments[0].markup == broken.markup)
    #expect(controller.attachmentMessage == "Could not prepare marked images for send.")
    #expect(controller.pendingSubmissions.isEmpty)
    #expect(controller.runtimeState == .idle)
    let commands = try String(contentsOf: commandLogURL, encoding: .utf8)
        .split(separator: "\n")
        .map(String.init)
    #expect(!commands.contains("prompt"))
    await manager.closeAll()
}

@MainActor @Test func sendPromptRestoresTheBurnedAttachmentWhenRPCFails() async throws {
    let manager = fakeManager(mode: "delayed-prompt-failure")
    let controller = SessionController(processManager: manager)
    await controller.openNew(projectURL: try temporaryDirectory())

    let original = try #require(ComposerAttachmentEncoder.attachment(
        from: markupSendSolidImage(width: 16, height: 12),
        name: "marked.png"))
    let marked = original.replacingMarkup([
        .rectangle(origin: CGPoint(x: 1, y: 1), size: CGSize(width: 4, height: 4))
    ])
    let prepared = try ImageMarkupSend.prepare([marked]).get()
    controller.draft = "look"
    controller.attachments = [marked]

    await controller.sendPrompt()

    #expect(controller.draft == "look")
    #expect(controller.attachments.count == 1)
    #expect(controller.attachments[0].id == original.id)
    #expect(controller.attachments[0].data == prepared[0].data)
    #expect(controller.attachments[0].data != original.data)
    #expect(controller.attachments[0].markup.isEmpty)
    #expect(controller.attachmentMessage == nil)
    #expect(controller.pendingSubmissions.count == 1)
    #expect(controller.pendingSubmissions[0].state == .unconfirmed)
    #expect(controller.pendingSubmissions[0].message.document.images.count == 1)
    #expect(controller.pendingSubmissions[0].message.document.images[0].data == prepared[0].data)
    await manager.closeAll()
}

@MainActor
private func markupSendSolidImage(width: Int, height: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor.systemTeal.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.unlockFocus()
    return image
}
```

Add `import AppKit` to `Tests/TenXAppTests/AppModelNavigationTests.swift` if it is missing. Add this as a free `@MainActor @Test` in that file (same style as `archivingANewSessionUsesTheControllerTranscriptPath`) so it can see `navigationDependencies` and so the `-only-testing` filter below matches:

```swift
@MainActor
@Test func startNewSessionDoesNothingWhenMarkedImagesCannotBePrepared() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-markup-prepare-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container)
    let project = container.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: SessionLibrary(root: container.appendingPathComponent("sessions"))))
    await model.bootstrap()
    model.chooseProject(project)

    let broken = ComposerAttachment(
        name: "broken.png",
        data: Data([0x00, 0x01]),
        mimeType: "image/png",
        pixelWidth: 1,
        pixelHeight: 1,
        markup: [.pen(points: [CGPoint(x: 0, y: 0)])])
    model.newSessionDraft = "keep this draft"
    model.newSessionAttachments = [broken]

    model.startNewSession(
        prompt: model.newSessionDraft,
        attachments: model.newSessionAttachments)

    #expect(model.route == .newSession)
    #expect(model.activeSession == nil)
    #expect(model.newSessionDraft == "keep this draft")
    #expect(model.newSessionAttachments.count == 1)
    #expect(model.newSessionAttachments[0].id == broken.id)
    #expect(model.newSessionAttachments[0].data == broken.data)
    #expect(model.newSessionAttachments[0].markup == broken.markup)
    #expect(model.newSessionAttachmentMessage == "Could not prepare marked images for send.")
    #expect(model.isSessionMutationInFlight == false)
    await model.shutdown()
}

@MainActor
@Test func startNewSessionBurnsMarkedImagesBeforeCreatingTheController() async throws {
    let container = URL(filePath: NSTemporaryDirectory())
        .appendingPathComponent("app-model-markup-burn-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: container) }
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let executable = try makeNavigationExecutable(in: container)
    let project = container.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    let model = AppModel(dependencies: navigationDependencies(
        ompLocator: FixedOmpLocator(executableURL: executable),
        sessionLibrary: SessionLibrary(root: container.appendingPathComponent("sessions"))))
    await model.bootstrap()
    model.chooseProject(project)

    let original = try #require(ComposerAttachmentEncoder.attachment(
        from: markupStartSessionSolidImage(width: 16, height: 12),
        name: "marked.png"))
    let marked = original.replacingMarkup([
        .rectangle(origin: CGPoint(x: 1, y: 1), size: CGSize(width: 4, height: 4))
    ])
    let prepared = try ImageMarkupSend.prepare([marked]).get()
    model.newSessionDraft = "look"
    model.newSessionAttachments = [marked]

    model.startNewSession(
        prompt: model.newSessionDraft,
        attachments: model.newSessionAttachments)

    let controller = try #require(model.activeSession)
    #expect(model.newSessionAttachmentMessage == nil)
    #expect(controller.pendingSubmissions.count == 1)
    #expect(controller.pendingSubmissions[0].state == .starting)
    #expect(controller.pendingSubmissions[0].message.document.images.count == 1)
    #expect(controller.pendingSubmissions[0].message.document.images[0].data == prepared[0].data)
    #expect(controller.pendingSubmissions[0].message.document.images[0].data != original.data)
    await model.shutdown()
}

@MainActor
private func markupStartSessionSolidImage(width: Int, height: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor.systemTeal.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.unlockFocus()
    return image
}
```

These four tests are red if `sendPrompt` or `startNewSession` never call `ImageMarkupSend.prepare`, or if `startNewSession` only early-returns on failure and still passes the unmarked attachment into `prepareInitialSubmission`. Do not replace them with another `prepare(_:)` unit test. A Step 2 run that executes 0 tests is not a failure and is not a pass; the four names below must appear in the test log.

- [ ] **Step 2: Run tests to verify they fail**

These four tests are edits to files already in the target. Do not run `generate_xcodeproj.rb` unless Step 1 created a new `.swift` file. If it did, regenerate first. A run that executes 0 tests is not a red result.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/SessionControllerTests/sendPromptDoesNothingWhenMarkedImagesCannotBePrepared()' \
  -only-testing:'TenXAppTests/startNewSessionDoesNothingWhenMarkedImagesCannotBePrepared()' \
  -only-testing:'TenXAppTests/startNewSessionBurnsMarkedImagesBeforeCreatingTheController()' \
  -only-testing:'TenXAppTests/SessionControllerTests/sendPromptRestoresTheBurnedAttachmentWhenRPCFails()'
```

Expected first failure: compile error, `has no member 'attachmentMessage'` / `has no member 'newSessionAttachmentMessage'`.

After the two properties exist but the entry points are still unwired, the same command stays red. Do not proceed to Step 3 while any of these is green:

- `sendPromptDoesNothingWhenMarkedImagesCannotBePrepared` sends a `prompt` and clears the draft
- `startNewSessionDoesNothingWhenMarkedImagesCannotBePrepared` creates a controller and clears `newSessionDraft` / `newSessionAttachments`
- `startNewSessionBurnsMarkedImagesBeforeCreatingTheController` creates a `.starting` receipt from the unmarked original bytes
- `sendPromptRestoresTheBurnedAttachmentWhenRPCFails` restores the unmarked original, including its strokes

- [ ] **Step 3: Call prepare at both send entries**

In `SessionController`, add `var attachmentMessage: String?` next to `attachments`. In `send(...)`, after `let staged = suppliedAttachments ?? attachments`, the `hasContent` guard, and the `handle` / `isComposerAvailable` / `isSendInFlight` guard, and before `beginManagedTurn`, the receipt, or any draft clear:

```swift
        let prepared: [ComposerAttachment]
        switch ImageMarkupSend.prepare(staged) {
        case .success(let value):
            prepared = value
            attachmentMessage = nil
        case .failure:
            attachmentMessage = "Could not prepare marked images for send."
            return false
        }
```

Use `prepared` for the receipt, `images: prepared.map(\.promptImage)`, and the restore assignment (`attachments = prepared` on RPC failure). Keep using `stagedIDs` from the pre-prepare ids (they are the same). Do not clear draft or attachments when prepare fails. `sendPrompt` already calls `markInitialSubmissionFailed()` when this returns false for a `.starting` receipt; that path does not run if `AppModel.startNewSession` refuses to create the controller.

In `AppModel`, add `var newSessionAttachmentMessage: String?` next to `newSessionAttachments`. In `startNewSession(prompt:attachments:)`, after the existing `isSessionMutationInFlight` / `processManager` / `selectedProjectURL` / `canCreateManagedSession` guards and before `makeSessionController`:

```swift
        let prepared: [ComposerAttachment]
        switch ImageMarkupSend.prepare(attachments) {
        case .success(let value):
            prepared = value
            newSessionAttachmentMessage = nil
        case .failure:
            newSessionAttachmentMessage = "Could not prepare marked images for send."
            return
        }
        let controller = makeSessionController(processManager: processManager)
        controller.prepareInitialSubmission(text: prompt, attachments: prepared, projectURL: selectedProjectURL)
```

Do not create the controller, do not clear `newSessionDraft` / `newSessionAttachments`, and do not spawn the `openNew` task when prepare fails.

In `ComposerView`, show `attachmentMessage ?? externalAttachmentMessage ?? controls?.errorMessage`. Add `externalAttachmentMessage: String? = nil`. Keep the existing paperclip skip line as the local `attachmentMessage`. `NewSessionView` passes `model.newSessionAttachmentMessage`. `ActiveSessionView` passes `controller.attachmentMessage`.

- [ ] **Step 4: Run the send-path tests**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/SessionControllerTests/sendPromptDoesNothingWhenMarkedImagesCannotBePrepared()' \
  -only-testing:'TenXAppTests/startNewSessionDoesNothingWhenMarkedImagesCannotBePrepared()' \
  -only-testing:'TenXAppTests/startNewSessionBurnsMarkedImagesBeforeCreatingTheController()' \
  -only-testing:'TenXAppTests/SessionControllerTests/sendPromptRestoresTheBurnedAttachmentWhenRPCFails()'
```

Expected: PASS. All four tests must run. Do not add Task 6 helper filters here; those can pass while both send entries are still unwired.

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/SessionController.swift \
  App/Application/AppModel.swift \
  App/Sessions/ComposerView.swift \
  App/Sessions/NewSessionView.swift \
  App/Sessions/ActiveSessionView.swift \
  Tests/TenXAppTests/SessionControllerTests.swift \
  Tests/TenXAppTests/AppModelNavigationTests.swift
git commit -m "$(cat <<'EOF'
feat(composer): burn markup before prompt images leave the client

Send and new-session start composite first. A failed prepare keeps
the draft and strokes. A failed RPC restores the burned bytes.
EOF
)"
```


### Task 9: Overlay chrome, strip click, transcript click

**Files:**
- Create: `App/Sessions/ImageMarkupOverlay.swift`
- Create: `App/Sessions/ImagePreviewOverlay.swift`
- Modify: `App/Sessions/ComposerAttachmentsView.swift`
- Modify: `App/Sessions/MessageBlockView.swift`
- Modify: `App/Sessions/MessageBubbleView.swift`
- Modify: `App/Sessions/NewSessionView.swift`
- Modify: `App/Sessions/ActiveSessionView.swift`

**Interfaces:**
- Consumes: `ImagePreviewSession`, `ImageMarkupGeometry`, `ImageMarkupDraft`, `TenXPalette`, `TenXTypography`.
- Produces: one dimmed overlay, two modes; thumbnail click opens edit; `MessageImageView` click opens view.

No sheet. No extra window. No Quick Look. No corner radius. No shadow. One overlay at a time.

- [ ] **Step 1: Write a state test for overlay copy and mode**

Add to `Tests/TenXAppTests/ImagePreviewSessionTests.swift`:

```swift
@Test func editModeShowsToolbarAndViewModeDoesNot() {
    var session = ImagePreviewSession()
    session.openEdit(attachmentID: UUID(), strokes: [])
    #expect(session.showsToolbar)
    session.openView(image: ContentImage(data: Data([0x01]), mimeType: "image/png"))
    #expect(session.showsToolbar == false)
}
```

- [ ] **Step 2: Run it (already true after Task 7; keep it as the chrome contract)**

This test is an edit to `ImagePreviewSessionTests.swift`, which is already in the target. Do not run `generate_xcodeproj.rb` unless Step 1 created a new `.swift` file.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/editModeShowsToolbarAndViewModeDoesNot()'
```

Expected: PASS.

- [ ] **Step 3: Build the views and host them**

`ImageMarkupOverlay` is a `Canvas` that maps each stroke through `ImageMarkupGeometry.viewPoint` and strokes `TenXPalette.color(TenXPalette.signalRedHex)`. `allowsHitTesting(false)`.

`ImagePreviewOverlay` layout:

- Full-size backdrop: `TenXPalette.color(TenXPalette.nearBlackHex).opacity(0.55)`. Clicking it calls `cancel` / `close`. A click that lands inside the displayed image rect is not a backdrop click.
- Image fitted with `ImageMarkupGeometry.displayedRect`. Edit mode: no zoom. View mode: scroll/pinch zoom, drag pan, double-click reset. Clamp minimum scale to 1.
- Edit toolbar, no corner radius, hairline `separatorHex`: Pen, Arrow, Rectangle, Text, Undo, Cancel, Done. Selected tool uses `signalRedHex`. Labels: `Pen`, `Arrow`, `Rectangle`, `Text`, `Undo`, `Cancel`, `Done`. Symbols: `pencil.tip`, `arrow.up.right`, `rectangle`, `textformat`, `arrow.uturn.backward`.
- Drag with pen/arrow/rectangle appends or updates the in-progress stroke in pixel space. Click with text begins an in-overlay text field; Return or click-away commits `.text`; Escape while typing cancels that text only.
- Command-Z calls `draft.undo()` when not typing.
- Escape when not typing, or Done/Cancel, match `ImagePreviewSession`.
- Session change or empty attachments: host calls `session.close()`.

Add an environment opener so clicks do not thread through every transcript wrapper:

```swift
struct ImagePreviewActions {
    var openAttachment: (ComposerAttachment) -> Void
    var openImage: (ContentImage) -> Void
}
```

`ComposerAttachmentsView`: clicking the thumbnail (not the remove button) calls `openAttachment`. Draw `ImageMarkupOverlay` over the 44-pixel image when `markup` is not empty.

`MessageImageView`: if an opener is present, tap calls `openImage`. Existing snapshots stay valid when the environment is absent.

`NewSessionView` and `ActiveSessionView`: `@State private var preview = ImagePreviewSession()`, ZStack the overlay, set the environment. Close on `controller.id` change, `newSessionFocusRequest` change, and when the edited attachment id is no longer in the staged list.

Host bindings for Done and open:

```swift
func openAttachment(_ attachment: ComposerAttachment) {
    preview.openEdit(attachmentID: attachment.id, strokes: attachment.markup)
}

func finishEdit() {
    guard let committed = preview.commit() else { return }
    attachments = attachments.map { attachment in
        attachment.id == committed.attachmentID
            ? attachment.replacingMarkup(committed.strokes)
            : attachment
    }
}
```

`attachments` is `model.newSessionAttachments` on the new-session screen and `controller.attachments` on the active session. Cancel calls `preview.cancel()` and writes nothing. `ImagePreviewOverlay` takes `session`, `base` image bytes, `pixelSize`, `selectedTool`, and the Cancel / Done / Undo / select-tool callbacks used by Task 10.


- [ ] **Step 4: Generate the project after the new overlay sources, then compile**

Step 3 created `ImageMarkupOverlay.swift` and `ImagePreviewOverlay.swift`. They are not in the target until this generate. The Step 1 test was an edit to an existing file, so Step 2 did not need a generate.

```bash
ruby scripts/generate_xcodeproj.rb
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/editModeShowsToolbarAndViewModeDoesNot()' \
  -only-testing:'TenXAppTests/composerWithStagedAttachmentsSnapshot()'
```

Expected: PASS. The existing unmarked-strip snapshot still matches.

- [ ] **Step 5: Commit**

```bash
git add App/Sessions/ImageMarkupOverlay.swift \
  App/Sessions/ImagePreviewOverlay.swift \
  App/Sessions/ComposerAttachmentsView.swift \
  App/Sessions/MessageBlockView.swift \
  App/Sessions/MessageBubbleView.swift \
  App/Sessions/NewSessionView.swift \
  App/Sessions/ActiveSessionView.swift \
  Tests/TenXAppTests/ImagePreviewSessionTests.swift \
  10x.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(composer): host image markup and preview in one overlay

Staged thumbnails open edit. Transcript images open view. Done
writes strokes; Cancel and session changes throw the draft away.
EOF
)"
```

---

### Task 10: Snapshots

**Files:**
- Modify: `Tests/TenXAppTests/ViewSnapshotTests.swift`

**Interfaces:**
- Consumes: existing `assertSnapshot`, `snapshotAttachment`, `snapshotImageData`.
- Produces: four new references from the spec, light appearance.

- [ ] **Step 1: Write the snapshot tests**

Append to `ViewSnapshotTests.swift`. Reuse `snapshotAttachment`. For the marked strip, call `replacingMarkup` with one rectangle and one arrow in the attachment's pixel space.

```swift
@MainActor
@Test func composerStripWithUnmarkedThumbnailSnapshot() throws {
    try assertSnapshot(
        ComposerAttachmentsView(
            attachments: [snapshotAttachment(name: "sidebar-overflow.png", width: 1_200, height: 800)],
            onRemove: { _ in })
            .frame(width: 620)
            .padding(24),
        name: "composer-strip-unmarked",
        size: CGSize(width: 700, height: 120))
}

@MainActor
@Test func composerStripWithMarkedThumbnailSnapshot() throws {
    let marked = snapshotAttachment(name: "sidebar-overflow.png", width: 1_200, height: 800)
        .replacingMarkup([
            .rectangle(origin: CGPoint(x: 20, y: 20), size: CGSize(width: 80, height: 40)),
            .arrow(start: CGPoint(x: 40, y: 80), end: CGPoint(x: 120, y: 30)),
        ])
    try assertSnapshot(
        ComposerAttachmentsView(
            attachments: [marked],
            onRemove: { _ in })
            .frame(width: 620)
            .padding(24),
        name: "composer-strip-marked",
        size: CGSize(width: 700, height: 120))
}

@MainActor
@Test func imageLightboxEditSnapshot() throws {
    var session = ImagePreviewSession()
    session.openEdit(attachmentID: UUID(), strokes: [
        .rectangle(origin: CGPoint(x: 20, y: 20), size: CGSize(width: 80, height: 40))
    ])
    try assertSnapshot(
        ImagePreviewOverlay(
            session: session,
            base: snapshotImageData(width: 320, height: 200),
            pixelSize: CGSize(width: 320, height: 200),
            selectedTool: .rectangle,
            onCancel: {},
            onDone: {},
            onUndo: {},
            onSelectTool: { _ in })
            .frame(width: 720, height: 480),
        name: "lightbox-edit",
        size: CGSize(width: 720, height: 480))
}

@MainActor
@Test func imageLightboxViewSnapshot() throws {
    var session = ImagePreviewSession()
    session.openView(image: ContentImage(
        data: snapshotImageData(width: 320, height: 200),
        mimeType: "image/png"))
    try assertSnapshot(
        ImagePreviewOverlay(
            session: session,
            base: snapshotImageData(width: 320, height: 200),
            pixelSize: CGSize(width: 320, height: 200),
            selectedTool: .pen,
            onCancel: {},
            onDone: {},
            onUndo: {},
            onSelectTool: { _ in })
            .frame(width: 720, height: 480),
        name: "lightbox-view",
        size: CGSize(width: 720, height: 480))
}
```

`ImagePreviewOverlay` must accept these stored arguments (or an equivalent initializer) so snapshots do not need a live session object with bindings. If the production view uses bindings, add a preview-friendly initializer that copies `session` and ignores the unused edit callbacks in view mode.

No per-frame pen-move snapshots.

- [ ] **Step 2: Run tests to verify they fail on missing references**

These snapshot tests are edits to `ViewSnapshotTests.swift`, which is already in the target. Do not run `generate_xcodeproj.rb` unless Step 1 created a new `.swift` file. If it did, regenerate first. A run that executes 0 tests is not a red result.

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/composerStripWithUnmarkedThumbnailSnapshot()'
```

Expected: FAIL, missing `composer-strip-unmarked` reference.

- [ ] **Step 3: Record the four references**

```bash
TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild test -project 10x.xcodeproj -scheme 10x \
  -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/composerStripWithUnmarkedThumbnailSnapshot()' \
  -only-testing:'TenXAppTests/composerStripWithMarkedThumbnailSnapshot()' \
  -only-testing:'TenXAppTests/imageLightboxEditSnapshot()' \
  -only-testing:'TenXAppTests/imageLightboxViewSnapshot()'
```

Inspect the PNGs. Edit chrome must show the toolbar. View chrome must not. Marked strip must show red vector marks. Unmarked strip must not.

- [ ] **Step 4: Re-run without recording**

```bash
xcodebuild test -project 10x.xcodeproj -scheme 10x -destination 'platform=macOS' \
  -only-testing:'TenXAppTests/composerStripWithUnmarkedThumbnailSnapshot()' \
  -only-testing:'TenXAppTests/composerStripWithMarkedThumbnailSnapshot()' \
  -only-testing:'TenXAppTests/imageLightboxEditSnapshot()' \
  -only-testing:'TenXAppTests/imageLightboxViewSnapshot()'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/TenXAppTests/ViewSnapshotTests.swift \
  Tests/TenXAppTests/Snapshots
git commit -m "$(cat <<'EOF'
test(composer): snapshot unmarked strip, marked strip, and both lightboxes

Edit chrome keeps the toolbar. View chrome does not. Marks stay
vectors on the strip until send.
EOF
)"
```

---

## Spec coverage

| Spec requirement | Task |
| --- | --- |
| Classify pasteboard: files, then images, else none | Task 1 |
| Built-app paste spike before locking a path | Task 2 |
| Key-router path if spike passes | Task 3A |
| Owned `NSTextView` if spike fails | Task 3B |
| Never hook or mutate `SwiftUI.PlatformTextView` | Global Constraints, Tasks 2-3 |
| No window-local key monitor | Global Constraints, Task 1 |
| Paste / drop / paperclip only stage | Tasks 2, 9 |
| Pen, arrow, rectangle, text, undo | Tasks 4, 9 |
| One markup color `signalRedHex` | Tasks 5, 9 |
| Points in fitted pixel space; resize does not drift | Task 4 |
| Backdrop click does not start a stroke | Tasks 4, 9 |
| Live views draw vector overlay; send is the only composite | Tasks 5, 6, 8, 9 |
| Stroke-less send is byte-identical | Task 6 |
| Marked send's `PromptImage` differs | Task 6 |
| `PendingUserSubmission` uses burned bytes | Tasks 6, 8 |
| Composite failure blocks send and keeps strokes | Task 8 (`sendPrompt` integration) |
| Composite failure blocks new-session start | Task 8 (`startNewSession` integration) |
| New-session start burns markup before `prepareInitialSubmission` | Task 8 (`startNewSession` burned receipt) |
| RPC failure restores burned attachment | Task 8 (`sendPrompt` + `delayed-prompt-failure`) |
| In-app lightbox, no extra window, no Quick Look | Task 9 |
| Edit from staged thumbnail; view from `MessageImageView` | Task 9 |
| Done writes draft; Cancel / Esc / backdrop / open-another discard | Tasks 7, 9 |
| Session change or composer clear closes overlay | Task 9 |
| View mode zoom / pan / double-click reset, no toolbar | Task 9 |
| Four snapshots | Task 10 |
| 8-image cap, 1,568 fit, PNG/JPEG budget unchanged | Tasks 1, 6 |
| `generate_xcodeproj.rb` after every new `.swift` file, including before the red run | every new-file task |

## Out of scope (do not implement)

- `Edit → Paste` while `TextEditor` is focused, unless Task 3B is locked
- Color picker, blur, crop, highlighter, or shapes beyond pen / arrow / rectangle / text
- Re-editing a sent image
- Keeping the unmarked original after send
- Quick Look or a separate preview window
- Auto-opening the editor on paste, drop, or paperclip
- Replacing `TextEditor` unless the paste spike fails
- Changing the 8-image cap, the 1,568-pixel fit, or the PNG/JPEG budget
- Non-image clipboard content (files still become draft paths)
- Window-local key monitors or any runtime mutation of SwiftUI's text view
- Merging uncommitted paste-monitor files from the `/10x` checkout

## Type names this plan locks

Later tasks must use these names. Do not invent a second vocabulary.

- `ComposerPasteboard.Content` = `.imageFiles([URL])` / `.images([NSImage])` / `.none`
- `ComposerPasteKeyRouting.Decision` = `.stage` / `.ignore` (Task 3A only)
- `ImageMarkupTool` = `.pen` / `.arrow` / `.rectangle` / `.text`
- `ImageMarkupStroke` = `.pen(points:)` / `.arrow(start:end:)` / `.rectangle(origin:size:)` / `.text(origin:value:)`
- `ImageMarkupDraft.append` / `ImageMarkupDraft.undo`
- `ImageMarkupGeometry.displayedRect(imageSize:in:)` / `pixel(from:imageSize:displayedRect:)` / `viewPoint(from:imageSize:displayedRect:)`
- `ImageMarkupRenderer.render(base:strokes:)`
- `ImageMarkupSend.prepare(_:)` -> `Result<[ComposerAttachment], ImageMarkupSend.Failure>`
- `ImageMarkupSend.Failure` = `.compositeFailed` / `.encodeFailed`
- `ComposerAttachment.markup` / `replacingMarkup(_:)`
- `ImagePreviewSession.openEdit(attachmentID:strokes:)` / `openView(image:)` / `commit()` / `cancel()` / `close()`
- User-visible prepare error: `Could not prepare marked images for send.`
- Pasted bitmap name: `Pasted image`
