import Foundation
import OmpKit

struct SettingsCatalog: Equatable {
    private(set) var definitions: [SettingDefinition]

    static let empty = SettingsCatalog(definitions: [])

    static func build(from value: JSONValue) -> SettingsCatalog {
        guard let object = value.objectValue else { return .empty }
        let definitions = object.keys.sorted().compactMap { key -> SettingDefinition? in
            guard let source = object[key]?.objectValue else { return nil }
            let isSecret = secretKey(key)
            return SettingDefinition(
                key: key,
                displayLabel: displayLabel(for: key),
                value: isSecret ? nil : source["value"],
                type: SettingValueType(rawValue: source["type"]?.stringValue ?? "unknown"),
                description: source["description"]?.stringValue ?? "",
                category: category(for: key),
                isSecret: isSecret,
                requiresRestart: requiresRestart(key))
        }
        return SettingsCatalog(definitions: definitions)
    }

    func definition(key: String) -> SettingDefinition? {
        definitions.first { $0.key == key }
    }

    func filter(query: String) -> [SettingDefinition] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return definitions }
        return definitions.filter { definition in
            [definition.key, definition.displayLabel, definition.description].contains { value in
                value.range(
                    of: query,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current) != nil
            }
        }
    }

    func sections(query: String = "") -> [SettingsSection] {
        let filtered = filter(query: query)
        return SettingsCategory.allCases.compactMap { category in
            let definitions = filtered.filter { $0.category == category }
            return definitions.isEmpty ? nil : SettingsSection(
                category: category,
                definitions: definitions)
        }
    }

    mutating func update(key: String, value: JSONValue?) {
        guard let index = definitions.firstIndex(where: { $0.key == key }) else { return }
        definitions[index].value = definitions[index].isSecret ? nil : value
    }

    private static func category(for key: String) -> SettingsCategory {
        let rules: [(SettingsCategory, [String])] = [
            (.general, ["setupVersion", "autoResume", "power.", "async.", "ask.", "shellPath"]),
            (.appearance, ["theme", "ui.", "tui.", "autocomplete", "notification", "notify."]),
            (.models, ["model", "models.", "enabledModels", "disabledProviders", "providers.", "thinking"]),
            (.agent, ["advisor.", "prewalk.", "autolearn.", "goal.", "prompt.", "queue.", "steer."]),
            (.tools, ["tools.", "bash.", "read.", "write.", "edit.", "grep.", "glob.", "ast", "lsp.", "browser.", "computer.", "eval.", "web."]),
            (.subagents, ["subagent", "task.", "delegate."]),
            (.memory, ["memory.", "recall.", "retain.", "reflect.", "compaction.", "context."]),
            (.integrations, ["git.", "github.", "mcp.", "extensions", "auth.", "xdg.", "hooks."]),
            (.safety, ["approval", "permission", "sandbox", "security", "secret", "redact"]),
        ]
        for (category, prefixes) in rules where prefixes.contains(where: { key.hasPrefix($0) }) {
            return category
        }
        return .advanced
    }

    private static func displayLabel(for key: String) -> String {
        let spacedCamel = key.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression)
        let words = spacedCamel
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
        return words.map { word in
            guard let first = word.first else { return "" }
            return first.uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    private static func secretKey(_ key: String) -> Bool {
        let value = key.lowercased()
        return ["token", "secret", "password", "apikey", "api_key"].contains {
            value.contains($0)
        }
    }

    private static func requiresRestart(_ key: String) -> Bool {
        key.hasPrefix("providers.") || key.hasPrefix("extensions") || key.hasPrefix("auth.")
    }
}
