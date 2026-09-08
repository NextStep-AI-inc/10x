import Foundation
import Testing
@testable import TenXApp

private let cursor = IDEApplication(
    displayName: "Cursor",
    url: URL(filePath: "/Applications/Cursor.app"),
    source: .known(bundleIdentifier: "com.todesktop.230313mzl4w4u92"))

private func reference(exists: Bool = true) -> ResolvedFileReference {
    ResolvedFileReference(
        originalPath: "App/Feature.swift",
        line: 7,
        url: URL(filePath: "/tmp/App/Feature.swift"),
        exists: exists)
}

@Test func normalFileActivationOpensThePreferredIDE() {
    #expect(FileReferenceActivation.resolve(
        preference: .available(cursor),
        reference: reference(),
        isOptionPressed: false
    ) == .openInIDE(cursor))
}

@Test func optionFileActivationRevealsTheFileInFinder() {
    #expect(FileReferenceActivation.resolve(
        preference: .available(cursor),
        reference: reference(),
        isOptionPressed: true
    ) == .revealInFinder)
}

@Test func fileActivationWithoutAnIDEOpensPreferredIDESettings() {
    #expect(FileReferenceActivation.resolve(
        preference: .none,
        reference: reference(),
        isOptionPressed: false
    ) == .openPreferences)
    #expect(FileReferenceActivation.resolve(
        preference: .unavailable(displayName: "Old IDE"),
        reference: reference(),
        isOptionPressed: false
    ) == .openPreferences)
}

@Test func missingFileActivationRemainsUnavailable() {
    #expect(FileReferenceActivation.resolve(
        preference: .available(cursor),
        reference: reference(exists: false),
        isOptionPressed: false
    ) == .unavailable)
    #expect(FileReferenceActivation.resolve(
        preference: .available(cursor),
        reference: reference(exists: false),
        isOptionPressed: true
    ) == .unavailable)
}
