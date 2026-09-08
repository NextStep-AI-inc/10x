import Foundation
import Sparkle
import Testing

@Test func sparkleIsEmbeddedAndLoadableAtRuntime() throws {
    let bundle = try #require(Bundle(for: SPUUpdater.self))

    #expect(bundle.bundleURL.lastPathComponent == "Sparkle.framework")
}
