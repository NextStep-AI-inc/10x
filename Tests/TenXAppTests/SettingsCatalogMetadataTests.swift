import OmpKit
import Testing
@testable import TenXApp

struct SettingsCatalogMetadataTests {
    private func entry(type: String = "enum", description: String = "") -> JSONValue {
        .object(["value": .string("x"), "type": .string(type), "description": .string(description)])
    }

    @Test func curatedEnumOptionsAttachToDefinition() {
        let catalog = SettingsCatalog.build(from: .object(["followUpMode": entry()]))
        #expect(catalog.definition(key: "followUpMode")?.enumOptions.map(\.value) == ["all", "one-at-a-time"])
    }

    @Test func uncuratedEnumGetsNoOptions() {
        let catalog = SettingsCatalog.build(from: .object(["some.unknownEnum": entry()]))
        #expect(catalog.definition(key: "some.unknownEnum")?.enumOptions == [])
    }

    @Test func runtimeDescriptionWinsOverCurated() {
        let catalog = SettingsCatalog.build(from: .object(["modelRoles": entry(type: "record", description: "OMP text")]))
        #expect(catalog.definition(key: "modelRoles")?.description == "OMP text")
    }

    @Test
    func curatedDescriptionFillsGap() {
        let catalog = SettingsCatalog.build(from: .object(["modelRoles": entry(type: "record")]))
        #expect(catalog.definition(key: "modelRoles")?.description.isEmpty == false)
    }

    @Test func secretRecordKeepsValue() {
        let catalog = SettingsCatalog.build(from: .object([
            "images.urls.credentials": .object([
                "value": .object(["apiKey": .string("secret-key")]),
                "type": .string("record"),
                "description": .string(""),
            ]),
        ]))
        let definition = catalog.definition(key: "images.urls.credentials")
        #expect(definition?.isSecret == true)
        #expect(definition?.value == .object(["apiKey": .string("secret-key")]))
    }

    @Test func secretStringHidesValue() {
        let catalog = SettingsCatalog.build(from: .object([
            "auth.broker.token": .object([
                "value": .string("do-not-show"),
                "type": .string("string"),
                "description": .string(""),
            ]),
        ]))
        let definition = catalog.definition(key: "auth.broker.token")
        #expect(definition?.isSecret == true)
        #expect(definition?.value == nil)
    }
}
