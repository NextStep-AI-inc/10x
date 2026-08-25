import Foundation
import Testing
@testable import TenXApp

@Test func resolvesRelativeReferenceAgainstSessionBase() {
    let resolver = FileReferenceResolver(fileExists: { $0 == "/tmp/10x/App/Foo.swift" })
    let result = resolver.resolve(
        path: "App/Folder/../Foo.swift",
        line: 42,
        relativeTo: URL(filePath: "/tmp/10x", directoryHint: .isDirectory))

    #expect(result.url?.path == "/tmp/10x/App/Foo.swift")
    #expect(result.exists)
    #expect(result.compactLabel == "Foo.swift:42")
    #expect(result.fullPathLabel == "/tmp/10x/App/Foo.swift:42")
    #expect(result.originalReference == "App/Folder/../Foo.swift:42")
}

@Test func leavesRelativeReferenceUnavailableWithoutSessionBase() {
    let result = FileReferenceResolver(fileExists: { _ in true })
        .resolve(path: "App/Foo.swift", line: nil, relativeTo: nil)

    #expect(result.url == nil)
    #expect(!result.exists)
    #expect(result.fullPathLabel == "App/Foo.swift")
}

@Test func resolvesAbsolutePathIgnoringSuppliedBase() {
    let resolver = FileReferenceResolver(fileExists: { $0 == "/tmp/file.swift" })
    let result = resolver.resolve(
        path: "/tmp/Folder/../file.swift",
        line: nil,
        relativeTo: URL(filePath: "/tmp/10x", directoryHint: .isDirectory))

    #expect(result.url?.path == "/tmp/file.swift")
    #expect(result.exists)
}

@Test func reportsMissingAbsoluteFile() {
    let result = FileReferenceResolver(fileExists: { _ in false })
        .resolve(path: "/tmp/missing.swift", line: 9, relativeTo: nil)

    #expect(result.url?.path == "/tmp/missing.swift")
    #expect(!result.exists)
    #expect(result.fullPathLabel == "/tmp/missing.swift:9")
}

@Test func preservesRootFileNameAndOriginalLineSuffix() {
    let result = FileReferenceResolver(fileExists: { _ in true })
        .resolve(path: "Package.swift", line: 007, relativeTo: nil)

    #expect(result.compactLabel == "Package.swift:7")
    #expect(result.originalReference == "Package.swift:7")
}
