import AppKit
import Foundation
import OmpKit
import UniformTypeIdentifiers

/// An image staged in the composer, already downscaled and encoded for the wire.
///
/// Encoding happens when the image is added rather than when the prompt is
/// sent, so the cost lands while the user is still typing and the strip can
/// show the real size it will send.
struct ComposerAttachment: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let data: Data
    let mimeType: String
    let pixelWidth: Int
    let pixelHeight: Int

    init(
        id: UUID = UUID(),
        name: String,
        data: Data,
        mimeType: String,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.id = id
        self.name = name
        self.data = data
        self.mimeType = mimeType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    var promptImage: PromptImage {
        PromptImage(base64Data: data.base64EncodedString(), mimeType: mimeType)
    }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}

enum ComposerAttachmentEncoder {
    /// The longest side every image is fitted into. Above this the extra pixels
    /// buy no accuracy from any vision model and only cost transfer.
    static let maxPixelDimension = 1_568
    /// PNG is kept while it stays this small, so screenshots of text keep their
    /// crisp glyph edges. Photographs blow past it and fall back to JPEG.
    static let pngBudgetBytes = 1_000_000
    static let maximumCount = 8

    /// Nil when the file is not an image this machine can decode. Callers treat
    /// that as "reference it by path instead", not as an error.
    static func attachment(fromFileAt url: URL) -> ComposerAttachment? {
        guard isImage(url), let image = NSImage(contentsOf: url) else { return nil }
        return attachment(from: image, name: url.lastPathComponent)
    }

    static func attachment(from image: NSImage, name: String) -> ComposerAttachment? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let fitted = fitted(source)
        else { return nil }

        let representation = NSBitmapImageRep(cgImage: fitted)
        representation.size = NSSize(width: fitted.width, height: fitted.height)

        if let png = representation.representation(using: .png, properties: [:]),
           png.count <= pngBudgetBytes {
            return ComposerAttachment(
                name: name,
                data: png,
                mimeType: "image/png",
                pixelWidth: fitted.width,
                pixelHeight: fitted.height)
        }
        guard let jpeg = representation.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.8])
        else { return nil }
        return ComposerAttachment(
            name: name,
            data: jpeg,
            mimeType: "image/jpeg",
            pixelWidth: fitted.width,
            pixelHeight: fitted.height)
    }

    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .image)
    }

    /// Longest side clamped, aspect ratio kept, never enlarged.
    nonisolated static func fittedSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard longest > maxPixelDimension, longest > 0 else { return (width, height) }
        let scale = Double(maxPixelDimension) / Double(longest)
        return (
            max(1, Int((Double(width) * scale).rounded())),
            max(1, Int((Double(height) * scale).rounded())))
    }

    private static func fitted(_ image: CGImage) -> CGImage? {
        let size = fittedSize(width: image.width, height: image.height)
        guard size.width != image.width || size.height != image.height else { return image }
        guard let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage() ?? image
    }
}
