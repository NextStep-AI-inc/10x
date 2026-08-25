import AppKit
import SwiftUI
import Testing

final class SnapshotToken: NSObject {}

@MainActor
func assertSnapshot<Content: View>(
    _ content: Content,
    name: String,
    size: CGSize = CGSize(width: 900, height: 600),
    sourceFile: String = #filePath
) throws {
    let root = content
        .frame(width: size.width, height: size.height)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    let host = NSHostingView(rootView: root)
    host.appearance = NSAppearance(named: .aqua)
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        Issue.record("Unable to allocate snapshot bitmap")
        return
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let actual = bitmap.representation(using: .png, properties: [:]) else {
        Issue.record("Unable to encode snapshot PNG")
        return
    }

    let sourceDirectory = URL(fileURLWithPath: sourceFile).deletingLastPathComponent()
    let recordingURL = sourceDirectory
        .appendingPathComponent("ReferenceImages")
        .appendingPathComponent("\(name).png")
    if ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1" {
        try FileManager.default.createDirectory(
            at: recordingURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try actual.write(to: recordingURL)
        return
    }

    guard let referenceURL = Bundle(for: SnapshotToken.self)
        .url(forResource: name, withExtension: "png", subdirectory: "ReferenceImages")
    else {
        Issue.record("Missing reference image: \(name).png")
        return
    }
    let reference = try Data(contentsOf: referenceURL)
    #expect(actual.elementsEqual(reference))
}
