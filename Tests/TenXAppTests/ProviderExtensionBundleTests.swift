import Foundation
import Testing
@testable import TenXApp

@Test func bundledExtensionIsPresentAndLoadable() throws {
    let url = try #require(ProviderExtensionBundle.indexURL)
    #expect(url.lastPathComponent == "index.ts")
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Test func spawnArgumentsLoadTheBundledExtension() throws {
    let url = try #require(ProviderExtensionBundle.indexURL)
    let arguments = ProviderExtensionBundle.spawnArguments()
    #expect(arguments == ["-e", url.path])
}

@Test func spawnArgumentsAreEmptyWhenTheExtensionIsMissing() {
    #expect(ProviderExtensionBundle.spawnArguments(indexURL: nil).isEmpty)
}
