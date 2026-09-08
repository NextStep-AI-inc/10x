import OmpKit
import Testing
@testable import TenXApp

@Test func catalogCategorizesDynamicOMPSettingsAndProtectsSecrets() {
    let source: JSONValue = .object([
        "autoResume": setting(
            .bool(false),
            defaultValue: .bool(true),
            type: "boolean",
            description: "Automatically resume"),
        "advisor.enabled": setting(.bool(true), type: "boolean", description: "Pair a reviewer"),
        "providers.openai-codex.codeMode": setting(.string("off"), type: "enum", description: "Codex mode"),
        "auth.broker.token": .object([
            "default": .string("must-not-display"),
            "type": .string("string"),
            "description": .string("Authentication value"),
        ]),
        "unmapped.futureKey": setting(.int(3), type: "number", description: "Future setting"),
    ])

    let catalog = SettingsCatalog.build(from: source)

    #expect(catalog.definition(key: "autoResume")?.category == .general)
    #expect(catalog.definition(key: "autoResume")?.defaultValue == .bool(true))
    #expect(catalog.definition(key: "advisor.enabled")?.category == .agent)
    #expect(catalog.definition(key: "providers.openai-codex.codeMode")?.category == .models)
    #expect(catalog.definition(key: "auth.broker.token")?.category == .integrations)
    #expect(catalog.definition(key: "auth.broker.token")?.isSecret == true)
    #expect(catalog.definition(key: "auth.broker.token")?.value == nil)
    #expect(catalog.definition(key: "auth.broker.token")?.defaultValue == nil)
    #expect(catalog.definition(key: "unmapped.futureKey")?.category == .advanced)
    #expect(catalog.definition(key: "unmapped.futureKey")?.displayLabel == "Unmapped Future Key")
}

@Test func catalogSearchMatchesKeysLabelsAndDescriptions() {
    let source: JSONValue = .object([
        "unmapped.futureKey": setting(.int(3), type: "number", description: "Controls tomorrow"),
        "advisor.enabled": setting(.bool(true), type: "boolean", description: "Pair a reviewer"),
    ])
    let catalog = SettingsCatalog.build(from: source)

    #expect(catalog.filter(query: "futureKey").map(\.key) == ["unmapped.futureKey"])
    #expect(catalog.filter(query: "Future Key").map(\.key) == ["unmapped.futureKey"])
    #expect(catalog.filter(query: "reviewer").map(\.key) == ["advisor.enabled"])
}

@Test func missingOMPDefaultsStillHaveHonestActionLabels() throws {
    let source: JSONValue = .object([
        "shellPath": setting(.string("20"), type: "string", description: ""),
        "autoResume": setting(.bool(true), type: "boolean", description: "Automatically resume"),
    ])
    let catalog = SettingsCatalog.build(from: source)
    let shellPath = try #require(catalog.definition(key: "shellPath"))
    let autoResume = try #require(catalog.definition(key: "autoResume"))

    #expect(SettingControlView.defaultActionLabel(for: shellPath) == "System shell")
    #expect(SettingControlView.defaultActionLabel(for: autoResume) == "Default")
}

private func setting(
    _ value: JSONValue,
    defaultValue: JSONValue? = nil,
    type: String,
    description: String
) -> JSONValue {
    var object: [String: JSONValue] = [
        "value": value,
        "type": .string(type),
        "description": .string(description),
    ]
    object["default"] = defaultValue
    return .object(object)
}
