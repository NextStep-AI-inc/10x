import SwiftUI
import OmpKit

enum RecordValueKind: Equatable {
    case text
    case policy
    case number
    case model
    case stringList
}

struct RecordEntry: Equatable, Identifiable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key && lhs.value == rhs.value
    }
}

struct RecordSettingEditor: View {
    let definition: SettingDefinition
    let model: SettingsViewModel
    let valueKind: RecordValueKind

    @State private var entries: [RecordEntry]

    init(definition: SettingDefinition, model: SettingsViewModel, valueKind: RecordValueKind) {
        self.definition = definition
        self.model = model
        self.valueKind = valueKind
        _entries = State(initialValue: Self.entries(from: definition.value ?? .object([:]), kind: valueKind))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($entries) { $entry in
                HStack(spacing: 8) {
                    Text(entry.key)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
                        .frame(width: 110, alignment: .leading)
                    valueControl(for: $entry)
                    Button {
                        entries.removeAll { $0.id == entry.id }
                        save()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                    .accessibilityLabel("Remove \(entry.key)")
                }
            }
            Button("Add entry") {
                entries.append(RecordEntry(key: nextPlaceholderKey(), value: ""))
            }
            .buttonStyle(GhostActionStyle())
        }
        .task { await model.loadCatalogIfNeeded() }
        .onChange(of: definition.value) { _, newValue in
            if Self.shouldResync(entries: entries, incoming: newValue, kind: valueKind) {
                entries = Self.entries(from: newValue ?? .object([:]), kind: valueKind)
            }
        }
    }

    @ViewBuilder
    private func valueControl(for entry: Binding<RecordEntry>) -> some View {
        switch valueKind {
        case .policy:
            InlineDropdown(
                options: [SettingOption("allow"), SettingOption("prompt"), SettingOption("deny")],
                current: entry.wrappedValue.value,
                allowsOther: false,
                accessibilityLabelText: "\(entry.wrappedValue.key) policy",
                onSelect: { entry.wrappedValue.value = $0; save() })
            .frame(width: 130)
        case .model:
            InlineDropdown(
                options: ModelRolesEditor.modelOptions(from: model.catalogModels),
                current: entry.wrappedValue.value,
                accessibilityLabelText: "\(entry.wrappedValue.key) model",
                onSelect: { entry.wrappedValue.value = $0; save() })
        case .number, .text, .stringList:
            TextField(valueKind == .stringList ? "a, b, c" : "Value", text: entry.projectedValue.value)
                .textFieldStyle(.plain)
                .font(TenXTypography.mono(size: 11))
                .padding(.vertical, 5)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(TenXPalette.color(TenXPalette.nearBlackHex)).frame(height: 1)
                }
                .onSubmit { save() }
        }
    }

    private func nextPlaceholderKey() -> String {
        if !entries.contains(where: { $0.key == "key" }) { return "key" }
        var n = 2
        while entries.contains(where: { $0.key == "key-\(n)" }) { n += 1 }
        return "key-\(n)"
    }

    private func save() {
        let object = Self.jsonObject(from: entries, kind: valueKind)
        Task { await model.save(definition, value: object) }
    }

    nonisolated static func shouldResync(entries: [RecordEntry], incoming: JSONValue?, kind: RecordValueKind) -> Bool {
        let newValue = incoming ?? .object([:])
        return jsonObject(from: entries, kind: kind) != newValue
    }

    nonisolated static func valueKind(for key: String) -> RecordValueKind {
        switch key {
        case "tools.approval": .policy
        case "providers.maxInFlightRequests": .number
        case "task.agentModelOverrides": .model
        case "retry.fallbackChains": .stringList
        default: .text
        }
    }

    nonisolated static func entries(from value: JSONValue, kind: RecordValueKind) -> [RecordEntry] {
        (value.objectValue ?? [:]).sorted { $0.key < $1.key }.map { key, raw in
            switch kind {
            case .stringList:
                RecordEntry(key: key, value: (raw.arrayValue ?? []).compactMap(\.stringValue).joined(separator: ", "))
            case .number:
                RecordEntry(key: key, value: rawValueText(from: raw))
            default:
                RecordEntry(key: key, value: raw.stringValue ?? "")
            }
        }
    }

    nonisolated static func jsonObject(from entries: [RecordEntry], kind: RecordValueKind) -> JSONValue {
        var object: [String: JSONValue] = [:]
        for entry in entries where !entry.key.isEmpty {
            switch kind {
            case .number:
                if let number = Double(entry.value) {
                    object[entry.key] = number == number.rounded() ? .int(Int(number)) : .double(number)
                }
            case .stringList:
                object[entry.key] = .array(
                    entry.value.split(separator: ",").map {
                        .string($0.trimmingCharacters(in: .whitespaces))
                    })
            case .text, .policy, .model:
                object[entry.key] = .string(entry.value)
            }
        }
        return .object(object)
    }

    nonisolated private static func rawValueText(from raw: JSONValue) -> String {
        if let int = raw.intValue { return String(int) }
        if let double = raw.doubleValue { return String(double) }
        return raw.stringValue ?? ""
    }
}
