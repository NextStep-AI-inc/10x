import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func sessionMapPlanningExcerptPrefersCapturedSuccessfulMarkdown() throws {
    let project = try planningDirectory()
    defer { try? FileManager.default.removeItem(at: project) }
    let path = project.appending(path: "PLAN.md")
    try Data("changed on disk".utf8).write(to: path)
    let write = planningTool(
        id: "write-plan",
        name: "write",
        path: path.path,
        content: "# Captured plan\n\n- Build it")

    let result = SessionMapPlanningExcerptReader.read(
        items: [.tool(write)],
        projectURL: project)

    #expect(result.excerpts.count == 1)
    #expect(result.excerpts.first?.text == "# Captured plan\n\n- Build it")
    #expect(result.excerpts.first?.ref == "write-plan")
    #expect(result.diagnostics.isEmpty)
}

@Test func sessionMapPlanningExcerptReadsChangedObservedFile() throws {
    let project = try planningDirectory()
    defer { try? FileManager.default.removeItem(at: project) }
    let path = project.appending(path: "docs/PLAN.md")
    try FileManager.default.createDirectory(
        at: path.deletingLastPathComponent(),
        withIntermediateDirectories: true)
    try Data("before".utf8).write(to: path)
    let edit = planningTool(id: "edit-plan", name: "edit", path: path.path)
    let before = SessionMapPlanningExcerptReader.read(items: [.tool(edit)], projectURL: project)
    try Data("after".utf8).write(to: path)
    let after = SessionMapPlanningExcerptReader.read(items: [.tool(edit)], projectURL: project)

    #expect(before.excerpts.first?.text == "before")
    #expect(after.excerpts.first?.text == "after")
    #expect(before.excerpts.first?.hash != after.excerpts.first?.hash)
}

@Test func sessionMapPlanningExcerptOmitsMissingAndSymlinkEscapes() throws {
    let project = try planningDirectory()
    let outside = try planningDirectory()
    defer {
        try? FileManager.default.removeItem(at: project)
        try? FileManager.default.removeItem(at: outside)
    }
    let missing = project.appending(path: "missing.md")
    let outsideFile = outside.appending(path: "secret.md")
    try Data("outside".utf8).write(to: outsideFile)
    let link = project.appending(path: "linked.md")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideFile)

    let result = SessionMapPlanningExcerptReader.read(items: [
        .tool(planningTool(id: "missing", name: "edit", path: missing.path)),
        .tool(planningTool(id: "escape", name: "edit", path: link.path)),
    ], projectURL: project)

    #expect(result.excerpts.isEmpty)
    #expect(Set(result.diagnostics.map(\.code)) == [
        "planningExcerptUnreadable",
        "planningExcerptOutsideProject",
    ])
}

@Test func sessionMapPlanningExcerptTruncatesMultibyteContentByUTF8Bytes() throws {
    let project = try planningDirectory()
    defer { try? FileManager.default.removeItem(at: project) }
    let path = project.appending(path: "large.md")
    try Data(String(repeating: "🧭", count: 1_000).utf8).write(to: path)
    let result = SessionMapPlanningExcerptReader.read(
        items: [.tool(planningTool(id: "large", name: "edit", path: path.path))],
        projectURL: project)
    let excerpt = try #require(result.excerpts.first)

    #expect(excerpt.text.utf8.count == 2_048)
    #expect(excerpt.text.count == 512)
    #expect(result.diagnostics.map(\.code) == ["planningExcerptTruncated"])
}

@Test func sessionMapPlanningExcerptOmitsInvalidUTF8() throws {
    let project = try planningDirectory()
    defer { try? FileManager.default.removeItem(at: project) }
    let path = project.appending(path: "invalid.md")
    try Data([0xFF, 0xFE]).write(to: path)

    let result = SessionMapPlanningExcerptReader.read(
        items: [.tool(planningTool(id: "invalid", name: "edit", path: path.path))],
        projectURL: project)

    #expect(result.excerpts.isEmpty)
    #expect(result.diagnostics.map(\.code) == ["planningExcerptInvalidUTF8"])
}

private func planningDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func planningTool(
    id: String,
    name: String,
    path: String,
    content: String? = nil
) -> ToolPresentation {
    var arguments: [String: JSONValue] = ["path": .string(path)]
    if let content { arguments["content"] = .string(content) }
    let result: JSONValue = name == "edit"
        ? .object(["details": .object(["diff": .string("@@ -1 +1 @@")])])
        : .object(["output": .string("ok")])
    return ToolPresentation(
        id: id,
        name: name,
        arguments: .object(arguments),
        result: result,
        phase: .complete,
        startDate: .distantPast,
        endDate: .distantPast)
}
