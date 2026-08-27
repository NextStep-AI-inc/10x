import Foundation

/// A requirement onboarding collects before the workspace is usable, in the
/// order they are asked for.
enum OnboardingStep: Equatable, Sendable, CaseIterable {
    case installOmp
    case connectProvider
    case chooseProject
}

extension OnboardingStep {
    /// Every requirement these inputs do not satisfy, in order.
    ///
    /// Kept free of `AppModel` so it can be tested as a table: `providerModel`
    /// is `private(set)` and a test cannot populate it.
    ///
    /// The whole set, not just the first, because the step counter must not
    /// count a requirement that is already met. Losing OMP mid-session is the
    /// case that separates them: the provider model goes away with the
    /// runtime, but the chosen project survives.
    static func unmet(
        installation: OmpInstallation?,
        hasAuthenticatedProvider: Bool,
        selectedProjectURL: URL?
    ) -> [OnboardingStep] {
        var steps: [OnboardingStep] = []
        if installation == nil { steps.append(.installOmp) }
        if !hasAuthenticatedProvider { steps.append(.connectProvider) }
        if selectedProjectURL == nil { steps.append(.chooseProject) }
        return steps
    }

    /// The requirement to ask for now, or nil when the workspace is usable.
    static func firstUnmet(
        installation: OmpInstallation?,
        hasAuthenticatedProvider: Bool,
        selectedProjectURL: URL?
    ) -> OnboardingStep? {
        unmet(
            installation: installation,
            hasAuthenticatedProvider: hasAuthenticatedProvider,
            selectedProjectURL: selectedProjectURL).first
    }
}
