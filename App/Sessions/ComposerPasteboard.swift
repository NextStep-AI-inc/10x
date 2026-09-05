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
