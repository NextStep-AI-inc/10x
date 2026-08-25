import OmpKit
import SwiftUI

struct ArchivedSessionsView: View {
    let model: AppModel

    private var groups: [ProjectSessionGroup] {
        ProjectSessionGrouper.groups(model.archivedSessions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Archived")
                    .font(TenXTypography.title(size: 34))
                Text("Restore session history or delete it permanently.")
                    .font(TenXTypography.body(size: 13))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            }
            .padding(.top, 62)
            .padding(.bottom, 22)

            if groups.isEmpty {
                Label("No archived sessions", systemImage: "archivebox")
                    .font(TenXTypography.body(size: 13))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { group in
                            groupSection(group)
                        }
                    }
                    .padding(.bottom, 60)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: 960)
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await model.reloadArchivedSessions()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Archived sessions")
    }

    private func groupSection(_ group: ProjectSessionGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(group.displayName)
                    .font(TenXTypography.accent(size: 19))
                Spacer()
                Text(sessionCount(group.sessions.count))
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
            }
            .padding(.top, 26)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .focusable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(group.displayName), \(sessionCount(group.sessions.count))")
            .contextMenu {
                Button("Restore Project Sessions", systemImage: "arrow.uturn.backward") {
                    Task { await model.restoreProject(group) }
                }
                Button("Delete Project Sessions...", systemImage: "trash", role: .destructive) {
                    model.requestDeleteProject(group)
                }
            }
            .accessibilityAction(named: Text("Restore Project Sessions")) {
                Task { await model.restoreProject(group) }
            }
            .accessibilityAction(named: Text("Delete Project Sessions...")) {
                model.requestDeleteProject(group)
            }

            Rectangle()
                .fill(TenXPalette.color(TenXPalette.cyanHex))
                .frame(height: 2)

            ForEach(group.sessions) { metadata in
                sessionRow(metadata)
                Divider()
            }
        }
    }

    private func sessionRow(_ metadata: SessionMetadata) -> some View {
        let title = metadata.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session"

        return HStack(spacing: 14) {
            Image(systemName: "archivebox")
                .foregroundStyle(TenXPalette.color(TenXPalette.cyanHex))
                .frame(width: 20)
            Text(title)
                .font(TenXTypography.body(size: 13, weight: .medium))
                .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                .lineLimit(1)
            Spacer(minLength: 24)
            Text(metadata.modified, format: .dateTime.month(.abbreviated).day().year())
                .font(TenXTypography.mono(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .focusable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .contextMenu {
            Button("Restore Session", systemImage: "arrow.uturn.backward") {
                Task { await model.restoreSession(metadata) }
            }
            Button("Delete Session...", systemImage: "trash", role: .destructive) {
                model.requestDeleteSession(metadata)
            }
        }
        .accessibilityAction(named: Text("Restore Session")) {
            Task { await model.restoreSession(metadata) }
        }
        .accessibilityAction(named: Text("Delete Session...")) {
            model.requestDeleteSession(metadata)
        }
    }

    private func sessionCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "session" : "sessions")"
    }
}
