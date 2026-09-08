import Foundation
import OmpKit

struct SessionRenameRequest: Identifiable, Equatable {
    let path: String
    let cwd: String
    let originalTitle: String
    var draft: String
    var errorMessage: String?

    var id: String { path }

    var normalizedTitle: String? {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    init(metadata: SessionMetadata) {
        let title = metadata.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session"
        path = metadata.path
        cwd = metadata.cwd
        originalTitle = title
        draft = title
        errorMessage = nil
    }

    init(path: String, cwd: String, title: String) {
        self.path = path
        self.cwd = cwd
        originalTitle = title
        draft = title
        errorMessage = nil
    }
}
