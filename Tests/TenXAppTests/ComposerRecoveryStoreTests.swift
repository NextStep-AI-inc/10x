import Foundation
import Testing
@testable import TenXApp

@Suite @MainActor struct ComposerRecoveryStoreTests {
    @Test func unicodeDraftAndOrderedAttachmentsRoundTripWithoutReencoding() async throws {
        let root = try recoveryTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstID = UUID()
        let secondID = UUID()
        let draft = ComposerRecoveryDraft(
            text: "下書き 👩🏽‍💻 café\nمرحبا",
            attachments: [
                recoveryAttachment(id: firstID, byte: 0x11, name: "一.png"),
                recoveryAttachment(id: secondID, byte: 0x22, name: "two.jpg"),
            ])
        let owner = ComposerRecoveryOwner.session(root.appending(path: "session.jsonl").path)
        let store = ComposerRecoveryStore(rootURL: root, debounce: .milliseconds(5))

        store.setDraft(draft, for: owner)
        await store.flush()
        let restored = ComposerRecoveryStore(rootURL: root, debounce: .milliseconds(5))

        #expect(restored.record(for: owner)?.draft == draft)
        #expect(restored.record(for: owner)?.draft.attachments.map(\.id) == [firstID, secondID])
        #expect(restored.record(for: owner)?.draft.attachments.map(\.data) == [Data([0x11]), Data([0x22])])
        #expect(try permissions(at: root) == 0o700)
        #expect(try permissions(at: root.appending(path: ComposerRecoveryStore.fileName)) == 0o600)
    }

    @Test func canonicalSessionAndProjectRecordsStayIndependentAndCanBeRemoved() async throws {
        let root = try recoveryTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appending(path: "Project", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let alias = root.appending(path: "ProjectAlias", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: project)
        let store = ComposerRecoveryStore(rootURL: root.appending(path: "Recovery"))
        let projectOwner = ComposerRecoveryOwner.project(alias)
        let canonicalProjectOwner = ComposerRecoveryOwner.project(project)
        let sessionOwner = ComposerRecoveryOwner.session(root.appending(path: "session.jsonl").path)

        store.setDraft(ComposerRecoveryDraft(text: "project", attachments: []), for: projectOwner)
        store.setDraft(ComposerRecoveryDraft(text: "session", attachments: []), for: sessionOwner)

        #expect(store.record(for: canonicalProjectOwner)?.draft.text == "project")
        #expect(store.record(for: sessionOwner)?.draft.text == "session")
        store.remove(canonicalProjectOwner)
        #expect(store.record(for: projectOwner) == nil)
        #expect(store.record(for: sessionOwner)?.draft.text == "session")
    }

    @Test func malformedFileFallsBackToEmptyAndReportsATraceableError() throws {
        let root = try recoveryTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a property list".utf8).write(
            to: root.appending(path: ComposerRecoveryStore.fileName))

        let store = ComposerRecoveryStore(rootURL: root)

        #expect(store.allRecords.isEmpty)
        #expect(store.lastMeaningfulRoute == nil)
        #expect(store.errorMessage?.hasPrefix("[ComposerRecoveryStore:load]") == true)
    }

    @Test func invalidAttachmentRecordsAreIgnoredWithinExistingComposerBounds() {
        let store = ComposerRecoveryStore.inMemory()
        let owner = ComposerRecoveryOwner.session("/tmp/recovery-validation.jsonl")
        let valid = (0..<ComposerAttachmentEncoder.maximumCount).map {
            recoveryAttachment(byte: UInt8($0), name: "\($0).png")
        }
        let invalidSize = ComposerAttachment(
            name: "too-large.png",
            data: Data(repeating: 0xFF, count: ComposerAttachmentEncoder.pngBudgetBytes + 1),
            mimeType: "image/png",
            pixelWidth: 10,
            pixelHeight: 10)
        let invalidDimensions = ComposerAttachment(
            name: "empty.png", data: Data([1]), mimeType: "image/png",
            pixelWidth: 0, pixelHeight: 10)

        store.setDraft(
            ComposerRecoveryDraft(
                text: "bounded",
                attachments: valid + [invalidSize, invalidDimensions]),
            for: owner)

        #expect(store.record(for: owner)?.draft.attachments == valid)
    }

    @Test func latestRevisionWinsAcrossDebounceAndExplicitFlush() async throws {
        let root = try recoveryTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = ComposerRecoveryOwner.project(root)
        let store = ComposerRecoveryStore(rootURL: root, debounce: .milliseconds(100))

        store.setDraft(ComposerRecoveryDraft(text: "old", attachments: []), for: owner)
        store.setDraft(ComposerRecoveryDraft(text: "new", attachments: []), for: owner)
        await store.flush()
        try await Task.sleep(for: .milliseconds(150))

        let restored = ComposerRecoveryStore(rootURL: root)
        #expect(restored.record(for: owner)?.draft.text == "new")
    }

    @Test func inFlightInputAndInitialOwnersRemainSeparateFromEditableDraftAndRoute() {
        let store = ComposerRecoveryStore.inMemory()
        let project = URL(filePath: "/tmp/Project", directoryHint: .isDirectory)
        let initialID = UUID()
        let owner = ComposerRecoveryOwner.initial(id: initialID, projectURL: project)
        let current = ComposerRecoveryDraft(text: "newer text", attachments: [])
        let submitted = ComposerRecoveryInFlight(
            id: UUID(),
            draft: ComposerRecoveryDraft(
                text: "submitted", attachments: [recoveryAttachment(byte: 7)]),
            minimumUserIndex: 4)

        store.setDraft(current, for: owner)
        store.setInFlight(submitted, for: owner)
        store.setLastMeaningfulRoute(.newSession(projectURL: project))

        #expect(store.record(for: owner)?.draft == current)
        #expect(store.record(for: owner)?.inFlight == submitted)
        #expect(store.initialRecords(for: project).map(\.owner) == [owner])
        #expect(store.lastMeaningfulRoute == .newSession(projectURL: project))
    }

    @Test func encodedJPEGAboveThePNGChoiceThresholdIsPreserved() async throws {
        let root = try recoveryTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = ComposerRecoveryOwner.session("/tmp/large-jpeg.jsonl")
        let jpeg = ComposerAttachment(
            name: "photo.jpg",
            data: Data(repeating: 0xA5, count: ComposerAttachmentEncoder.pngBudgetBytes + 1),
            mimeType: "image/jpeg",
            pixelWidth: ComposerAttachmentEncoder.maxPixelDimension,
            pixelHeight: ComposerAttachmentEncoder.maxPixelDimension)
        let store = ComposerRecoveryStore(rootURL: root)

        store.setDraft(ComposerRecoveryDraft(text: "photo", attachments: [jpeg]), for: owner)
        await store.flush()

        let restored = ComposerRecoveryStore(rootURL: root)
        #expect(restored.record(for: owner)?.draft.attachments == [jpeg])
    }

    @Test func mergingDistinctFullDraftsNeverDropsOverflowAttachments() {
        let older = ComposerRecoveryDraft(
            text: "older",
            attachments: (0..<ComposerAttachmentEncoder.maximumCount).map {
                recoveryAttachment(byte: UInt8($0), name: "old-\($0).png")
            })
        let newer = ComposerRecoveryDraft(
            text: "newer",
            attachments: (0..<ComposerAttachmentEncoder.maximumCount).map {
                recoveryAttachment(byte: UInt8($0 + 8), name: "new-\($0).png")
            })

        let merged = ComposerRecoveryStore.merged(older, newer)

        #expect(merged.attachments.count == ComposerAttachmentEncoder.maximumCount * 2)
        #expect(merged.attachments.map(\.id) == older.attachments.map(\.id) + newer.attachments.map(\.id))
    }
}

private func recoveryTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "10x-composer-recovery-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func recoveryAttachment(
    id: UUID = UUID(),
    byte: UInt8,
    name: String = "image.png"
) -> ComposerAttachment {
    ComposerAttachment(
        id: id,
        name: name,
        data: Data([byte]),
        mimeType: name.hasSuffix(".jpg") ? "image/jpeg" : "image/png",
        pixelWidth: 1,
        pixelHeight: 1)
}

private func permissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}
