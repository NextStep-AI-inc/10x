import Foundation
import Testing

@Test func sharedSchemeSerializesTheAppTestBundle() throws {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let schemeURL = repositoryRoot
        .appending(path: "10x.xcodeproj/xcshareddata/xcschemes/10x.xcscheme")
    let scheme = try String(contentsOf: schemeURL, encoding: .utf8)

    #expect(scheme.contains("parallelizable = \"NO\""))
}
