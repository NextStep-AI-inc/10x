import SwiftUI
import OmpKit

struct ModelRoleEntry: Equatable, Identifiable {
    var id: String { role }
    var role: String
    var value: ModelRoleValue
}

struct ModelRolesEditor: View {
    let definition: SettingDefinition
    let model: SettingsViewModel

    @State private var entries: [ModelRoleEntry]

    static let knownRoles = ["default", "plan", "advisor", "smol", "commit",
                             "designer", "slow", "task", "tiny", "vision"]

    init(definition: SettingDefinition, model: SettingsViewModel) {
        self.definition = definition
        self.model = model
        _entries = State(initialValue: Self.entries(from: definition.value ?? .object([:])))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($entries) { $entry in
                HStack(spacing: 8) {
                    Text(entry.role)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
                        .frame(width: 70, alignment: .leading)
                    InlineDropdown(
                        options: Self.modelOptions(from: model.catalogModels),
                        current: "\(entry.value.provider)/\(entry.value.modelID)",
                        onSelect: { selection in
                            if let parsed = ModelRoleValue(raw: selection) {
                                entry.value.provider = parsed.provider
                                entry.value.modelID = parsed.modelID
                                entry.value.effort = nil
                                save()
                            }
                        })
                    if !effortOptions(for: entry.value).isEmpty {
                        InlineDropdown(
                            options: effortOptions(for: entry.value),
                            current: entry.value.effort ?? "",
                            prompt: "effort",
                            allowsOther: false,
                            onSelect: { effort in
                                entry.value.effort = effort.isEmpty ? nil : effort
                                save()
                            })
                        .frame(width: 90)
                    }
                    Button {
                        entries.removeAll { $0.role == entry.role }
                        save()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                    .accessibilityLabel("Remove \(entry.role)")
                }
            }
            let unused = Self.knownRoles.filter { role in !entries.contains { $0.role == role } }
            if !unused.isEmpty {
                Menu("Add role") {
                    ForEach(unused, id: \.self) { role in
                        Button(role) {
                            entries.append(ModelRoleEntry(role: role, value: defaultValue(for: role)))
                            sortEntries()
                            save()
                        }
                    }
                }
                .font(TenXTypography.body(size: 12, weight: .medium))
                .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
            }
            Text("Saved as a whole record; removing all rows restores OMP defaults.")
                .font(TenXTypography.body(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
        .task { await model.loadCatalogIfNeeded() }
        .onChange(of: definition.value) { _, newValue in
            let serialized = Self.jsonObject(from: entries, preserving: newValue ?? .object([:]))
            if serialized != newValue {
                entries = Self.entries(from: newValue ?? .object([:]))
            }
        }
    }

    private func defaultValue(for role: String) -> ModelRoleValue {
        // New roles start from the "default" role's model when one is set.
        if let d = entries.first(where: { $0.role == "default" })?.value { return d }
        return ModelRoleValue(provider: "", modelID: "", effort: nil)
    }

    private func effortOptions(for value: ModelRoleValue) -> [SettingOption] {
        guard let found = model.catalogModels.first(where: {
            $0.provider == value.provider && $0.modelID == value.modelID
        }), !found.thinkingEfforts.isEmpty else { return [] }
        return found.thinkingEfforts.map { SettingOption($0) }
    }

    private func sortEntries() {
        entries.sort { a, b in
            let ia = Self.knownRoles.firstIndex(of: a.role) ?? .max
            let ib = Self.knownRoles.firstIndex(of: b.role) ?? .max
            return ia == ib ? a.role < b.role : ia < ib
        }
    }

    private func save() {
        let object = Self.jsonObject(from: entries, preserving: definition.value ?? .object([:]))
        Task { await model.save(definition, value: object) }
    }

    nonisolated static func entries(from value: JSONValue) -> [ModelRoleEntry] {
        let object = value.objectValue ?? [:]
        return object.compactMap { role, raw in
            raw.stringValue.flatMap(ModelRoleValue.init(raw:)).map {
                ModelRoleEntry(role: role, value: $0)
            }
        }.sorted { a, b in
            let ia = knownRoles.firstIndex(of: a.role) ?? .max
            let ib = knownRoles.firstIndex(of: b.role) ?? .max
            return ia == ib ? a.role < b.role : ia < ib
        }
    }

    /// Serializes edited entries; roles whose values never parsed are carried
    /// over from the original record so editing can't silently drop them.
    nonisolated static func jsonObject(from entries: [ModelRoleEntry], preserving original: JSONValue) -> JSONValue {
        var object = original.objectValue ?? [:]
        for entry in entries {
            object[entry.role] = .string(entry.value.raw)
        }
        let editedRoles = Set(entries.map(\.role))
        let originallyParsed = Set(Self.entries(from: original).map(\.role))
        for role in originallyParsed where !editedRoles.contains(role) {
            object[role] = nil
        }
        return .object(object)
    }

    nonisolated static func modelOptions(from models: [ComposerModelInfo]) -> [SettingOption] {
        models.map { SettingOption("\($0.provider)/\($0.modelID)", label: $0.name, detail: $0.provider) }
    }
}
