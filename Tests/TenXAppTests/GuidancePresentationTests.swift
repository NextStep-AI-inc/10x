import Foundation
import OmpKit
import Testing
@testable import TenXApp

@Test func guidanceClassifierBoundsAndLabels() {
    let advisorMessage = JSONValue.object([
        "role": .string("custom"),
        "customType": .string("advisor"),
        "display": .bool(true),
        "content": .string("""
            <advisory severity="blocker" guidance="weigh, don't blindly obey">
            Ignored envelope body.
            </advisory>
            """),
        "details": .object([
            "notes": .array([
                .object([
                    "note": .string("Check the probe window."),
                    "severity": .string("blocker"),
                ]),
            ]),
        ]),
    ])
    let advisor = GuidanceClassifier.classify(id: "advisor-1", message: advisorMessage)
    #expect(advisor?.kind == .advisor)
    #expect(advisor?.preview == "Check the probe window.")

    let fileMentionMessage = JSONValue.object([
        "role": .string("fileMention"),
        "files": .array([
            .object([
                "path": .string("src/Probe.swift"),
                "content": .string("injected file body must stay out of the preview"),
            ]),
        ]),
    ])
    let fileMention = GuidanceClassifier.classify(id: "file-1", message: fileMentionMessage)
    let fileMentionPreview = fileMention?.preview ?? ""
    #expect(fileMention?.kind == .referencedFile)
    #expect(fileMention?.visibility == .always)
    #expect(!fileMentionPreview.contains("injected file body"))

    let largeText = String(repeating: "字", count: 200)
    let developerMessage = JSONValue.object([
        "role": .string("developer"),
        "content": .string(largeText),
    ])
    let developer = GuidanceClassifier.classify(id: "dev-1", message: developerMessage)
    let largePreview = developer?.preview ?? ""
    #expect(Data(largePreview.utf8).count <= 512)
}

@Test func guidanceClassifierAdvisorNotes() {
    let fromNotes = GuidanceClassifier.classify(
        id: "advisor-notes",
        message: .object([
            "role": .string("custom"),
            "customType": .string("advisor"),
            "display": .bool(true),
            "content": .string("<advisory>Envelope only.</advisory>"),
            "details": .object([
                "notes": .array([
                    .object(["note": .string("First note.")]),
                    .object(["note": .string("Second note.")]),
                ]),
            ]),
        ]))
    #expect(fromNotes?.kind == .advisor)
    #expect(fromNotes?.visibility == .whenEnabled)
    #expect(fromNotes?.preview == "First note.\nSecond note.")

    let fromEnvelope = GuidanceClassifier.classify(
        id: "advisor-envelope",
        message: .object([
            "role": .string("custom"),
            "customType": .string("advisor"),
            "display": .bool(true),
            "content": .string("""
                <advisory severity="info" guidance="weigh, don't blindly obey">
                Fallback note text.
                </advisory>
                """),
        ]))
    #expect(fromEnvelope?.kind == .advisor)
    #expect(fromEnvelope?.preview == "Fallback note text.")
}

@Test func guidanceClassifierDeveloperAndHiddenCustomMessages() {
    let developer = GuidanceClassifier.classify(
        id: "developer-wall",
        message: .object([
            "role": .string("developer"),
            "content": .string("Plan approved.\n\n<instruction>\nExecute step by step."),
        ]))
    #expect(developer?.kind == .agentGuidance)
    #expect(developer?.visibility == .whenEnabled)
    #expect(developer?.preview == "Plan approved.\n\n<instruction>\nExecute step by step.")

    let hiddenCustom = GuidanceClassifier.classify(
        id: "hidden-nudge",
        message: .object([
            "role": .string("custom"),
            "customType": .string("prewalk-plan"),
            "display": .bool(false),
            "content": .string("STOP: write a plan before exploring."),
        ]))
    #expect(hiddenCustom?.kind == .agentGuidance)
    #expect(hiddenCustom?.visibility == .whenEnabled)
    #expect(hiddenCustom?.preview == "STOP: write a plan before exploring.")
}

@Test func guidanceClassifierFileMentionReferences() {
    let fileMention = GuidanceClassifier.classify(
        id: "mention-1",
        message: .object([
            "role": .string("fileMention"),
            "files": .array([
                .object([
                    "path": .string("src/Alpha.swift"),
                    "content": .string("alpha body"),
                ]),
                .object([
                    "path": .string("src/Beta.swift"),
                    "content": .string("beta body"),
                ]),
            ]),
        ]))
    #expect(fileMention?.kind == .referencedFile)
    #expect(fileMention?.visibility == .always)
    #expect(fileMention?.preview == "src/Alpha.swift\nsrc/Beta.swift")
    #expect(fileMention?.byteCount == Data("alpha body".utf8).count + Data("beta body".utf8).count)
}

@Test func guidanceClassifierUserAttributedDeveloperFileReferences() {
    let referenced = GuidanceClassifier.classify(
        id: "user-file-dev",
        message: .object([
            "role": .string("developer"),
            "attribution": .string("user"),
            "files": .array([
                .object([
                    "path": .string("docs/plan.md"),
                    "content": .string("injected file body from developer mention"),
                ]),
            ]),
            "content": .string("User prompt with attached file context."),
        ]))
    #expect(referenced?.kind == .referencedFile)
    #expect(referenced?.visibility == .always)
    #expect(referenced?.preview == "docs/plan.md")
    #expect(!(referenced?.preview.contains("injected file body") ?? true))
    #expect(!(referenced?.preview.contains("User prompt") ?? true))
}

@Test func guidanceClassifierEmptyContentReturnsNil() {
    #expect(GuidanceClassifier.classify(
        id: "empty-file-mention",
        message: .object(["role": .string("fileMention")])) == nil)
    #expect(GuidanceClassifier.classify(
        id: "empty-developer",
        message: .object([
            "role": .string("developer"),
            "content": .string(""),
        ])) == nil)
    #expect(GuidanceClassifier.classify(
        id: "conversation-user",
        message: .object([
            "role": .string("user"),
            "content": .string("Hello"),
        ])) == nil)
}

@Test func guidanceClassifierMultibytePreviewBounds() {
    let multiline = (0..<10).map { "line \($0): 日本語" }.joined(separator: "\n")
    let preview = BoundaryText.preview(multiline, byteLimit: 512, lineLimit: 6)
    #expect(preview.components(separatedBy: "\n").count <= 6)
    #expect(Data(preview.utf8).count <= 512)

    let longTitle = String(repeating: "路", count: 100)
    let sanitized = BoundaryText.sanitizeTitle(longTitle)
    #expect(Data(sanitized.utf8).count <= 80)
}

@Test func guidanceClassifierInMemoryUserAttributedDeveloperProjection() {
    let projection = GuidanceClassifier.classify(
        id: "mem-proj",
        message: .object([
            "role": .string("developer"),
            "attribution": .string("user"),
            "content": .string("injected file body must stay out of the preview"),
        ]))
    #expect(projection?.kind == .referencedFile)
    #expect(projection?.visibility == .always)
    #expect(projection?.preview.isEmpty == true)
    #expect(!(projection?.preview.contains("injected file body") ?? true))
}

@Test func guidanceClassifierUsesFileByteSizeWhenContentOmitted() {
    let projection = GuidanceClassifier.classify(
        id: "file-1",
        message: .object([
            "role": .string("fileMention"),
            "files": .array([
                .object([
                    "path": .string("src/Large.swift"),
                    "content": .string(""),
                    "byteSize": .int(48_000),
                ]),
            ]),
        ]))
    #expect(projection?.byteCount == 48_000)
}

@Test func guidanceCardLabelsUseSingularFormsForOne() {
    #expect(GuidanceCardView.sizeLabel(1) == "1 byte")
    #expect(GuidanceCardView.sizeLabel(2) == "2 bytes")
    #expect(GuidanceCardView.sizeLabel(512) == "512 bytes")

    #expect(GuidanceCardView.omissionBody(1) == "1 earlier item omitted")
    #expect(GuidanceCardView.omissionBody(2) == "2 earlier items omitted")

    #expect(GuidanceCardView.accessibilityLabel(for: GuidancePresentation.earlierOmitted(count: 1)) ==
        "Earlier guidance omitted, 1 item")
    #expect(GuidanceCardView.accessibilityLabel(for: GuidancePresentation.earlierOmitted(count: 3)) ==
        "Earlier guidance omitted, 3 items")
}

@Test func guidanceReconcileFingerprintDistinguishesIdenticalPreviews() {
    let shared = String(repeating: "a", count: 513)
    let first = GuidanceClassifier.classify(
        id: "dev-a",
        message: .object([
            "role": .string("developer"),
            "content": .string(shared + "tailA"),
        ]))
    let second = GuidanceClassifier.classify(
        id: "dev-b",
        message: .object([
            "role": .string("developer"),
            "content": .string(shared + "tailB"),
        ]))
    #expect(first?.preview == second?.preview)
    #expect(first?.byteCount == second?.byteCount)
    #expect(first?.reconcileFingerprint != second?.reconcileFingerprint)
}
