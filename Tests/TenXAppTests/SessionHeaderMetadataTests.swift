import Testing
@testable import TenXApp

@Test func headerMetadataIncludesWorktreeWhenPresent() {
    let metadata = SessionHeaderMetadata(
        branch: "codex/gui-v1",
        repo: "10x",
        worktreePath: ".worktrees/gui-v1")

    #expect(metadata.displayLine == "codex/gui-v1 | 10x | .worktrees/gui-v1")
}

@Test func headerMetadataOmitsMissingWorktree() {
    let metadata = SessionHeaderMetadata(branch: "main", repo: "10x", worktreePath: nil)

    #expect(metadata.displayLine == "main | 10x")
}
