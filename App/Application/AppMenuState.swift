import OmpKit

struct AppMenuState {
    let isWorkspaceAvailable: Bool
    let currentSessionPath: String?
    let previousSession: SessionMetadata?
    let nextSession: SessionMetadata?
    let canStopResponse: Bool
    let canChooseMessageBehavior: Bool
    let canArchiveSession: Bool

    init(
        route: AppRoute,
        sessions: [SessionMetadata],
        activeSessionPath: String?,
        runtimeState: SessionRuntimeState?,
        isSessionMutationInFlight: Bool
    ) {
        isWorkspaceAvailable = !isSessionMutationInFlight && !route.isOnboarding

        let routeSessionPath: String? = if case .session(let path) = route { path } else { nil }
        currentSessionPath = activeSessionPath ?? routeSessionPath

        let currentIndex = isWorkspaceAvailable
            ? currentSessionPath.flatMap { currentPath in
                sessions.firstIndex { $0.path == currentPath }
            }
            : nil
        previousSession = currentIndex.flatMap { index in
            index > sessions.startIndex ? sessions[index - 1] : nil
        }
        nextSession = currentIndex.flatMap { index in
            sessions.index(after: index) < sessions.endIndex ? sessions[index + 1] : nil
        }

        let isStreaming = runtimeState == .streaming
        canStopResponse = isWorkspaceAvailable && isStreaming
        canChooseMessageBehavior = isWorkspaceAvailable && isStreaming
        canArchiveSession = isWorkspaceAvailable && currentSessionPath != nil
    }
}

private extension AppRoute {
    var isOnboarding: Bool {
        if case .onboarding = self { return true }
        return false
    }
}
