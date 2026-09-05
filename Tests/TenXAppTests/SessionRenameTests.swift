import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Suite struct SessionRenameTests {
    @Test func requestPrefillsThePersistedTitle() {
        let request = SessionRenameRequest(metadata: renameMetadata(title: "Course navigation"))

        #expect(request.id == "/tmp/sessions/rename.jsonl")
        #expect(request.draft == "Course navigation")
        #expect(request.originalTitle == "Course navigation")
        #expect(request.normalizedTitle == "Course navigation")
        #expect(request.errorMessage == nil)
    }

    @Test func requestUsesTheUntitledFallback() {
        let request = SessionRenameRequest(metadata: renameMetadata(title: ""))

        #expect(request.draft == "Untitled session")
        #expect(request.originalTitle == "Untitled session")
    }

    @Test func normalizedTitleTrimsInputAndRejectsBlankNames() {
        var request = SessionRenameRequest(metadata: renameMetadata(title: "Before"))

        request.draft = "  After  \n"
        #expect(request.normalizedTitle == "After")

        request.draft = " \n\t "
        #expect(request.normalizedTitle == nil)
    }
}

private func renameMetadata(title: String?) -> SessionMetadata {
    SessionMetadata(
        path: "/tmp/sessions/rename.jsonl",
        sessionId: "rename",
        cwd: "/tmp/project",
        title: title,
        created: .distantPast,
        modified: .distantPast,
        sizeBytes: 100,
        status: .complete)
}
