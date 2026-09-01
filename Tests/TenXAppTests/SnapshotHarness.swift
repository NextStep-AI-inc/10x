import AppKit
import SwiftUI
import Testing
@testable import TenXApp

final class SnapshotToken: NSObject {}

/// Which appearance a snapshot is rendered in. Pinned explicitly rather than
/// inherited, so a reference recorded on a machine set to dark mode matches one
/// recorded on a machine set to light.
enum SnapshotAppearance {
    case light
    case dark

    var appearanceName: NSAppearance.Name {
        switch self {
        case .light: .aqua
        case .dark: .darkAqua
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }

    /// The ground the hosting view paints behind the content. Light keeps the
    /// literal white the existing references were recorded against; dark uses
    /// the canvas token so the backdrop matches what the app actually draws.
    var backdrop: Color {
        switch self {
        case .light: Color.white
        case .dark: TenXPalette.color(TenXPalette.canvasHex)
        }
    }
}

@MainActor
func assertSnapshot<Content: View>(
    _ content: Content,
    name: String,
    appearance: SnapshotAppearance = .light,
    size: CGSize = CGSize(width: 900, height: 600),
    sourceFile: String = #filePath
) throws {
    // Rendering in parallel with the rest of the suite, a detached hosting view
    // occasionally resolves a text field a few points short — its placeholder
    // clipped by its own bounds, every row below it shifted up. A second host
    // usually draws it correctly; when the miss is sticky, an identical view of
    // a different static type always does. Everything past the first attempt
    // runs only on a mismatch, and a real regression differs on all of them.
    let sameColorScheme = content.environment(\.colorScheme, appearance.colorScheme)
    let attempts: [() -> Data?] = [
        { renderSnapshot(content, size: size, appearance: appearance) },
        { renderSnapshot(content, size: size, appearance: appearance) },
        { renderSnapshot(sameColorScheme, size: size, appearance: appearance) },
        {
            renderSnapshot(
                sameColorScheme.environment(\.colorScheme, appearance.colorScheme),
                size: size,
                appearance: appearance)
        },
    ]
    try captureAndCompare(attempts: attempts, name: name, sourceFile: sourceFile)
}

@MainActor
private func renderSnapshot<Content: View>(
    _ content: Content,
    size: CGSize,
    appearance: SnapshotAppearance
) -> Data? {
    renderSnapshotBitmap(content, size: size, appearance: appearance)?
        .representation(using: .png, properties: [:])
}

@MainActor
func renderSnapshotBitmap<Content: View>(
    _ content: Content,
    size: CGSize,
    appearance: SnapshotAppearance = .light
) -> NSBitmapImageRep? {
    let host = makeSnapshotHost(content, size: size, appearance: appearance)
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        return nil
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    return bitmap
}

@MainActor
private func makeSnapshotHost<Content: View>(
    _ content: Content,
    size: CGSize,
    appearance: SnapshotAppearance
) -> NSHostingView<some View> {
    let root = content
        .frame(width: size.width, height: size.height)
        .background(appearance.backdrop)
        .environment(\.colorScheme, appearance.colorScheme)
    let host = NSHostingView(rootView: root)
    // Set before the backdrop resolves: the palette's dynamic colors read the
    // host's appearance, not the process's.
    host.appearance = NSAppearance(named: appearance.appearanceName)
    host.frame = CGRect(origin: .zero, size: size)
    return host
}

@MainActor
private func captureAndCompare(
    attempts: [() -> Data?],
    name: String,
    sourceFile: String
) throws {
    guard var actual = attempts.first?() ?? nil else {
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
    if let reference {
        for attempt in attempts.dropFirst() {
            if actual.elementsEqual(reference) { break }
            guard let rendered = attempt() else { break }
            actual = rendered
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
