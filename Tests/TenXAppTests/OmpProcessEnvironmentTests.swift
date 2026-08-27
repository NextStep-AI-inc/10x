import Foundation
import Testing
@testable import TenXApp

private let home = URL(filePath: "/Users/example", directoryHint: .isDirectory)

/// The PATH a GUI app inherits when launched from Finder — no Homebrew, no ~/.bun.
private let launchServicesPath = "/usr/bin:/bin:/usr/sbin:/sbin"

private func path(_ environment: [String: String]) -> [String] {
    (environment["PATH"] ?? "").split(separator: ":").map(String.init)
}

@Test func finderLaunchGainsTheDirectoriesHoldingOmpAndItsInterpreter() {
    let resolved = OmpProcessEnvironment.resolved(
        base: ["PATH": launchServicesPath],
        homeDirectory: home)

    #expect(path(resolved).contains("/Users/example/.bun/bin"))
    #expect(path(resolved).contains("/opt/homebrew/bin"))
    #expect(path(resolved).contains("/usr/local/bin"))
}

@Test func inheritedEntriesAreKeptAndStillTakePrecedence() {
    let resolved = OmpProcessEnvironment.resolved(
        base: ["PATH": launchServicesPath],
        homeDirectory: home)

    let entries = path(resolved)
    #expect(entries.prefix(4) == ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
}

@Test func aDirectoryAlreadyOnPathIsNotAddedTwice() {
    let resolved = OmpProcessEnvironment.resolved(
        base: ["PATH": "/opt/homebrew/bin:/usr/bin"],
        homeDirectory: home)

    #expect(path(resolved).filter { $0 == "/opt/homebrew/bin" }.count == 1)
}

@Test func aMissingOrEmptyPathStillProducesAUsableOne() {
    for base in [[:], ["PATH": ""]] as [[String: String]] {
        let resolved = OmpProcessEnvironment.resolved(base: base, homeDirectory: home)
        #expect(path(resolved).contains("/opt/homebrew/bin"))
        #expect(!path(resolved).contains(""))
    }
}

@Test func everythingOtherThanPathIsPassedThroughUntouched() {
    let resolved = OmpProcessEnvironment.resolved(
        base: ["PATH": launchServicesPath, "HOME": "/Users/example", "TERM": "xterm"],
        homeDirectory: home)

    #expect(resolved["HOME"] == "/Users/example")
    #expect(resolved["TERM"] == "xterm")
}

@Test func aShellLaunchIsLeftAlone() {
    // Already-complete PATH: the same set comes back, order intact, nothing appended.
    let shellPath = "/Users/example/.bun/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    let resolved = OmpProcessEnvironment.resolved(
        base: ["PATH": shellPath],
        homeDirectory: home)

    #expect(resolved["PATH"] == shellPath)
}
