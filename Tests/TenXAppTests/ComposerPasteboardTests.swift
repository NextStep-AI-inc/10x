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
