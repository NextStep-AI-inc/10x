enum AppRoute: Equatable {
    case setup
    case providerSetup
    case newSession
    case session(String)
    case archivedSessions
    case settings
    case providers(ProviderWorkspaceSection)
}
