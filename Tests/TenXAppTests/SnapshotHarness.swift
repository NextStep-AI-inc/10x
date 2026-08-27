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
    let host = makeSnapshotHost(content, size: size)
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    try captureAndCompare(host: host, name: name, size: size, sourceFile: sourceFile)
}

@MainActor
private func makeSnapshotHost<Content: View>(
    _ content: Content,
    size: CGSize
) -> NSHostingView<some View> {
    let root = content
        .frame(width: size.width, height: size.height)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    let host = NSHostingView(rootView: root)
    host.appearance = NSAppearance(named: .aqua)
    host.frame = CGRect(origin: .zero, size: size)
    return host
}

@MainActor
private func captureAndCompare(
    host: NSView,
    name: String,
    size: CGSize,
    sourceFile: String
) throws {
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        Issue.record("Unable to allocate snapshot bitmap")
        return
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let actual = bitmap.representation(using: .png, properties: [:]) else {
        Issue.record("Unable to encode snapshot PNG")
        return
    }

    // Written into the source tree, not the built bundle, so a recorded or
    // rejected snapshot lands next to the reference it replaces.
    let referenceDirectory = URL(fileURLWithPath: sourceFile)
        .deletingLastPathComponent()
        .appendingPathComponent("ReferenceImages")
    let recordingURL = referenceDirectory.appendingPathComponent("\(name).png")
    let actualURL = referenceDirectory.appendingPathComponent("\(name).actual.png")
    try FileManager.default.createDirectory(
        at: referenceDirectory, withIntermediateDirectories: true)

    if ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1" {
        try actual.write(to: recordingURL)
        try? FileManager.default.removeItem(at: actualURL)
        return
    }

    let reference = Bundle(for: SnapshotToken.self)
        .url(forResource: name, withExtension: "png", subdirectory: "ReferenceImages")
        .flatMap { try? Data(contentsOf: $0) }
    guard let reference, actual.elementsEqual(reference) else {
        try actual.write(to: actualURL)
        Issue.record("""
            Snapshot \(name) \(reference == nil ? "has no reference image" : "differs from its reference").
            Wrote \(actualURL.path)
            Inspect it, then promote with: mv '\(actualURL.path)' '\(recordingURL.path)'
            """)
        return
    }
    try? FileManager.default.removeItem(at: actualURL)
}
