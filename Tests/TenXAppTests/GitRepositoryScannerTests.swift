import Foundation
import Testing
@testable import TenXApp

private struct ScannerFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "tenx-scan-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Creates `path` under the fixture root and marks it a repository by
    /// giving it a `.git` directory.
    @discardableResult
    func repository(_ path: String, modified: Date = Date(timeIntervalSince1970: 1)) throws -> URL {
        let url = root.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: url.appending(path: ".git", directoryHint: .isDirectory),
            withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.modificationDate: modified],
            ofItemAtPath: url.path)
        return url
    }

    /// A worktree: `.git` is a file, not a directory.
    @discardableResult
    func worktree(_ path: String) throws -> URL {
        let url = root.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try "gitdir: /elsewhere/.git/worktrees/x\n".write(
            to: url.appending(path: ".git"),
            atomically: true,
            encoding: .utf8)
        return url
    }

    func directory(_ path: String) throws -> URL {
        let url = root.appending(path: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@Test func scannerFindsRepositoriesAndAppliesEveryExclusionRule() async throws {
    let fixture = try ScannerFixture()
    defer { fixture.cleanup() }

    let shallow = try fixture.repository("app")
    let deep = try fixture.repository("a/b/c/deep")
    try fixture.repository("a/b/c/d/tooDeep")
    try fixture.repository("app/vendor/nested")
    try fixture.worktree("worktrees/wt")
    try fixture.repository(".hidden/dotted")
    try fixture.repository("Documents/notes")
    try fixture.repository("Library/caches")

    let found = try await GitRepositoryScanner(homeDirectory: fixture.root)
        .scan()
        .map(\.url.lastPathComponent)

    #expect(Set(found) == ["app", "deep"])
    #expect(!found.contains("tooDeep"))     // depth 5
    #expect(!found.contains("nested"))      // inside another repository
    #expect(!found.contains("wt"))          // .git is a file
    #expect(!found.contains("dotted"))      // under a dot-directory
    #expect(!found.contains("notes"))       // skip list
    #expect(!found.contains("caches"))      // skip list
}

@Test func scannerRanksMostRecentlyModifiedFirstAndCapsTheList() async throws {
    let fixture = try ScannerFixture()
    defer { fixture.cleanup() }

    for index in 0..<(GitRepositoryScanner.maximumResults + 3) {
        try fixture.repository(
            "repo-\(index)",
            modified: Date(timeIntervalSince1970: TimeInterval(index)))
    }

    let found = try await GitRepositoryScanner(homeDirectory: fixture.root).scan()

    #expect(found.count == GitRepositoryScanner.maximumResults)
    #expect(found.first?.url.lastPathComponent == "repo-14")
    #expect(found.map(\.modified) == found.map(\.modified).sorted(by: >))
}

@Test func scannerDoesNotFollowASymbolicLinkCycle() async throws {
    let fixture = try ScannerFixture()
    defer { fixture.cleanup() }

    let branch = try fixture.directory("branch")
    try fixture.repository("branch/real")
    try FileManager.default.createSymbolicLink(
        at: branch.appending(path: "loop"),
        withDestinationURL: fixture.root)

    let found = try await GitRepositoryScanner(homeDirectory: fixture.root).scan()

    #expect(found.map(\.url.lastPathComponent) == ["real"])
}

@Test func scannerStopsWhenItsTaskIsCancelled() async throws {
    let fixture = try ScannerFixture()
    defer { fixture.cleanup() }
    for index in 0..<200 { try fixture.repository("repo-\(index)") }

    let scan = Task { try await GitRepositoryScanner(homeDirectory: fixture.root).scan() }
    scan.cancel()

    await #expect(throws: CancellationError.self) { _ = try await scan.value }
}
