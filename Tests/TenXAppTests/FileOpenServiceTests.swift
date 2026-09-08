import Foundation
import Testing
@testable import TenXApp

private enum FileOpenServiceTestError: Error, Equatable {
    case failedToOpen
}

@MainActor
@Test func opensWithSystemDefaultUsingRequestedURL() throws {
    var openedURL: URL?
    let fileURL = URL(filePath: "/tmp/10x/App/File.swift")
    let service = FileOpenService(
        openDefault: { openedURL = $0 },
        openInApplication: { _, _ in },
        reveal: { _ in },
        startSecurityScope: { _ in false },
        stopSecurityScope: { _ in })

    try service.openWithSystemDefault(fileURL)

    #expect(openedURL == fileURL)
}

@MainActor
@Test func opensKnownIDEWithoutSecurityScopedAccess() async throws {
    var events: [String] = []
    let fileURL = URL(filePath: "/tmp/10x/App/File.swift")
    let application = IDEApplication(
        displayName: "Xcode",
        url: URL(filePath: "/Applications/Xcode.app"),
        source: .known(bundleIdentifier: "com.apple.dt.Xcode"))
    let service = FileOpenService(
        openDefault: { _ in },
        openInApplication: { fileURL, applicationURL in
            events.append("open:\(fileURL.path):\(applicationURL.path)")
        },
        reveal: { _ in },
        startSecurityScope: { url in
            events.append("start:\(url.path)")
            return true
        },
        stopSecurityScope: { url in events.append("stop:\(url.path)") })

    try await service.open(fileURL, in: application)

    #expect(events == ["open:/tmp/10x/App/File.swift:/Applications/Xcode.app"])
}

@MainActor
@Test func customIDEOpenBalancesSecurityScopedAccess() async throws {
    var events: [String] = []
    let service = FileOpenService(
        openDefault: { _ in events.append("default") },
        openInApplication: { fileURL, applicationURL in
            events.append("open:\(fileURL.path):\(applicationURL.path)")
        },
        reveal: { url in events.append("reveal:\(url.path)") },
        startSecurityScope: { url in
            events.append("start:\(url.path)")
            return true
        },
        stopSecurityScope: { url in events.append("stop:\(url.path)") })
    let application = IDEApplication(
        displayName: "Custom IDE",
        url: URL(filePath: "/Applications/Custom IDE.app"),
        source: .custom)

    try await service.open(URL(filePath: "/tmp/File.swift"), in: application)

    #expect(events == [
        "start:/Applications/Custom IDE.app",
        "open:/tmp/File.swift:/Applications/Custom IDE.app",
        "stop:/Applications/Custom IDE.app",
    ])
}

@MainActor
@Test func customIDEOpenPropagatesFailureAfterStoppingSecurityScopedAccess() async {
    var events: [String] = []
    let applicationURL = URL(filePath: "/Applications/Custom IDE.app")
    let service = FileOpenService(
        openDefault: { _ in },
        openInApplication: { fileURL, applicationURL in
            events.append("open:\(fileURL.path):\(applicationURL.path)")
            throw FileOpenServiceTestError.failedToOpen
        },
        reveal: { _ in },
        startSecurityScope: { url in
            events.append("start:\(url.path)")
            return true
        },
        stopSecurityScope: { url in events.append("stop:\(url.path)") })
    let application = IDEApplication(displayName: "Custom IDE", url: applicationURL, source: .custom)

    await #expect(throws: FileOpenServiceTestError.failedToOpen) {
        try await service.open(URL(filePath: "/tmp/File.swift"), in: application)
    }

    #expect(events == [
        "start:/Applications/Custom IDE.app",
        "open:/tmp/File.swift:/Applications/Custom IDE.app",
        "stop:/Applications/Custom IDE.app",
    ])
}

@MainActor
@Test func revealsRequestedURLInFinder() {
    var revealedURL: URL?
    let fileURL = URL(filePath: "/tmp/10x/App/File.swift")
    let service = FileOpenService(
        openDefault: { _ in },
        openInApplication: { _, _ in },
        reveal: { revealedURL = $0 },
        startSecurityScope: { _ in false },
        stopSecurityScope: { _ in })

    service.reveal(fileURL)

    #expect(revealedURL == fileURL)
}
