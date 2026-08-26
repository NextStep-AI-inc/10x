import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func storeUpdatesOnlyModelRolesDefaultKey() async throws {
    let runner = RecordingConfigRunner(initialListJSON: """
    {"modelRoles":{"value":{"default":"cursor/old","commit":"cursor/c"},"type":"object"}}
    """)
    let store = OmpComposerDefaultStore(config: OmpConfigService(runner: runner))
    try await store.setDefaultModel(provider: "anthropic", modelID: "claude-opus-4-8")
    #expect(await runner.lastSetKey == "modelRoles")
    #expect(await runner.lastSetValueContainsDefault == "anthropic/claude-opus-4-8")
    #expect(await runner.lastSetValueContainsCommit == "cursor/c")
}

@Test func storePersistsDefaultThinkingLevel() async throws {
    let runner = RecordingConfigRunner(initialListJSON: "{}")
    let store = OmpComposerDefaultStore(config: OmpConfigService(runner: runner))
    try await store.setDefaultThinkingLevel("high")
    #expect(await runner.lastSetKey == "defaultThinkingLevel")
    #expect(await runner.lastSetValue == "high")
}

@Test func storeFailsClosedWhenModelRolesValueIsNotObject() async {
    let runner = RecordingConfigRunner(initialListJSON: """
    {"modelRoles":{"value":"anthropic/claude-opus-4-8","type":"string"}}
    """)
    let store = OmpComposerDefaultStore(config: OmpConfigService(runner: runner))
    await #expect(throws: OmpComposerDefaultStoreError.malformedModelRoles) {
        try await store.setDefaultModel(provider: "anthropic", modelID: "claude-sonnet-4-5")
    }
    #expect(await runner.lastSetKey == nil)
}

private actor RecordingConfigRunner: OmpConfigRunning {
    private let initialListJSON: String
    private(set) var lastSetKey: String?
    private(set) var lastSetValue: String?

    init(initialListJSON: String) {
        self.initialListJSON = initialListJSON
    }

    var lastSetValueContainsDefault: String? {
        guard let lastSetValue,
              let data = lastSetValue.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              let object = value.objectValue else { return nil }
        return object["default"]?.stringValue
    }

    var lastSetValueContainsCommit: String? {
        guard let lastSetValue,
              let data = lastSetValue.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              let object = value.objectValue else { return nil }
        return object["commit"]?.stringValue
    }

    func run(arguments: [String]) async throws -> Data {
        if arguments == ["config", "list", "--json"] {
            return Data(initialListJSON.utf8)
        }
        if arguments.first == "config", arguments.count >= 4, arguments[1] == "set" {
            lastSetKey = arguments[2]
            lastSetValue = arguments[3]
        }
        return Data()
    }
}
