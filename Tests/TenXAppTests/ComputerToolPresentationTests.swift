import AppKit
import Foundation
import OmpKit
import Testing
@testable import TenXApp

@MainActor
@Test func computerPresentationPreservesImagesAndCapabilities() throws {
    let parsed = try #require(ComputerToolPresentation(computerPresentation(
        name: "COMPUTER",
        arguments: .object([
            "code": .string("await desktop.windows()[0].screenshot()"),
            "read_only": .bool(true),
        ]),
        result: computerResult(images: [testImageBase64(.png)]))))

    #expect(parsed.images.count == 1)
    #expect(parsed.images.first?.mimeType == "image/png")
    #expect(parsed.isReadOnly)
    #expect(parsed.output == "Captured TextEdit")
    #expect(parsed.target == "TextEdit")
    #expect(parsed.capabilities.capture == .granted)
    #expect(parsed.capabilities.input == .granted)
    #expect(parsed.capabilities.accessibility == .granted)
}

@MainActor
@Test func computerPresentationAcceptsValidatedJPEGImages() throws {
    let parsed = try #require(ComputerToolPresentation(computerPresentation(
        result: computerResult(images: [testImageBase64(.jpeg)], mimeType: "image/jpeg"))))

    #expect(parsed.images.count == 1)
    #expect(parsed.images.first?.mimeType == "image/jpeg")
}

@Test func computerPresentationRequiresTheExactNormalizedToolName() {
    #expect(ComputerToolPresentation(computerPresentation(name: "computer")) != nil)
    #expect(ComputerToolPresentation(computerPresentation(name: "Computer")) != nil)
    #expect(ComputerToolPresentation(computerPresentation(name: " computer")) == nil)
    #expect(ComputerToolPresentation(computerPresentation(name: "computer_use")) == nil)
}

@MainActor
@Test func malformedAndUnsupportedImagesAreSkippedWithoutDroppingText() throws {
    let validPNG = testImageBase64(.png)
    let result = JSONValue.object([
        "content": .array([
            .object(["type": .string("text"), "text": .string("Capture still available")]),
            .object([
                "type": .string("image"),
                "data": .string("not-base64"),
                "mimeType": .string("image/png"),
            ]),
            .object([
                "type": .string("image"),
                "data": .string(validPNG),
                "mimeType": .string("image/gif"),
            ]),
            .object([
                "type": .string("image"),
                "data": .string(validPNG),
                "mimeType": .string("image/jpeg"),
            ]),
        ]),
    ])

    let parsed = try #require(ComputerToolPresentation(computerPresentation(result: result)))
    #expect(parsed.images.isEmpty)
    #expect(parsed.output == "Capture still available")
}

@Test func imagePayloadsOverTwentyMiBAreRejectedBeforeDecoding() throws {
    let encodedByteCount = 20 * 1_024 * 1_024 + 1
    let encodedLength = ((encodedByteCount + 2) / 3) * 4
    let oversized = "A" + String(repeating: "A", count: encodedLength - 1)
    let result = JSONValue.object([
        "content": .array([
            .object([
                "type": .string("image"),
                "data": .string(oversized),
                "mimeType": .string("image/png"),
            ]),
        ]),
    ])

    let parsed = try #require(ComputerToolPresentation(computerPresentation(result: result)))
    #expect(parsed.images.isEmpty)
}

private enum TestImageFormat {
    case png
    case jpeg
}

@MainActor
private func testImageBase64(_ format: TestImageFormat) -> String {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 8,
        pixelsHigh: 5,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0)!
    for x in 0..<8 {
        for y in 0..<5 {
            bitmap.setColor(
                x < 4
                    ? NSColor(deviceRed: 0, green: 0.65, blue: 0.76, alpha: 1)
                    : NSColor(deviceRed: 0.96, green: 0.48, blue: 0.12, alpha: 1),
                atX: x,
                y: y)
        }
    }
    let fileType: NSBitmapImageRep.FileType = format == .png ? .png : .jpeg
    return bitmap.representation(using: fileType, properties: [:])!.base64EncodedString()
}

private func computerPresentation(
    name: String = "computer",
    arguments: JSONValue = .object([:]),
    result: JSONValue? = nil
) -> ToolPresentation {
    ToolPresentation(
        id: "computer-test",
        name: name,
        arguments: arguments,
        result: result,
        phase: .complete,
        startDate: .distantPast,
        endDate: .distantPast)
}

private func computerResult(
    images: [String],
    mimeType: String = "image/png"
) -> JSONValue {
    .object([
        "content": .array([
            .object(["type": .string("text"), "text": .string("Captured TextEdit")]),
        ] + images.map { image in
            .object([
                "type": .string("image"),
                "data": .string(image),
                "mimeType": .string(mimeType),
            ])
        }),
        "details": .object([
            "backend": .string("macos"),
            "capturePermission": .string("granted"),
            "inputPermission": .string("granted"),
            "axPermission": .string("granted"),
            "screenshots": .array([
                .object(["target": .string("TextEdit")]),
            ]),
        ]),
    ])
}
