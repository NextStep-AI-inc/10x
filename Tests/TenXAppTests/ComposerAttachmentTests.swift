import AppKit
import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func attachmentsAreFittedIntoTheLongestSideCap() {
    let cap = ComposerAttachmentEncoder.maxPixelDimension

    #expect(ComposerAttachmentEncoder.fittedSize(width: 800, height: 600).width == 800)
    #expect(ComposerAttachmentEncoder.fittedSize(width: 800, height: 600).height == 600)

    let wide = ComposerAttachmentEncoder.fittedSize(width: cap * 2, height: cap)
    #expect(wide.width == cap)
    #expect(wide.height == cap / 2)

    let tall = ComposerAttachmentEncoder.fittedSize(width: 100, height: cap * 4)
    #expect(tall.height == cap)
    #expect(tall.width == 25)
}

@Test func aVeryThinImageKeepsAtLeastOnePixel() {
    let fitted = ComposerAttachmentEncoder.fittedSize(
        width: 1,
        height: ComposerAttachmentEncoder.maxPixelDimension * 8)
    #expect(fitted.width == 1)
    #expect(fitted.height == ComposerAttachmentEncoder.maxPixelDimension)
}

@MainActor @Test func anOversizedScreenshotIsDownscaledAndStaysPNG() throws {
    let attachment = try #require(ComposerAttachmentEncoder.attachment(
        from: solidImage(width: 3_000, height: 1_500),
        name: "screenshot.png"))

    #expect(attachment.pixelWidth == ComposerAttachmentEncoder.maxPixelDimension)
    #expect(attachment.pixelHeight == ComposerAttachmentEncoder.maxPixelDimension / 2)
    #expect(attachment.mimeType == "image/png")
    #expect(attachment.data.count <= ComposerAttachmentEncoder.pngBudgetBytes)
    #expect(NSImage(data: attachment.data) != nil)
}

@MainActor @Test func anAttachmentEncodesIntoThePromptContractShape() throws {
    let attachment = try #require(ComposerAttachmentEncoder.attachment(
        from: solidImage(width: 40, height: 40),
        name: "dot.png"))
    let image = attachment.promptImage

    #expect(image.mimeType == "image/png")
    #expect(Data(base64Encoded: image.base64Data) == attachment.data)
}

@Test func onlyImageFilesAreTreatedAsAttachable() {
    #expect(ComposerAttachmentEncoder.isImage(URL(filePath: "/tmp/a.png")))
    #expect(ComposerAttachmentEncoder.isImage(URL(filePath: "/tmp/a.JPEG")))
    #expect(!ComposerAttachmentEncoder.isImage(URL(filePath: "/tmp/a.swift")))
    #expect(!ComposerAttachmentEncoder.isImage(URL(filePath: "/tmp/no-extension")))
}

@Test func anImageContentBlockBecomesAnImageAndStaysOutOfTheMessageText() throws {
    let png = try #require(solidPNG(width: 8, height: 8))
    let message = TranscriptMessage(
        id: "with-image",
        raw: .object([
            "role": .string("user"),
            "content": .array([
                .object(["type": .string("text"), "text": .string("What is wrong here?")]),
                .object([
                    "type": .string("image"),
                    "data": .string(png.base64EncodedString()),
                    "mimeType": .string("image/png"),
                ]),
            ]),
        ]),
        isFinal: true)

    #expect(message.document.images.count == 1)
    #expect(message.document.images[0].mimeType == "image/png")
    #expect(message.document.images[0].data == png)
    #expect(message.visibleText == "What is wrong here?")
}

@Test func anImageOnlyMessageKeepsItsImage() throws {
    let png = try #require(solidPNG(width: 8, height: 8))
    let message = TranscriptMessage(
        id: "image-only",
        raw: .object([
            "role": .string("user"),
            "content": .array([
                .object([
                    "type": .string("image"),
                    "data": .string(png.base64EncodedString()),
                    "mimeType": .string("image/png"),
                ]),
            ]),
        ]),
        isFinal: true)

    #expect(message.document.images.count == 1)
    #expect(message.visibleText.isEmpty)
}

@Test func anImageBlockWithUnreadableDataFallsBackToALabel() {
    let message = TranscriptMessage(
        id: "broken-image",
        raw: .object([
            "role": .string("user"),
            "content": .array([
                .object(["type": .string("image"), "data": .string("")]),
            ]),
        ]),
        isFinal: true)

    #expect(message.document.images.isEmpty)
    #expect(message.visibleText == "Image attachment")
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

private func solidPNG(width: Int, height: Int) -> Data? {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0)
    else { return nil }
    return representation.representation(using: .png, properties: [:])
}

@Test func aTranscriptImageIsBoxedExactlyAndNeverEnlarged() {
    let capped = MessageImageView.displaySize(for: CGSize(width: 1_600, height: 400))
    #expect(capped.width == MessageImageView.maxWidth)
    #expect(capped.height == (MessageImageView.maxWidth / 4).rounded())

    let tall = MessageImageView.displaySize(for: CGSize(width: 400, height: 1_600))
    #expect(tall.height == MessageImageView.maxHeight)

    let small = MessageImageView.displaySize(for: CGSize(width: 120, height: 90))
    #expect(small == CGSize(width: 120, height: 90))

    let degenerate = MessageImageView.displaySize(for: .zero)
    #expect(degenerate.width == MessageImageView.maxWidth)
}
