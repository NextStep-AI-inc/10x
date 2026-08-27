import AppKit
import SwiftUI

struct OnboardingProjectStepView: View {
    let model: AppModel

    @State private var chosen: Set<String> = []

    /// Project directories 10x already knows about, from existing sessions.
    /// No disk crawling: this reuses the same derivation as the composer's
    /// project flyout.
    private var suggestions: [URL] {
        ProjectSessionGrouper.choosableProjectURLs(from: model.sessions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !suggestions.isEmpty {
                Text("Recent projects")
                    .font(TenXTypography.body(size: 12, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions, id: \.path) { url in
                            OnboardingRowView(
                                title: url.lastPathComponent,
                                detail: url.path
                            ) {
                                if chosen.contains(url.standardizedFileURL.path) {
                                    Text("Added")
                                        .font(TenXTypography.body(size: 12))
                                        .foregroundStyle(
                                            TenXPalette.color(TenXPalette.mutedTextHex))
                                } else {
                                    Button("Add") { choose(url) }
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
    }

    private func choose(_ url: URL) {
        model.recordOnboardingProject(url)
        chosen.insert(url.standardizedFileURL.path)
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
