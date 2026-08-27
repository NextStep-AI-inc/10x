import AppKit
import SwiftUI

/// Which project folders this step shows as chosen, and which folders the
/// user picked from disk this session (most recently picked first).
///
/// A plain value type, extracted from `OnboardingProjectStepView` so
/// folder-picking behavior is testable without driving `NSOpenPanel`, which
/// cannot run in tests.
struct OnboardingProjectSelection: Equatable {
    private(set) var pickedFolders: [URL] = []
    private(set) var chosen: Set<String> = []

    init() {}

    /// Seeds from a project already selected before this step appeared
    /// (e.g. carried over from an earlier presentation of this step), so it
    /// is not invisible on first render the way an unseeded pick was.
    init(seeding selectedProjectURL: URL?) {
        guard let selectedProjectURL else { return }
        pick(selectedProjectURL)
    }

    func isAdded(_ url: URL) -> Bool {
        chosen.contains(url.standardizedFileURL.path)
    }

    /// Marks `url` added without affecting `pickedFolders` order. Used when
    /// the user clicks "Add" on a session suggestion that is already in the
    /// list.
    mutating func markAdded(_ url: URL) {
        chosen.insert(url.standardizedFileURL.path)
    }

    /// The effect of picking `url` via "Choose folder…": it leads
    /// `pickedFolders` (moved to the front if already present there) and is
    /// marked added.
    mutating func pick(_ url: URL) {
        let standardized = url.standardizedFileURL
        pickedFolders.removeAll { $0.standardizedFileURL.path == standardized.path }
        pickedFolders.insert(standardized, at: 0)
        markAdded(url)
    }

    /// `pickedFolders` followed by `suggestions`, de-duplicated by
    /// standardized path so a picked folder that is also a session project
    /// appears once.
    func projects(suggestions: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in pickedFolders + suggestions {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                result.append(url)
            }
        }
        return result
    }
}

struct OnboardingProjectStepView: View {
    let model: AppModel

    @State private var selection: OnboardingProjectSelection

    init(model: AppModel, initialSelection: OnboardingProjectSelection? = nil) {
        self.model = model
        _selection = State(
            initialValue: initialSelection ?? OnboardingProjectSelection(seeding: model.selectedProjectURL))
    }

    /// Project directories 10x already knows about, from existing sessions
    /// and from projects recorded without one (e.g. a folder picked in an
    /// earlier onboarding attempt). No disk crawling: this reuses the same
    /// derivation as the composer's project flyout. A folder just picked
    /// via "Choose folder…" this session is recorded into the same store
    /// this reads from, so it can appear here too — `projects(suggestions:)`
    /// dedupes it against `pickedFolders` by standardized path.
    private var suggestions: [URL] {
        ProjectSessionGrouper.choosableProjectURLs(
            from: model.sessions,
            knownProjectURLs: model.knownProjectURLs)
    }

    /// Folders picked from disk this session, followed by session
    /// suggestions. Renders whenever this is non-empty, so a picked folder
    /// makes the list appear even with no sessions.
    private var projects: [URL] {
        selection.projects(suggestions: suggestions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !projects.isEmpty {
                Text("Projects")
                    .font(TenXTypography.body(size: 12, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(projects, id: \.path) { url in
                            OnboardingRowView(
                                title: url.lastPathComponent,
                                detail: url.path
                            ) {
                                if selection.isAdded(url) {
                                    Text("Added")
                                        .font(TenXTypography.body(size: 12))
                                        .foregroundStyle(
                                            TenXPalette.color(TenXPalette.mutedTextHex))
                                } else {
                                    Button("Add") { addSuggestion(url) }
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

    private func addSuggestion(_ url: URL) {
        model.recordOnboardingProject(url)
        selection.markAdded(url)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.recordOnboardingProject(url)
        selection.pick(url)
    }
}
