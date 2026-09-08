import SwiftUI
import OmpKit

/// Reorderable list editor for arrays with a closed value set (cycleOrder,
/// compaction.methodOrder, …) or values fed by the live catalog
/// (enabledModels, disabledProviders, …). ponytail: up/down buttons instead
/// of drag-and-drop; upgrade path is DragGesture if reordering feels cramped.
struct KnownSetArrayEditor: View {
    let definition: SettingDefinition
    let model: SettingsViewModel
    let knownValues: [String]
    var alwaysShowAdd = false

    @State private var items: [String]

    init(
        definition: SettingDefinition,
        model: SettingsViewModel,
        knownValues: [String],
        alwaysShowAdd: Bool = false
    ) {
        self.definition = definition
        self.model = model
        self.knownValues = knownValues
        self.alwaysShowAdd = alwaysShowAdd
        // ponytail: non-string items are dropped from editing; OMP schema is string[] for all
        // known-set and catalog-fed array keys.
        _items = State(initialValue: (definition.value?.arrayValue ?? []).compactMap(\.stringValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 6) {
                    Text(item)
                        .font(TenXTypography.mono(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))
                    Spacer()
                    Button {
                        items = Self.movingUp(items, index: index)
                        save()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(index == 0)
                    .accessibilityLabel("Move \(item) up")
                    Button {
                        items = Self.movingUp(items, index: index + 1)
                        save()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(index == items.count - 1)
                    .accessibilityLabel("Move \(item) down")
                    Button {
                        items.remove(at: index)
                        save()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                    .accessibilityLabel("Remove \(item)")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
            }
            let remaining = Self.remaining(known: knownValues, items: items)
            if !remaining.isEmpty || knownValues.isEmpty || alwaysShowAdd {
                InlineDropdown(
                    options: remaining.map { SettingOption($0) },
                    current: "",
                    prompt: "Add…",
                    allowsOther: true,
                    accessibilityLabelText: "Add to \(definition.displayLabel)",
                    onSelect: { value in
                        let updated = Self.appending(items: items, value: value)
                        guard updated != items else { return }
                        items = updated
                        save()
                    })
            }
        }
        .frame(maxWidth: 290)
        .task { await model.loadCatalogIfNeeded() }
        .onChange(of: definition.value) { _, newValue in
            guard !model.hasPendingWrite(for: definition.key) else { return }
            if Self.shouldResync(items: items, incoming: newValue) {
                items = (newValue?.arrayValue ?? []).compactMap(\.stringValue)
            }
        }
    }

    private func save() {
        Task { await model.save(definition, value: Self.jsonArray(from: items)) }
    }

    nonisolated static func remaining(known: [String], items: [String]) -> [String] {
        known.filter { !items.contains($0) }
    }

    nonisolated static func movingUp(_ items: [String], index: Int) -> [String] {
        var copy = items
        guard copy.indices.contains(index), index > 0 else { return copy }
        copy.swapAt(index, index - 1)
        return copy
    }

    nonisolated static func jsonArray(from items: [String]) -> JSONValue {
        .array(items.map { .string($0) })
    }

    nonisolated static func shouldResync(items: [String], incoming: JSONValue?) -> Bool {
        jsonArray(from: items) != (incoming ?? .array([]))
    }

    nonisolated static func appending(items: [String], value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !items.contains(trimmed) else { return items }
        var copy = items
        copy.append(trimmed)
        return copy
    }

    nonisolated static func modelSelectors(from models: [ComposerModelInfo]) -> [String] {
        models.map { "\($0.provider)/\($0.modelID)" }
    }

    nonisolated static func providerIDs(from models: [ComposerModelInfo]) -> [String] {
        Array(Set(models.map(\.provider))).sorted()
    }

    /// enabledModels → provider/modelID selectors; modelProviderOrder and
    /// disabledProviders → bare provider IDs (OMP rank lookup).
    nonisolated static func catalogValues(for key: String, models: [ComposerModelInfo]) -> [String] {
        switch key {
        case "enabledModels":
            modelSelectors(from: models)
        case "modelProviderOrder", "disabledProviders":
            providerIDs(from: models)
        default:
            []
        }
    }
}
