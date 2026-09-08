import SwiftUI
import OmpKit

struct InterceptorPatternEntry: Equatable, Identifiable {
    let id: UUID
    var pattern: String
    var tool: String
    var message: String
    var sourceObject: [String: JSONValue]?
    var unrecognizedRaw: String?

    var isUnrecognized: Bool { unrecognizedRaw != nil }

    init(
        id: UUID = UUID(),
        pattern: String,
        tool: String,
        message: String,
        sourceObject: [String: JSONValue]? = nil,
        unrecognizedRaw: String? = nil
    ) {
        self.id = id
        self.pattern = pattern
        self.tool = tool
        self.message = message
        self.sourceObject = sourceObject
        self.unrecognizedRaw = unrecognizedRaw
    }
}

/// Structured editor for bashInterceptor.patterns, the one array-of-objects setting.
struct ObjectArraySettingEditor: View {
    private enum FocusedField: Hashable {
        case pattern(UUID)
        case message(UUID)
    }

    let definition: SettingDefinition
    let model: SettingsViewModel

    @State private var entries: [InterceptorPatternEntry]
    @State private var localError: String?
    @FocusState private var focusedField: FocusedField?

    private static let toolOptions = ["read", "bash", "write", "edit", "grep", "glob", "hub"]
        .map { SettingOption($0) }

    init(definition: SettingDefinition, model: SettingsViewModel) {
        self.definition = definition
        self.model = model
        _entries = State(initialValue: Self.interceptorEntries(from: definition.value ?? .array([])))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if entry.isUnrecognized {
                    unrecognizedRow(entry: binding(for: entry), rowIndex: index)
                } else {
                    editableCard(entry: binding(for: entry), rowIndex: index)
                }
            }
            Button("Add pattern") {
                entries.append(InterceptorPatternEntry(pattern: "", tool: "bash", message: ""))
            }
            .buttonStyle(GhostActionStyle())
            if let localError {
                Text(localError)
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.signalRedHex))
            }
        }
        .onChange(of: focusedField) { oldFocus, _ in
            guard oldFocus != nil else { return }
            save()
        }
        .onChange(of: definition.value) { _, newValue in
            if model.isOwnEcho(for: definition.key, value: newValue) { return }
            guard !model.hasPendingWrite(for: definition.key) else { return }
            if Self.shouldResync(entries: entries, incoming: newValue) {
                entries = Self.interceptorEntries(from: newValue ?? .array([]))
            }
        }
    }

    private func binding(for entry: InterceptorPatternEntry) -> Binding<InterceptorPatternEntry> {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return .constant(entry)
        }
        return $entries[index]
    }

    private func rowLabel(index: Int, pattern: String) -> String {
        pattern.isEmpty ? "row \(index + 1)" : pattern
    }

    @ViewBuilder
    private func unrecognizedRow(entry: Binding<InterceptorPatternEntry>, rowIndex: Int) -> some View {
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
            .accessibilityLabel("Remove unrecognized pattern \(rowIndex + 1)")
        }
        .padding(8)
        .overlay(Rectangle().stroke(TenXPalette.color(TenXPalette.separatorHex)))
    }

    @ViewBuilder
    private func editableCard(entry: Binding<InterceptorPatternEntry>, rowIndex: Int) -> some View {
        let label = rowLabel(index: rowIndex, pattern: entry.wrappedValue.pattern)
        VStack(spacing: 4) {
            fieldRow(
                label: "PATTERN",
                text: entry.pattern,
                invalid: !Self.isSaveablePattern(entry.wrappedValue.pattern),
                accessibilityLabel: "Pattern for \(label)",
                focus: .pattern(entry.wrappedValue.id))
            HStack(spacing: 8) {
                Text("TOOL")
                    .font(TenXTypography.mono(size: 9))
                    .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    .frame(width: 56, alignment: .leading)
                InlineDropdown(
                    options: Self.toolOptions,
                    current: entry.wrappedValue.tool,
                    prompt: "tool",
                    accessibilityLabelText: "Tool for pattern \(label)",
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
                .accessibilityLabel("Remove pattern \(rowIndex + 1)")
            }
            fieldRow(
                label: "MESSAGE",
                text: entry.message,
                invalid: false,
                accessibilityLabel: "Message for \(label)",
                focus: .message(entry.wrappedValue.id))
        }
        .padding(8)
        .overlay(Rectangle().stroke(TenXPalette.color(TenXPalette.separatorHex)))
    }

    private func fieldRow(
        label: String,
        text: Binding<String>,
        invalid: Bool,
        accessibilityLabel: String,
        focus: FocusedField
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
                .focused($focusedField, equals: focus)
                .onSubmit { save() }
        }
    }

    private func save() {
        guard Self.canSave(entries: entries) else {
            localError = "Enter a valid pattern before saving."
            return
        }
        localError = nil
        let value = Self.jsonArray(from: entries)
        Task { await model.save(definition, value: value) }
    }

    nonisolated static func shouldResync(entries: [InterceptorPatternEntry], incoming: JSONValue?) -> Bool {
        let newValue = incoming ?? .array([])
        return jsonArray(from: entries) != newValue
    }

    nonisolated static func interceptorEntries(from value: JSONValue) -> [InterceptorPatternEntry] {
        (value.arrayValue ?? []).map { item in
            if let object = item.objectValue,
               let pattern = object["pattern"]?.stringValue {
                return InterceptorPatternEntry(
                    pattern: pattern,
                    tool: object["tool"]?.stringValue ?? "",
                    message: object["message"]?.stringValue ?? "",
                    sourceObject: object)
            }
            return InterceptorPatternEntry(
                pattern: "",
                tool: "",
                message: "",
                unrecognizedRaw: jsonText(item))
        }
    }

    nonisolated static func jsonArray(from entries: [InterceptorPatternEntry]) -> JSONValue {
        .array(entries.compactMap { entry in
            if entry.isUnrecognized, let raw = entry.unrecognizedRaw {
                return parseJSONText(raw)
            }
            guard isSaveablePattern(entry.pattern) else { return nil }
            var object = entry.sourceObject ?? [:]
            object["pattern"] = .string(entry.pattern)
            if !entry.tool.isEmpty {
                object["tool"] = .string(entry.tool)
            }
            if !entry.message.isEmpty || entry.sourceObject?["message"] != nil {
                object["message"] = .string(entry.message)
            }
            return .object(object)
        })
    }

    // ponytail: ICU approximation of OMP's JS RegExp(pattern, flags); a pattern
    // valid in JS but not ICU can't be saved from this editor (use the CLI).
    // Shipped defaults (lookbehind etc.) validate in both.
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
