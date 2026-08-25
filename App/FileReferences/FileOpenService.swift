import AppKit

struct FileOpenService: Sendable {
    private enum OpenError: Error {
        case failed
    }

    let openDefault: @MainActor @Sendable (URL) throws -> Void
    let openInApplication: @MainActor @Sendable (URL, URL) async throws -> Void
    let revealOperation: @MainActor @Sendable (URL) -> Void
    let startSecurityScope: @MainActor @Sendable (URL) -> Bool
    let stopSecurityScope: @MainActor @Sendable (URL) -> Void

    init(
        openDefault: @escaping @MainActor @Sendable (URL) throws -> Void,
        openInApplication: @escaping @MainActor @Sendable (URL, URL) async throws -> Void,
        reveal: @escaping @MainActor @Sendable (URL) -> Void,
        startSecurityScope: @escaping @MainActor @Sendable (URL) -> Bool,
        stopSecurityScope: @escaping @MainActor @Sendable (URL) -> Void
    ) {
        self.openDefault = openDefault
        self.openInApplication = openInApplication
        revealOperation = reveal
        self.startSecurityScope = startSecurityScope
        self.stopSecurityScope = stopSecurityScope
    }

    @MainActor
    func openWithSystemDefault(_ url: URL) throws {
        try openDefault(url)
    }

    @MainActor
    func open(_ url: URL, in application: IDEApplication) async throws {
        let didAccess = application.source == .custom && startSecurityScope(application.url)
        defer {
            if didAccess {
                stopSecurityScope(application.url)
            }
        }
        try await openInApplication(url, application.url)
    }

    @MainActor
    func reveal(_ url: URL) {
        revealOperation(url)
    }
}

extension FileOpenService {
    static let live = FileOpenService(
        openDefault: { url in
            guard NSWorkspace.shared.open(url) else {
                throw OpenError.failed
            }
        },
        openInApplication: { url, applicationURL in
            try await withCheckedThrowingContinuation { continuation in
                NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: applicationURL,
                    configuration: .init()) { application, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if application == nil {
                            continuation.resume(throwing: OpenError.failed)
                        } else {
                            continuation.resume()
                        }
                    }
            }
        },
        reveal: { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        },
        startSecurityScope: { url in
            url.startAccessingSecurityScopedResource()
        },
        stopSecurityScope: { url in
            url.stopAccessingSecurityScopedResource()
        })
}
