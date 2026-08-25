import Testing
@testable import TenXApp

@Test func headerMetadataIncludesWorktreeWhenPresent() {
    let metadata = SessionHeaderMetadata(
        branch: "codex/gui-v1",
        repo: "10x",
        worktreePath: ".worktrees/gui-v1")

    #expect(metadata.presentationItems.map(\.value) == [
        "codex/gui-v1",
        "10x",
        ".worktrees/gui-v1",
    ])
}

@Test func headerMetadataOmitsMissingWorktree() {
    let metadata = SessionHeaderMetadata(branch: "main", repo: "10x", worktreePath: nil)

    #expect(metadata.presentationItems.map(\.value) == ["main", "10x"])
}

@Test func headerMetadataPresentsEachLocationWithAnIcon() {
    let metadata = SessionHeaderMetadata(
        branch: "codex/active-session-shell",
        repo: "10x",
        worktreePath: ".worktrees/active-session-shell")

    #expect(metadata.presentationItems.map(\.systemImage) == [
        "arrow.triangle.branch",
        "folder",
        "folder.badge.gearshape",
    ])
    #expect(metadata.presentationItems.map(\.value) == [
        "codex/active-session-shell",
        "10x",
        ".worktrees/active-session-shell",
    ])
}
