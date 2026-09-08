import Testing
@testable import TenXApp

@Test func sessionMapModelRoleUsesQualifiedCatalogID() {
    let catalog = [
        model("shared", provider: "first", efforts: ["low"]),
        model("shared", provider: "second", efforts: ["high"]),
    ]

    let resolved = SessionMapModelResolver.resolve(
        selection: .role("writer"),
        catalog: catalog,
        roles: ["writer": "second/shared:high"])

    #expect(resolved == SessionMapResolvedModel(
        provider: "second", modelID: "shared", effort: "high", acceptsImages: true))
}

@Test func sessionMapModelResolverRejectsMissingRolesAndUnsupportedEffort() {
    let catalog = [model("writer:v2", provider: "first", efforts: ["low"])]

    #expect(SessionMapModelResolver.resolve(
        selection: .role("missing"), catalog: catalog, roles: [:]) == nil)
    #expect(SessionMapModelResolver.resolve(
        selection: .model(id: "first/writer:v2", effort: "high"),
        catalog: catalog,
        roles: [:]) == nil)
    #expect(SessionMapModelResolver.resolve(
        selection: .role("writer"),
        catalog: catalog,
        roles: ["writer": "first/writer:v2"])?.modelID == "writer:v2")
}

private func model(
    _ id: String,
    provider: String,
    efforts: [String],
    acceptsImages: Bool = true
) -> ComposerModelInfo {
    ComposerModelInfo(
        modelID: id,
        name: id,
        provider: provider,
        api: nil,
        thinkingEfforts: efforts,
        requiresEffort: false,
        acceptsImages: acceptsImages)
}
