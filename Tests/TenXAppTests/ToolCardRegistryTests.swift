import Testing
@testable import TenXApp

@Test func registryExplicitlyRoutesEveryCanonicalOMPTool() {
    let canonical = [
        "read", "bash", "edit", "ast_grep", "ast_edit", "ask", "debug", "eval",
        "github", "glob", "grep", "lsp", "inspect_image", "browser", "computer",
        "checkpoint", "rewind", "security_scan", "task", "hub", "todo", "web_search",
        "write", "memory_edit", "retain", "recall", "reflect", "learn", "manage_skill",
        "yield", "goal", "think",
    ]

    #expect(canonical.count == 32)
    #expect(canonical.allSatisfy { ToolCardRegistry.kind(for: $0).isExplicit })
}

@Test func registryRoutesAliasesAdaptersAndOpenEndedTools() {
    #expect(ToolCardRegistry.kind(for: "search") == .grep)
    #expect(ToolCardRegistry.kind(for: "find") == .glob)
    #expect(ToolCardRegistry.kind(for: "apply_patch") == .edit)
    #expect(ToolCardRegistry.kind(for: "resolve") == .resolution(.resolve))
    #expect(ToolCardRegistry.kind(for: "reject") == .resolution(.reject))
    #expect(ToolCardRegistry.kind(for: "propose") == .resolution(.propose))
    #expect(ToolCardRegistry.kind(for: "vibe_wait") == .vibe(.wait))
    #expect(ToolCardRegistry.kind(for: "mcp__figma_render") == .mcp(
        server: "figma",
        tool: "render"))
    #expect(ToolCardRegistry.kind(for: "future_tool") == .custom(name: "future_tool"))
}

@Test func registryNormalizesKnownNamesWithoutRenamingExtensions() {
    #expect(ToolCardRegistry.kind(for: "READ") == .read)
    #expect(ToolCardRegistry.kind(for: "Search") == .grep)
    #expect(ToolCardRegistry.kind(for: "Future_Tool") == .custom(name: "Future_Tool"))
    #expect(ToolCardRegistry.kind(for: "mcp__Figma_Render") == .mcp(
        server: "Figma",
        tool: "Render"))
}
