import Testing
import Foundation
@testable import OmpKit

@Test func resolvesBareNameOnPath() {
    let resolved = LineTransport.resolveExecutable(
        "ls", environment: ["PATH": "/usr/bin:/bin"])
    #expect(resolved?.path == "/bin/ls" || resolved?.path == "/usr/bin/ls")
}

@Test func resolvesAbsolutePathDirectly() {
    #expect(LineTransport.resolveExecutable("/bin/ls", environment: nil)?.path == "/bin/ls")
}

@Test func rejectsMissingAbsolutePath() {
    #expect(LineTransport.resolveExecutable("/nope/nothing", environment: nil) == nil)
}

@Test func rejectsBareNameNotOnPath() {
    #expect(LineTransport.resolveExecutable(
        "definitely-not-a-real-binary", environment: ["PATH": "/usr/bin:/bin"]) == nil)
}

@Test func searchesPathInOrder() {
    // An empty first entry must not stop the search.
    let resolved = LineTransport.resolveExecutable(
        "ls", environment: ["PATH": "/nonexistent:/bin"])
    #expect(resolved?.path == "/bin/ls")
}
