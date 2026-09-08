import Testing
@testable import TenXApp

struct ModelRoleValueTests {
    @Test func parsesProviderModelAndEffort() {
        let v = ModelRoleValue(raw: "openai-codex/gpt-5.6-sol:max")
        #expect(v == ModelRoleValue(provider: "openai-codex", modelID: "gpt-5.6-sol", effort: "max"))
        #expect(v?.raw == "openai-codex/gpt-5.6-sol:max")
    }

    @Test func parsesWithoutEffort() {
        let v = ModelRoleValue(raw: "cursor/composer-2.5-fast")
        #expect(v == ModelRoleValue(provider: "cursor", modelID: "composer-2.5-fast", effort: nil))
        #expect(v?.raw == "cursor/composer-2.5-fast")
    }

    @Test func modelIdMayContainSlashes() {
        let v = ModelRoleValue(raw: "openrouter/google/gemini-x:high")
        #expect(v?.provider == "openrouter")
        #expect(v?.modelID == "google/gemini-x")
        #expect(v?.effort == "high")
    }

    @Test func unknownSuffixIsPartOfModelID() {
        let v = ModelRoleValue(raw: "provider/model:turbo")
        #expect(v?.modelID == "model:turbo")
        #expect(v?.effort == nil)
    }

    @Test func rejectsGarbage() {
        #expect(ModelRoleValue(raw: "noslash") == nil)
        #expect(ModelRoleValue(raw: "/model") == nil)
        #expect(ModelRoleValue(raw: "provider/") == nil)
    }
}
