import AppKit
import SwiftUI

struct OnboardingProjectStepView: View {
    let model: AppModel
    /// Injectable so a snapshot test can point the scan at a fixture tree.
    var scanner = GitRepositoryScanner()

    @State private var suggestions: [GitRepositorySuggestion] = []
    @State private var chosen: Set<String> = []
    @State private var isScanning = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isScanning {
                OnboardingSkeletonRows()
            } else if suggestions.isEmpty {
                Text("No Git repositories found in your home folder.")
                    .font(TenXTypography.body(size: 13))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            } else {
                Text("Found in your home folder")
                    .font(TenXTypography.body(size: 12, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions) { suggestion in
                            OnboardingRowView(
                                title: suggestion.url.lastPathComponent,
                                detail: suggestion.url.path
                            ) {
                                if chosen.contains(suggestion.id) {
                                    Text("Added")
                                        .font(TenXTypography.body(size: 12))
                                        .foregroundStyle(
                                            TenXPalette.color(TenXPalette.mutedTextHex))
                                } else {
                                    Button("Add") { choose(suggestion.url) }
                                        .buttonStyle(GhostActionStyle())
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
                .frame(height: 126)
            }

            HStack(spacing: 12) {
                Button("Continue") { model.gateRoute() }
                    .buttonStyle(GhostActionStyle())
                    .disabled(model.selectedProjectURL == nil)
                Button("Choose folder…") { chooseFolder() }
                    .buttonStyle(GhostActionStyle(
                        color: TenXPalette.color(TenXPalette.nearBlackHex)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            // Cancelled automatically when the step goes away.
            suggestions = (try? await scanner.scan()) ?? []
            isScanning = false
        }
    }

    private func choose(_ url: URL) {
        model.recordOnboardingProject(url)
        chosen.insert(GitRepositorySuggestion(url: url, modified: .distantPast).id)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        choose(url)
    }
}
