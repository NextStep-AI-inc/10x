import SwiftUI
import OmpKit

struct InterceptorPatternEntry: Equatable, Identifiable {
    let id: UUID
    var pattern: String
    var tool: String
    var message: String
    var unrecognizedRaw: String?

    var isUnrecognized: Bool { unrecognizedRaw != nil }

    init(
        id: UUID = UUID(),
        pattern: String,
        tool: String,
        message: String,
        unrecognizedRaw: String? = nil
    ) {
        self.id = id
        self.pattern = pattern
        self.tool = tool
        self.message = message
        self.unrecognizedRaw = unrecognizedRaw
    }
}

/// Structured editor for bashInterceptor.patterns, the one array-of-objects setting.
struct ObjectArraySettingEditor: View {
    let definition: SettingDefinition
    let model: SettingsViewModel

    @State private var entries: [InterceptorPatternEntry]

    private static let toolOptions = ["read", "bash", "write", "edit", "grep", "glob"]
        .map { SettingOption($0) }

    init(definition: SettingDefinition, model: SettingsViewModel) {
        self.definition = definition
        self.model = model
        _entries = State(initialValue: Self.interceptorEntries(from: definition.value ?? .array([])))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($entries) { $entry in
                if entry.isUnrecognized {
                    unrecognizedRow(entry: $entry)
                } else {
                    editableCard(entry: $entry)
                }
            }
            Button("Add pattern") {
                entries.append(InterceptorPatternEntry(pattern: "", tool: "read", message: ""))
            }
            .buttonStyle(GhostActionStyle())
        }
        .onChange(of: definition.value) { _, newValue in
            if Self.shouldResync(entries: entries, incoming: newValue) {
                entries = Self.interceptorEntries(from: newValue ?? .array([]))
            }
        }
    }

    @ViewBuilder
    private func unrecognizedRow(entry: Binding<InterceptorPatternEntry>) -> some View {
        HStack(spacing: 8) {
            Text(entry.wrappedValue.unrecognizedRaw ?? "")
                .font(TenXTypography.mono(size: 11))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .lineLimit(1)
            Text("(unrecognized)")
                .font(TenXTypography.body(size: 10))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
            Spacer()
            Button {
                entries.removeAll { $0.id == entry.wrappedValue.id }
                save()
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
            .accessibilityLabel("Remove unrecognized pattern")
        }
        .padding(8)
        .overlay(Rectangle().stroke(TenXPalette.color(TenXPalette.separatorHex)))
    }

    @ViewBuilder
    private func editableCard(entry: Binding<InterceptorPatternEntry>) -> some View {
        VStack(spacing: 4) {
            fieldRow(
                label: "PATTERN",
                text: entry.pattern,
                invalid: !Self.isSaveablePattern(entry.wrappedValue.pattern),
                accessibilityLabel: "Pattern")
            HStack(spacing: 8) {
                Text("TOOL")
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .frame(width: 56, alignment: .leading)
                InlineDropdown(
                    options: Self.toolOptions,
                    current: entry.wrappedValue.tool,
                    accessibilityLabelText: "Tool for pattern \(entry.wrappedValue.pattern)",
                    onSelect: { entry.wrappedValue.tool = $0; save() })
                .frame(width: 140)
                Spacer()
                Button {
                    entries.removeAll { $0.id == entry.wrappedValue.id }
                    save()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
                .accessibilityLabel("Remove pattern")
            }
            fieldRow(
                label: "MESSAGE",
                text: entry.message,
                invalid: false,
                accessibilityLabel: "Message for pattern \(entry.wrappedValue.pattern)")
        }
        .padding(8)
        .overlay(Rectangle().stroke(TenXPalette.color(TenXPalette.separatorHex)))
    }

    private func fieldRow(
        label: String,
        text: Binding<String>,
        invalid: Bool,
        accessibilityLabel: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(TenXTypography.mono(size: 9))
                .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                .frame(width: 56, alignment: .leading)
            TextField(label, text: text)
                .textFieldStyle(.plain)
                .font(TenXTypography.mono(size: 10))
                .padding(.vertical, 3)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(invalid
                              ? TenXPalette.color(TenXPalette.signalRedHex)
                              : TenXPalette.color(TenXPalette.nearBlackHex))
                        .frame(height: 1)
                }
                .accessibilityLabel(accessibilityLabel)
                .onSubmit { save() }
        }
    }

    private func save() {
        guard Self.canSave(entries: entries) else { return }
        let value = Self.jsonArray(from: entries, preserving: definition.value ?? .array([]))
        Task { await model.save(definition, value: value) }
    }

    nonisolated static func shouldResync(entries: [InterceptorPatternEntry], incoming: JSONValue?) -> Bool {
        let newValue = incoming ?? .array([])
        return jsonArray(from: entries, preserving: newValue) != newValue
    }

    nonisolated static func interceptorEntries(from value: JSONValue) -> [InterceptorPatternEntry] {
        (value.arrayValue ?? []).map { item in
            if let object = item.objectValue,
               let pattern = object["pattern"]?.stringValue {
                return InterceptorPatternEntry(
                    pattern: pattern,
                    tool: object["tool"]?.stringValue ?? "read",
                    message: object["message"]?.stringValue ?? "")
            }
            return InterceptorPatternEntry(
                pattern: "",
                tool: "read",
                message: "",
                unrecognizedRaw: jsonText(item))
        }
    }

    nonisolated static func jsonArray(
        from entries: [InterceptorPatternEntry],
        preserving original: JSONValue
    ) -> JSONValue {
        .array(entries.compactMap { entry in
            if entry.isUnrecognized, let raw = entry.unrecognizedRaw {
                return parseJSONText(raw)
            }
            guard isSaveablePattern(entry.pattern) else { return nil }
            return .object([
                "pattern": .string(entry.pattern),
                "tool": .string(entry.tool),
                "message": .string(entry.message),
            ])
        })
    }

    nonisolated static func isValidPattern(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }

    nonisolated static func isSaveablePattern(_ pattern: String) -> Bool {
        !pattern.isEmpty && isValidPattern(pattern)
    }

    nonisolated static func canSave(entries: [InterceptorPatternEntry]) -> Bool {
        entries.allSatisfy { $0.isUnrecognized || isSaveablePattern($0.pattern) }
    }

    nonisolated private static func jsonText(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated private static func parseJSONText(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return nil }
        return decoded
    }
}
