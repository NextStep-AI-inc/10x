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
    func render(_ view: some View) -> Data? {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .aqua)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            return nil
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }
    guard var actual = render(root) else {
        Issue.record("Unable to render snapshot \(name)")
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

    // Rendering in parallel with the rest of the suite, a detached hosting view
    // occasionally resolves a text field a few points short — its placeholder
    // clipped, every row below it shifted up. A second host usually renders it
    // correctly; when the miss is sticky, an identical view of a different
    // static type always does. A real regression differs on every attempt, so
    // this only absorbs the flake.
    if let reference, !actual.elementsEqual(reference) {
        let sameColorScheme = root.environment(\.colorScheme, .light)
        let retries: [() -> Data?] = [
            { render(root) },
            { render(sameColorScheme) },
            { render(sameColorScheme.environment(\.colorScheme, .light)) },
        ]
        for retry in retries {
            guard let rendered = retry() else { break }
            actual = rendered
            if actual.elementsEqual(reference) { break }
        }
    }
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
