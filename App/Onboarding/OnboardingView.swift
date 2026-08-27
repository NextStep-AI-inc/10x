import SwiftUI

struct OnboardingView: View {
    let model: AppModel
    let step: OnboardingStep
    /// Forwarded to `OnboardingProjectStepView` so a snapshot test can point
    /// the scan at a fixture tree without changing production call sites.
    var projectScanner = GitRepositoryScanner()

    /// The unmet steps as of when onboarding was entered. Held so the counter
    /// does not shrink underneath the user as requirements are satisfied.
    @State private var entrySteps: [OnboardingStep] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            BrandWordmark(width: 48)

            VStack(alignment: .leading, spacing: 8) {
                if let position {
                    Text("Step \(position) of \(entrySteps.count)")
                        .font(TenXTypography.body(size: 12))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                }
                Text(title)
                    .font(TenXTypography.title(size: 38))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                Text(explanation)
                    .font(TenXTypography.body(size: 14))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }

            content

            if let previous {
                Button("Back") { model.route = .onboarding(previous) }
                    .buttonStyle(GhostActionStyle(
                        color: TenXPalette.color(TenXPalette.nearBlackHex)))
            }
        }
        .frame(width: 470, alignment: .leading)
        .padding(56)
        .task {
            // Captured once: the counter must not shrink underneath the user
            // as they satisfy requirements.
            guard entrySteps.isEmpty else { return }
            entrySteps = model.unmetRequirements()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .installOmp:
            OnboardingInstallStepView(model: model)
        case .connectProvider:
            if let providerModel = model.providerModel {
                ProviderSetupView(
                    model: providerModel,
                    onContinue: model.completeProviderSetup)
            }
        case .chooseProject:
            OnboardingProjectStepView(model: model, scanner: projectScanner)
        }
    }

    private var position: Int? {
        entrySteps.firstIndex(of: step).map { $0 + 1 }
    }

    /// The step before this one within the entry set, if any.
    private var previous: OnboardingStep? {
        guard let index = entrySteps.firstIndex(of: step), index > 0 else { return nil }
        return entrySteps[index - 1]
    }

    private var title: String {
        switch step {
        case .installOmp:
            model.installation != nil
                ? "Using OMP"
                : (model.unrunnableOmpURL == nil ? "Install OMP" : "OMP won’t run")
        case .connectProvider: "Connect a provider"
        case .chooseProject: "Choose a project"
        }
    }

    private var explanation: String {
        switch step {
        case .installOmp:
            if model.installation != nil { return "10x is ready to start sessions." }
            return model.unrunnableOmpURL == nil
                ? "10x starts and resumes agent sessions through OMP."
                : "10x found OMP but couldn’t run it. Its interpreter may be missing."
        case .connectProvider:
            return "Choose at least one provider to start sessions."
        case .chooseProject:
            return "Sessions run in a project folder."
        }
    }
}
