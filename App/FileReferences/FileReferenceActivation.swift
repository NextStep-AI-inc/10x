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
