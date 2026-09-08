enum FileReferenceActivation: Equatable {
    case openInIDE(IDEApplication)
    case openPreferences
    case revealInFinder
    case unavailable

    static func resolve(
        preference: IDEPreferenceState,
        reference: ResolvedFileReference,
        isOptionPressed: Bool
    ) -> FileReferenceActivation {
        guard reference.exists, reference.url != nil else { return .unavailable }
        if isOptionPressed { return .revealInFinder }

        switch preference {
        case .available(let application):
            return .openInIDE(application)
        case .none, .unavailable:
            return .openPreferences
        }
    }
}

struct FileReferenceActionHandler: Sendable {
    let fileOpenService: FileOpenService
    let openIDEPreferences: OpenIDEPreferencesAction

    @MainActor
    func perform(
        _ action: FileReferenceActivation,
        reference: ResolvedFileReference
    ) async throws {
        switch action {
        case .openInIDE(let application):
            guard reference.exists, let url = reference.url else { return }
            try await fileOpenService.open(url, in: application)
        case .openPreferences:
            openIDEPreferences()
        case .revealInFinder:
            guard reference.exists, let url = reference.url else { return }
            fileOpenService.reveal(url)
        case .unavailable:
            break
        }
    }
}
