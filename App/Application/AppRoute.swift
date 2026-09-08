enum AppRoute: Equatable {
    case onboarding(OnboardingStep)
    case newSession
    case session(String)
    case archivedSessions
    case settings
    case providers(ProviderWorkspaceSection)
}
