import Foundation
import Testing
@testable import TenXApp

@Test func locatorAcceptsPreferredExecutableAndReadsItsVersion() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "tenx-locator-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let executable = directory.appending(path: "omp")
    try "#!/bin/sh\nprintf '18.0.4\\n'\n".write(
        to: executable,
        atomically: true,
        encoding: .utf8)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path)

    let installation = await OmpExecutableLocator().locate(preferredURL: executable)

    #expect(installation == OmpInstallation(
        executableURL: executable.standardizedFileURL,
        version: "18.0.4"))
}
