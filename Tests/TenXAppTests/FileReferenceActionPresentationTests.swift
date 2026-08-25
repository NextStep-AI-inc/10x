import Foundation
import Testing
@testable import TenXApp

@Test func missingFileKeepsThePreferredIDEActionLabelAndExposesUnavailableState() {
    let cursor = IDEApplication(
        displayName: "Cursor",
        url: URL(filePath: "/Applications/Cursor.app"),
        source: .known(bundleIdentifier: "com.todesktop.230313mzl4w4u92"))
    let reference = ResolvedFileReference(
        originalPath: "Missing/NeverExists.swift",
        line: 7,
        url: URL(filePath: "/tmp/Missing/NeverExists.swift"),
        exists: false)

    let presentation = FileReferenceIDEActionPresentation.make(
        preference: .available(cursor),
        reference: reference)

    #expect(presentation.title == "Open in Cursor")
    #expect(!presentation.isEnabled)
    #expect(presentation.showsUnavailableSymbol)
    #expect(presentation.accessibilityLabel ==
        "Open NeverExists.swift:7 in Cursor, Unavailable, /tmp/Missing/NeverExists.swift:7")
}
