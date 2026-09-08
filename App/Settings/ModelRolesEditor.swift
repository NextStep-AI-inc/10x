import SwiftUI
import OmpKit

struct ModelRoleEntry: Equatable, Identifiable {
    var id: String { role }
    var role: String
    var value: ModelRoleValue
    var unrecognizedRaw: String?

    var isUnrecognized: Bool { unrecognizedRaw != nil }

    init(role: String, value: ModelRoleValue, unrecognizedRaw: String? = nil) {
        self.role = role
        self.value = value
        self.unrecognizedRaw = unrecognizedRaw
    }
}

struct ModelRolesEditor: View {
    let definition: SettingDefinition
    let model: SettingsViewModel

    @State private var entries: [ModelRoleEntry]

    static let knownRoles = SettingMetadata.knownArrayValues["cycleOrder"]
        ?? ["default", "plan", "advisor", "smol", "commit",
            "designer", "slow", "task", "tiny", "vision"]

    init(definition: SettingDefinition, model: SettingsViewModel) {
        self.definition = definition
        self.model = model
        _entries = State(initialValue: Self.entries(from: definition.value ?? .object([:])))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($entries) { $entry in
                if entry.isUnrecognized {
                    unrecognizedRow(entry: $entry)
                } else {
                    editableRow(entry: $entry)
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
            Text("Remove every role to restore the defaults.")
                .font(TenXTypography.body(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
        }
        .task { await model.loadCatalogIfNeeded() }
        .onChange(of: definition.value) { _, newValue in
            if Self.shouldResync(entries: entries, incoming: newValue) {
                entries = Self.entries(from: newValue ?? .object([:]))
            }
        }
    }

    @ViewBuilder
    private func unrecognizedRow(entry: Binding<ModelRoleEntry>) -> some View {
        HStack(spacing: 8) {
            Text(entry.wrappedValue.role)
                .font(TenXTypography.mono(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
                .frame(width: 70, alignment: .leading)
            Text(entry.wrappedValue.unrecognizedRaw ?? "")
                .font(TenXTypography.mono(size: 11))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .lineLimit(1)
            Text("(unrecognized)")
                .font(TenXTypography.body(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            Spacer()
            removeButton(for: entry.wrappedValue.role)
        }
    }

    @ViewBuilder
    private func editableRow(entry: Binding<ModelRoleEntry>) -> some View {
        HStack(spacing: 8) {
            Text(entry.wrappedValue.role)
                .font(TenXTypography.mono(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
                .frame(width: 70, alignment: .leading)
            InlineDropdown(
                options: Self.modelOptions(from: model.catalogModels),
                current: "\(entry.wrappedValue.value.provider)/\(entry.wrappedValue.value.modelID)",
                accessibilityLabelText: "\(entry.wrappedValue.role) model",
                onSelect: { selection in
                    if let parsed = ModelRoleValue(raw: selection) {
                        entry.wrappedValue.value.provider = parsed.provider
                        entry.wrappedValue.value.modelID = parsed.modelID
                        entry.wrappedValue.value.effort = parsed.effort
                        save()
                    }
                })
            if showsEffortDropdown(for: entry.wrappedValue.value) {
                InlineDropdown(
                    options: effortOptions(for: entry.wrappedValue.value),
                    current: entry.wrappedValue.value.effort ?? "",
                    prompt: "effort",
                    allowsOther: false,
                    accessibilityLabelText: "\(entry.wrappedValue.role) effort",
                    onSelect: { effort in
                        entry.wrappedValue.value.effort = effort.isEmpty ? nil : effort
                        save()
                    })
                .frame(width: 90)
            }
            removeButton(for: entry.wrappedValue.role)
        }
    }

    private func removeButton(for role: String) -> some View {
        Button {
            entries.removeAll { $0.role == role }
            save()
        } label: {
            Image(systemName: "minus")
        }
        .buttonStyle(.plain)
        .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
        .accessibilityLabel("Remove \(role)")
    }

    private func defaultValue(for role: String) -> ModelRoleValue {
        if let d = entries.first(where: { $0.role == "default" })?.value,
           ModelRoleValue(raw: d.raw) != nil {
            return d
        }
        if let first = model.catalogModels.first {
            return ModelRoleValue(provider: first.provider, modelID: first.modelID, effort: nil)
        }
        return ModelRoleValue(provider: "", modelID: "", effort: nil)
    }

    private func showsEffortDropdown(for value: ModelRoleValue) -> Bool {
        Self.showsEffortDropdown(for: value, catalog: model.catalogModels)
    }

    private func effortOptions(for value: ModelRoleValue) -> [SettingOption] {
        Self.effortOptions(for: value, catalog: model.catalogModels)
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

    nonisolated static func shouldResync(entries: [ModelRoleEntry], incoming: JSONValue?) -> Bool {
        let newValue = incoming ?? .object([:])
        return jsonObject(from: entries, preserving: newValue) != newValue
    }

    nonisolated static func entries(from value: JSONValue) -> [ModelRoleEntry] {
        let object = value.objectValue ?? [:]
        return object.compactMap { role, raw -> ModelRoleEntry? in
            guard let string = raw.stringValue else { return nil }
            if let parsed = ModelRoleValue(raw: string) {
                return ModelRoleEntry(role: role, value: parsed)
            }
            return ModelRoleEntry(
                role: role,
                value: ModelRoleValue(provider: "", modelID: "", effort: nil),
                unrecognizedRaw: string)
        }.sorted { a, b in
            let ia = knownRoles.firstIndex(of: a.role) ?? .max
            let ib = knownRoles.firstIndex(of: b.role) ?? .max
            return ia == ib ? a.role < b.role : ia < ib
        }
    }

    /// Serializes edited entries. Invalid drafts are skipped; unrecognized rows
    /// keep their raw string; removed roles (parsed or not) are deleted.
    nonisolated static func jsonObject(from entries: [ModelRoleEntry], preserving original: JSONValue) -> JSONValue {
        var object = original.objectValue ?? [:]
        let currentRoles = Set(entries.map(\.role))

        for entry in entries {
            if entry.isUnrecognized, let raw = entry.unrecognizedRaw {
                object[entry.role] = .string(raw)
            } else if ModelRoleValue(raw: entry.value.raw) != nil {
                object[entry.role] = .string(entry.value.raw)
            }
        }

        for role in object.keys where !currentRoles.contains(role) {
            object[role] = nil
        }

        return .object(object)
    }

    nonisolated static func showsEffortDropdown(for value: ModelRoleValue, catalog: [ComposerModelInfo]) -> Bool {
        value.effort != nil || !effortOptions(for: value, catalog: catalog).isEmpty
    }

    nonisolated static func effortOptions(for value: ModelRoleValue, catalog: [ComposerModelInfo]) -> [SettingOption] {
        if let found = catalog.first(where: {
            $0.provider == value.provider && $0.modelID == value.modelID
        }) {
            return found.thinkingEfforts.map { SettingOption($0) }
        }
        return ModelRoleValue.efforts.map { SettingOption($0) }
    }

    nonisolated static func modelOptions(from models: [ComposerModelInfo]) -> [SettingOption] {
        models.map { SettingOption("\($0.provider)/\($0.modelID)", label: $0.name, detail: $0.provider) }
    }
}
