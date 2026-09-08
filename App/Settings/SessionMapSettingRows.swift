import SwiftUI

struct SessionMapSettingRows: View {
    struct Choice: Equatable {
        let title: String
        let selection: SessionMapModelSelection?
    }

    let presentation: Presentation
    let isLoading: Bool
    let errorMessage: String?

    @MainActor
    struct Presentation {
        let preferences: SessionMapPreferenceStore
        let catalog: [ComposerModelInfo]
        let roles: [String: String]
        var writerChoices: [Choice] {
            roleChoices(requiringImages: false) + modelChoices(requiringImages: false)
        }

        var checkerChoices: [Choice] {
            [Choice(title: "Off", selection: nil)]
                + roleChoices(requiringImages: true)
                + modelChoices(requiringImages: true)
        }

        var resolvedWriter: SessionMapResolvedModel? {
            SessionMapModelResolver.resolve(
                selection: preferences.writerSelection, catalog: catalog, roles: roles)
        }

        var resolvedChecker: SessionMapResolvedModel? {
            preferences.checkerSelection.flatMap {
                SessionMapModelResolver.resolve(selection: $0, catalog: catalog, roles: roles)
            }
        }

        private func roleChoices(requiringImages: Bool) -> [Choice] {
            roles.keys.sorted().compactMap { role in
                guard let resolved = SessionMapModelResolver.resolve(
                    selection: .role(role), catalog: catalog, roles: roles),
                      !requiringImages || resolved.acceptsImages
                else { return nil }
                return Choice(title: "Role: \(role)", selection: .role(role))
            }
        }

        private func modelChoices(requiringImages: Bool) -> [Choice] {
            catalog.filter { !requiringImages || $0.acceptsImages }.sorted {
                $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }.flatMap { model in
                let base = model.requiresEffort ? [] : [Choice(
                    title: "\(model.name) · \(model.provider)",
                    selection: .model(id: model.id, effort: nil))]
                return base + model.thinkingEfforts.map { effort in
                    Choice(
                        title: "\(model.name) · \(model.provider) · \(effort)",
                        selection: .model(id: model.id, effort: effort))
                }
            }
        }
    }

    var body: some View {
        preferenceRow(
            title: "Writer model",
            detail: "Updates an open map after completed turns."
        ) {
            selectionMenu(
                choices: presentation.writerChoices,
                selected: presentation.preferences.writerSelection,
                accessibilityLabel: "Session Map writer model"
            ) { selection in
                guard let selection else { return }
                presentation.preferences.writerSelection = selection
            }
        }
        Divider()
        preferenceRow(
            title: "Checker model",
            detail: "Checks structural map changes with an image-capable model."
        ) {
            selectionMenu(
                choices: presentation.checkerChoices,
                selected: presentation.preferences.checkerSelection,
                accessibilityLabel: "Session Map checker model"
            ) { presentation.preferences.checkerSelection = $0 }
        }
        Divider()
        preferenceRow(
            title: "Unattended updates",
            detail: "Allow map updates after completed turns when the map is closed."
        ) {
            Toggle("", isOn: Binding(
                get: {
                    presentation.resolvedWriter != nil
                        && presentation.preferences.isUnattendedGenerationEnabled
                },
                set: { presentation.preferences.isUnattendedGenerationEnabled = $0 }))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(TenXPalette.color(TenXPalette.cyanHex))
                .disabled(presentation.resolvedWriter == nil)
                .accessibilityLabel("Unattended Session Map updates")
        }
    }

    private func selectionMenu(
        choices: [Choice],
        selected: SessionMapModelSelection?,
        accessibilityLabel: String,
        onSelect: @escaping (SessionMapModelSelection?) -> Void
    ) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Menu {
                ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                    Button(choice.title) { onSelect(choice.selection) }
                }
            } label: {
                Text(selectionTitle(selected, choices: choices))
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue(selected, choices: choices))

            if let resolved = resolved(selected) {
                Text(resolvedTitle(resolved))
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            } else if isLoading {
                Text("Loading models…")
                    .font(TenXTypography.mono(size: 9))
            } else if let errorMessage {
                Text(errorMessage)
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
            } else if selected != nil {
                Text("Unavailable")
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
            }
        }
        .frame(width: 300, alignment: .trailing)
    }

    private func preferenceRow<Control: View>(
        title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(TenXTypography.body(size: 13, weight: .semibold))
                Text(detail)
                    .font(TenXTypography.body(size: 11))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .padding(.vertical, 15)
        .accessibilityElement(children: .contain)
    }

    private func selectionTitle(
        _ selection: SessionMapModelSelection?,
        choices: [Choice]
    ) -> String {
        choices.first { $0.selection == selection }?.title ?? "Choose a model"
    }

    private func resolved(_ selection: SessionMapModelSelection?) -> SessionMapResolvedModel? {
        selection.flatMap {
            SessionMapModelResolver.resolve(
                selection: $0, catalog: presentation.catalog, roles: presentation.roles)
        }
    }

    private func resolvedTitle(_ model: SessionMapResolvedModel) -> String {
        [model.provider, model.modelID, model.effort].compactMap { $0 }.joined(separator: " / ")
    }

    private func accessibilityValue(
        _ selection: SessionMapModelSelection?,
        choices: [Choice]
    ) -> String {
        let title = selectionTitle(selection, choices: choices)
        guard let resolved = resolved(selection) else { return title }
        return "\(title), \(resolvedTitle(resolved))"
    }

    nonisolated static func matches(query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return [
            "Map", "Session Map", "writer model", "checker model", "unattended",
            "completed turns", "background updates",
        ].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
