import CryptoKit
import Foundation
import OmpKit

typealias SessionMapWriterCompletion = @Sendable (
    _ prompt: String,
    _ images: [PromptImage],
    _ model: SessionMapResolvedModel
) async throws -> String

struct SessionMapGenerationInput: Sendable {
    let sessionKey: String
    let lineage: String
    let revision: UInt64
    let digest: SessionMapDigest
    let priorRecord: SessionMapRecord?
    let scope: SessionMapGenerationScope
    let model: SessionMapResolvedModel
    let projectURL: URL
    let force: Bool

    init(
        sessionKey: String,
        lineage: String,
        revision: UInt64,
        digest: SessionMapDigest,
        priorRecord: SessionMapRecord?,
        scope: SessionMapGenerationScope,
        model: SessionMapResolvedModel,
        projectURL: URL,
        force: Bool = false
    ) {
        self.sessionKey = sessionKey
        self.lineage = lineage
        self.revision = revision
        self.digest = digest
        self.priorRecord = priorRecord
        self.scope = scope
        self.model = model
        self.projectURL = projectURL
        self.force = force
    }
}

enum SessionMapGenerationDisposition: Equatable, Sendable {
    case cached
    case generated
    case retainedLastGood
    case factsFallback
    case obsolete
}

struct SessionMapGenerationResult: Sendable {
    let document: SessionMapDocument?
    let xml: String?
    let diagnostics: [SessionMapDiagnostic]
    let record: SessionMapRecord?
    let disposition: SessionMapGenerationDisposition
    let generatedThrough: SessionMapCursor
    let sourceManifest: [String: String]
    let checkOutcome: SessionMapCheckOutcome
}

actor SessionMapGenerator {
    private struct RequestToken: Equatable {
        let lineage: String
        let revision: UInt64
        let digestHash: String
        let writer: SessionMapResolvedModel
        let sourceManifest: [String: String]
    }

    private let completion: SessionMapWriterCompletion
    private let now: @Sendable () -> Date
    private var latestRequests: [String: RequestToken] = [:]

    init(
        completion: @escaping SessionMapWriterCompletion,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.completion = completion
        self.now = now
    }

    func generate(_ input: SessionMapGenerationInput) async -> SessionMapGenerationResult {
        let token = RequestToken(
            lineage: input.lineage,
            revision: input.revision,
            digestHash: input.digest.hash,
            writer: input.model,
            sourceManifest: input.digest.sourceFingerprintManifest)
        if let latest = latestRequests[input.sessionKey],
           latest.lineage == input.lineage,
           latest.revision > input.revision
        {
            return obsolete(input: input, priorDocument: nil, priorXML: nil)
        }
        latestRequests[input.sessionKey] = token

        let context = SessionMapValidationContext(
            knownRefs: input.digest.knownRefs,
            facts: input.digest.facts,
            previous: nil,
            projectURL: input.projectURL,
            statusEvidence: input.digest.statusEvidence)
        let priorValidation = input.priorRecord.map {
            SessionMapDocumentParser.parse(Data($0.xml.utf8), context: context)
        }
        let priorDocument = priorValidation?.document
        let priorXML = priorDocument.map {
            SessionMapXMLSerializer.serialize($0, facts: input.digest.facts)
        }
        let expectedCacheKey = cacheKey(input: input, priorXML: priorXML)

        if !input.force,
           let record = input.priorRecord,
           let priorDocument,
           record.cacheKey == expectedCacheKey
        {
            return result(
                document: priorDocument,
                xml: priorXML,
                diagnostics: priorValidation?.warnings ?? [],
                record: record,
                disposition: .cached,
                input: input)
        }

        let validationContext = SessionMapValidationContext(
            knownRefs: input.digest.knownRefs,
            facts: input.digest.facts,
            previous: priorDocument,
            projectURL: input.projectURL,
            statusEvidence: input.digest.statusEvidence)
        var diagnostics = (priorValidation?.warnings ?? []) + (priorValidation?.fatal ?? [])
        do {
            let candidate = try await completion(
                SessionMapPrompt.writer(digest: input.digest, previousXML: priorXML),
                [],
                input.model)
            guard isCurrent(token, for: input.sessionKey) else {
                return obsolete(input: input, priorDocument: priorDocument, priorXML: priorXML)
            }
            var validation = validateCandidate(candidate, context: validationContext)
            diagnostics += validation.warnings + validation.fatal
            if validation.document == nil || !validation.fatal.isEmpty {
                let repaired = try await completion(
                    SessionMapPrompt.repair(
                        digest: input.digest,
                        previousXML: priorXML,
                        rejectedXML: candidate,
                        diagnostics: validation.fatal),
                    [],
                    input.model)
                guard isCurrent(token, for: input.sessionKey) else {
                    return obsolete(input: input, priorDocument: priorDocument, priorXML: priorXML)
                }
                validation = validateCandidate(repaired, context: validationContext)
                diagnostics += validation.warnings + validation.fatal
            }
            guard let document = validation.document, validation.fatal.isEmpty else {
                return fallback(
                    input: input,
                    priorDocument: priorDocument,
                    priorXML: priorXML,
                    diagnostics: diagnostics)
            }
            let xml = SessionMapXMLSerializer.serialize(document, facts: input.digest.facts)
            let record = makeRecord(document: document, xml: xml, input: input)
            return result(
                document: document,
                xml: xml,
                diagnostics: diagnostics,
                record: record,
                disposition: .generated,
                input: input)
        } catch is CancellationError {
            return obsolete(input: input, priorDocument: priorDocument, priorXML: priorXML)
        } catch {
            guard isCurrent(token, for: input.sessionKey) else {
                return obsolete(input: input, priorDocument: priorDocument, priorXML: priorXML)
            }
            diagnostics.append(SessionMapDiagnostic(
                code: "writer-failure",
                elementID: nil,
                detail: "[SessionMap:SessionMapGenerator.generate] The map writer failed."))
            return fallback(
                input: input,
                priorDocument: priorDocument,
                priorXML: priorXML,
                diagnostics: diagnostics)
        }
    }

    func invalidate(sessionKey: String, lineage: String, revision: UInt64) {
        guard latestRequests[sessionKey]?.revision ?? 0 <= revision else { return }
        latestRequests[sessionKey] = RequestToken(
            lineage: lineage,
            revision: revision,
            digestHash: "invalidated",
            writer: SessionMapResolvedModel(
                provider: "", modelID: "", effort: nil, acceptsImages: false),
            sourceManifest: [:])
    }

    private func makeRecord(
        document: SessionMapDocument,
        xml: String,
        input: SessionMapGenerationInput
    ) -> SessionMapRecord {
        let prior = input.priorRecord
        let previousOrder = prior?.firstSeenOrder ?? []
        let previousIDs = Set(previousOrder)
        let firstSeenOrder = previousOrder
            + document.graph.nodes.map(\.id).filter { !previousIDs.contains($0) }
        return SessionMapRecord(
            xml: xml,
            cacheKey: cacheKey(input: input, priorXML: xml),
            generatedThrough: input.digest.cursor,
            sourceManifest: input.digest.sourceFingerprintManifest,
            caughtUpAt: prior?.caughtUpAt,
            caughtUpCursor: prior?.caughtUpCursor,
            caughtUpGraph: prior?.caughtUpGraph,
            firstSeenOrder: firstSeenOrder,
            updatedAt: now(),
            writerConfiguration: input.model,
            checkerConfiguration: prior?.checkerConfiguration,
            checkOutcome: .off,
            dismissedThrough: prior?.dismissedThrough)
    }

    private func fallback(
        input: SessionMapGenerationInput,
        priorDocument: SessionMapDocument?,
        priorXML: String?,
        diagnostics: [SessionMapDiagnostic]
    ) -> SessionMapGenerationResult {
        if let priorDocument, let priorXML {
            return result(
                document: priorDocument,
                xml: priorXML,
                diagnostics: diagnostics,
                record: input.priorRecord,
                disposition: .retainedLastGood,
                input: input)
        }
        let document = factsFallback(input.digest.facts)
        return result(
            document: document,
            xml: SessionMapXMLSerializer.serialize(document, facts: input.digest.facts),
            diagnostics: diagnostics,
            record: nil,
            disposition: .factsFallback,
            input: input)
    }

    private func factsFallback(_ facts: [String: SessionMapFact]) -> SessionMapDocument {
        let preferred = ["finishedTurns", "sourceEntries", "failedTools", "pendingAttention"]
        let blocks = preferred.compactMap { key -> SessionMapBlock? in
            guard let fact = facts[key] else { return nil }
            let label = switch key {
            case "finishedTurns": "Finished turns"
            case "sourceEntries": "Source entries"
            case "failedTools": "Failed tools"
            case "pendingAttention": "Needs attention"
            default: key
            }
            return .stat(fact: key, label: label, value: fact.value, tone: .neutral)
        }
        return SessionMapDocument(
            headline: "Session activity",
            phase: .mixed,
            summary: "The generated map is unavailable. Current session facts are shown below.",
            graph: SessionMapGraph(nodes: [], edges: []),
            flow: nil,
            plan: nil,
            blocks: blocks)
    }

    private func obsolete(
        input: SessionMapGenerationInput,
        priorDocument: SessionMapDocument?,
        priorXML: String?
    ) -> SessionMapGenerationResult {
        result(
            document: priorDocument,
            xml: priorXML,
            diagnostics: [],
            record: input.priorRecord,
            disposition: .obsolete,
            input: input)
    }

    private func result(
        document: SessionMapDocument?,
        xml: String?,
        diagnostics: [SessionMapDiagnostic],
        record: SessionMapRecord?,
        disposition: SessionMapGenerationDisposition,
        input: SessionMapGenerationInput
    ) -> SessionMapGenerationResult {
        SessionMapGenerationResult(
            document: document,
            xml: xml,
            diagnostics: diagnostics,
            record: record,
            disposition: disposition,
            generatedThrough: input.digest.cursor,
            sourceManifest: input.digest.sourceFingerprintManifest,
            checkOutcome: record?.checkOutcome ?? .off)
    }

    private func isCurrent(_ token: RequestToken, for sessionKey: String) -> Bool {
        latestRequests[sessionKey] == token
    }

    private func validateCandidate(
        _ candidate: String,
        context: SessionMapValidationContext
    ) -> SessionMapValidation {
        let validation = SessionMapDocumentParser.parse(Data(candidate.utf8), context: context)
        guard let document = validation.document,
              SessionMapXMLSerializer.serialize(document, facts: context.facts).utf8.count
                > SessionMapLimits.xmlBytes
        else { return validation }
        return SessionMapValidation(
            document: nil,
            warnings: validation.warnings,
            fatal: validation.fatal + [SessionMapDiagnostic(
                code: "limitExceeded",
                elementID: nil,
                detail: "Canonical XML exceeds \(SessionMapLimits.xmlBytes) bytes.")])
    }

    private func cacheKey(input: SessionMapGenerationInput, priorXML: String?) -> String {
        let scope = switch input.scope {
        case .sinceCaughtUp: "sinceCaughtUp"
        case .recentThreeTurns: "recentThreeTurns"
        case .wholeSession: "wholeSession"
        }
        let fields = [
            "session-map-v2", input.lineage, input.digest.cacheStateHash,
            sha256(priorXML ?? ""), scope, input.model.provider, input.model.modelID,
            input.model.effort ?? "",
        ]
        let canonical = fields.map { "\($0.utf8.count):\($0)" }.joined()
        return sha256(canonical)
    }

    private func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
