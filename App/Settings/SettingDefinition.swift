import OmpKit

enum SettingValueType: Equatable {
    case boolean
    case number
    case enumeration
    case string
    case array
    case record
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "boolean": self = .boolean
        case "number": self = .number
        case "enum": self = .enumeration
        case "string": self = .string
        case "array": self = .array
        case "record": self = .record
        default: self = .unknown(rawValue)
        }
    }
}

struct SettingDefinition: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let displayLabel: String
    var value: JSONValue?
    let type: SettingValueType
    let description: String
    let category: SettingsCategory
    let isSecret: Bool
    let requiresRestart: Bool
}

struct SettingsSection: Identifiable, Equatable {
    var id: SettingsCategory { category }
    let category: SettingsCategory
    let definitions: [SettingDefinition]
}
