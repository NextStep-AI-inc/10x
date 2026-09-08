import SwiftUI
import OmpKit

enum RecordValueKind: Equatable {
    case text
    case policy
    case number
    case model
    case stringList
}

enum RecordSaveValidation: Equatable {
    case ok(JSONValue)
    case duplicateKeys
    case invalidNumber
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
    private enum FocusedField: Hashable {
        case key(UUID)
        case value(UUID)
    }

    let definition: SettingDefinition
    let model: SettingsViewModel
    let valueKind: RecordValueKind

    @State private var entries: [RecordEntry]
    @State private var localError: String?
    @FocusState private var focusedField: FocusedField?

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
                    TextField("Key", text: $entry.key)
                        .textFieldStyle(.plain)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.interactiveCyanHex))
                        .padding(.vertical, 5)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(TenXPalette.color(TenXPalette.nearBlackHex)).frame(height: 1)
                        }
                        .frame(width: 110, alignment: .leading)
                        .focused($focusedField, equals: .key(entry.id))
                        .onSubmit { save() }
                        .accessibilityLabel("Entry key")
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
                entries.append(RecordEntry(key: "", value: ""))
            }
            .buttonStyle(GhostActionStyle())
            if let localError {
                Text(localError)
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
            }
        }
        .task { await model.loadCatalogIfNeeded() }
        .onChange(of: focusedField) { oldFocus, _ in
            guard oldFocus != nil else { return }
            save()
        }
        .onChange(of: definition.value) { _, newValue in
            guard !model.hasPendingWrite(for: definition.key) else { return }
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
                .focused($focusedField, equals: .value(entry.wrappedValue.id))
                .onSubmit { save() }
                .accessibilityLabel(
                    entry.wrappedValue.key.isEmpty
                        ? "Entry value"
                        : "\(entry.wrappedValue.key) value")
        }
    }

    private func save() {
        switch Self.validateSave(entries: entries, kind: valueKind) {
        case .ok(let object):
            localError = nil
            Task { await model.save(definition, value: object) }
        case .duplicateKeys:
            localError = "Each key must be unique."
        case .invalidNumber:
            localError = "Enter a valid number."
        }
    }

    nonisolated static func validateSave(entries: [RecordEntry], kind: RecordValueKind) -> RecordSaveValidation {
        var seenKeys = Set<String>()
        for entry in entries {
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            guard seenKeys.insert(key).inserted else { return .duplicateKeys }

            let trimmedValue = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else { continue }
            if kind == .number, numberJSON(from: trimmedValue) == nil {
                return .invalidNumber
            }
        }
        return .ok(jsonObject(from: entries, kind: kind))
    }

    nonisolated static func shouldResync(entries: [RecordEntry], incoming: JSONValue?, kind: RecordValueKind) -> Bool {
        let newValue = incoming ?? .object([:])
        if kind == .number {
            return !numericValuesMatch(entries: entries, incoming: newValue)
        }
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

    /// Rebuilds the record object from edited rows. Empty keys and whitespace-only
    /// values are omitted so placeholder rows and cleared fields restore OMP defaults.
    nonisolated static func jsonObject(from entries: [RecordEntry], kind: RecordValueKind) -> JSONValue {
        var object: [String: JSONValue] = [:]
        for entry in entries {
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            let trimmedValue = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else { continue }
            switch kind {
            case .number:
                if let json = numberJSON(from: trimmedValue) {
                    object[key] = json
                }
            case .stringList:
                object[key] = .array(
                    trimmedValue.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .map(JSONValue.string))
            case .text, .policy, .model:
                object[key] = .string(trimmedValue)
            }
        }
        return .object(object)
    }

    nonisolated private static func numericValuesMatch(entries: [RecordEntry], incoming: JSONValue) -> Bool {
        let serialized = jsonObject(from: entries, kind: .number).objectValue ?? [:]
        let incomingObject = incoming.objectValue ?? [:]
        let allKeys = Set(serialized.keys).union(incomingObject.keys)
        for key in allKeys {
            let left = serialized[key].flatMap(numericDouble)
            let right = incomingObject[key].flatMap(numericDouble)
            if left != right { return false }
        }
        return true
    }

    nonisolated private static func numericDouble(from value: JSONValue) -> Double? {
        switch value {
        case .int(let i): Double(i)
        case .double(let d): d
        case .string(let s): Double(s)
        default: nil
        }
    }

    nonisolated private static func numberJSON(from text: String) -> JSONValue? {
        guard let number = Double(text), number.isFinite else { return nil }
        if number == number.rounded(), number.magnitude < Double(Int.max) {
            return .int(Int(number))
        }
        if number == number.rounded() { return nil }
        return .double(number)
    }

    nonisolated private static func rawValueText(from raw: JSONValue) -> String {
        if let int = raw.intValue { return String(int) }
        if let double = raw.doubleValue { return String(double) }
        return raw.stringValue ?? ""
    }
}
