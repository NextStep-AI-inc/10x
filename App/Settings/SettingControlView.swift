import SwiftUI
import OmpKit

struct SettingControlView: View {
    let definition: SettingDefinition
    let model: SettingsViewModel

    @State private var draftText: String
    @State private var draftItems: [String]

    init(definition: SettingDefinition, model: SettingsViewModel) {
        self.definition = definition
        self.model = model
        _draftText = State(initialValue: Self.textValue(definition.value))
        _draftItems = State(initialValue: Self.arrayValues(definition.value))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            control
            Button {
                Task {
                    guard await model.restoreDefault(definition) else { return }
                    draftText = Self.textValue(definition.defaultValue)
                    draftItems = Self.arrayValues(definition.defaultValue)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.uturn.backward")
                    Text(Self.defaultActionLabel(for: definition))
                        .font(TenXTypography.mono(size: 10))
                }
            }
            .buttonStyle(GhostActionStyle())
            .help("Use default: \(Self.defaultActionLabel(for: definition))")
            .accessibilityLabel(
                "Use default for \(definition.displayLabel): \(Self.defaultActionLabel(for: definition))")
        }
        .onChange(of: definition.value) { _, value in
            draftText = Self.textValue(value)
            draftItems = Self.arrayValues(value)
        }
    }

    @ViewBuilder
    private var control: some View {
        switch definition.type {
        case .boolean:
            Toggle("", isOn: Binding(
                get: { definition.value?.boolValue ?? false },
                set: { value in
                    Task { await model.save(definition, value: .bool(value)) }
                }))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(TenXPalette.color(TenXPalette.cyanHex))
                .accessibilityLabel(definition.displayLabel)
        case .number:
            editableField(prompt: "Number") {
                guard let value = Double(draftText) else { return }
                let json: JSONValue = value == value.rounded()
                    ? .int(Int(value))
                    : .double(value)
                await model.save(definition, value: json)
            }
        case .string, .enumeration, .unknown(_):
            editableField(prompt: definition.isSecret ? "Secure value" : "Value") {
                await model.save(definition, value: .string(draftText))
            }
        case .array:
            arrayEditor
        case .record:
            editableField(prompt: "JSON object") {
                guard let data = draftText.data(using: .utf8),
                      let value = try? JSONDecoder().decode(JSONValue.self, from: data),
                      value.objectValue != nil
                else { return }
                await model.save(definition, value: value)
            }
        }
    }

    private func editableField(
        prompt: String,
        onSave: @escaping () async -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Group {
                if definition.isSecret {
                    SecureField(prompt, text: $draftText)
                } else {
                    TextField(prompt, text: $draftText)
                }
            }
            .textFieldStyle(.plain)
            .font(TenXTypography.mono(size: 11))
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(TenXPalette.color(TenXPalette.nearBlackHex))
                    .frame(height: 1)
            }
            .onSubmit { Task { await onSave() } }

            Button("Apply") { Task { await onSave() } }
                .buttonStyle(GhostActionStyle())
        }
        .frame(maxWidth: 290)
    }

    private var arrayEditor: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(draftItems.indices, id: \.self) { index in
                HStack(spacing: 4) {
                    TextField("Value", text: Binding(
                        get: { draftItems[index] },
                        set: { draftItems[index] = $0 }))
                        .textFieldStyle(.plain)
                        .font(TenXTypography.mono(size: 11))
                        .padding(.vertical, 5)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(TenXPalette.color(TenXPalette.nearBlackHex))
                                .frame(height: 1)
                        }
                        .onSubmit(saveArray)
                    Button {
                        draftItems.remove(at: index)
                        saveArray()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                    .accessibilityLabel("Remove value")
                }
            }
            Button("Add value") {
                draftItems.append("")
            }
            .buttonStyle(GhostActionStyle())
            if !draftItems.isEmpty {
                Button("Apply") { saveArray() }
                    .buttonStyle(GhostActionStyle())
            }
        }
        .frame(maxWidth: 290)
    }

    private func saveArray() {
        let values = draftItems.map(Self.value(from:))
        Task { await model.save(definition, value: .array(values)) }
    }

    private static func textValue(_ value: JSONValue?) -> String {
        guard let value else { return "" }
        if let string = value.stringValue { return string }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func defaultLabel(_ value: JSONValue) -> String {
        value.stringValue == "" ? "\"\"" : textValue(value)
    }

    static func defaultActionLabel(for definition: SettingDefinition) -> String {
        if let value = definition.defaultValue { return defaultLabel(value) }
        return definition.key == "shellPath" ? "System shell" : "Default"
    }

    private static func arrayValues(_ value: JSONValue?) -> [String] {
        value?.arrayValue?.map { textValue($0) } ?? []
    }

    private static func value(from text: String) -> JSONValue {
        guard let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return .string(text) }
        return decoded
    }
}
