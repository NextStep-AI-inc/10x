import Foundation
import CryptoKit

enum SessionMapDigestBuilder {
    static let maxBytes = 12 * 1024
    private static let assistantExcerptBytes = 600

    static func build(
        source: SessionMapSource,
        previousManifest: [String: String] = [:],
        scope: SessionMapGenerationScope,
        planningExcerpts: [SessionMapPlanningExcerpt] = []
    ) -> SessionMapDigest {
        let manifest = Dictionary(
            source.entries.map { ($0.id, $0.contentFingerprint) },
            uniquingKeysWith: { _, latest in latest })
        let delta = scopedEntries(
            source.entries.filter { previousManifest[$0.id] != $0.contentFingerprint },
            source: source,
            scope: scope)
        var facts = source.entries.reduce(into: [String: SessionMapFact]()) { result, entry in
            let stableFacts = entry.facts.filter {
                !$0.key.hasPrefix("failedTool.")
                    && !$0.key.hasPrefix("pendingAttention.")
                    && !$0.key.hasPrefix("subagentCost.")
            }
            result.merge(stableFacts, uniquingKeysWith: { _, latest in latest })
        }
        let failedTools = source.entries.filter { $0.facts.keys.contains { $0.hasPrefix("failedTool.") } }
        if !failedTools.isEmpty {
            facts["failedTools"] = SessionMapFact(
                value: String(failedTools.count),
                number: Double(failedTools.count))
        }
        let pendingAttention = source.entries.filter {
            $0.facts.keys.contains { $0.hasPrefix("pendingAttention.") }
        }
        if !pendingAttention.isEmpty {
            facts["pendingAttention"] = SessionMapFact(
                value: String(pendingAttention.count),
                number: Double(pendingAttention.count))
        }
        let costs = source.entries.flatMap { entry in
            entry.facts.compactMap { key, fact in
                key.hasPrefix("subagentCost.") ? fact.number : nil
            }
        }
        if !costs.isEmpty {
            let cost = costs.reduce(0, +)
            facts["cost"] = SessionMapFact(
                value: String(format: "%.4f", cost),
                number: cost)
        }
        facts["finishedTurns"] = SessionMapFact(
            value: String(source.finishedTurnIDs.count),
            number: Double(source.finishedTurnIDs.count))
        facts["sourceEntries"] = SessionMapFact(
            value: String(source.entries.count),
            number: Double(source.entries.count))

        let footer = factsFooter(facts)
        let header = "Session delta (\(scopeName(scope)))\n"
        let planning = planningRecords(planningExcerpts)
        let reservedOmissionBytes = 64
        let available = max(
            0,
            maxBytes - header.utf8.count - footer.utf8.count
                - planning.utf8.count - reservedOmissionBytes)
        let records = delta.map(record)
        let prioritizedIndexes = prioritized(delta)
        var selected: Set<Int> = []
        var used = 0
        for index in prioritizedIndexes {
            let size = records[index].utf8.count
            guard used + size <= available else { continue }
            selected.insert(index)
            used += size
        }
        let omitted = delta.count - selected.count
        let body = delta.indices.compactMap { selected.contains($0) ? records[$0] : nil }.joined()
        let omission = omitted > 0 ? "[omitted] \(omitted) earlier or routine entries\n" : ""
        var text = header + body + omission + planning + footer
        if text.utf8.count > maxBytes {
            let fixed = header + omission + planning + footer
            let bodyBudget = max(0, maxBytes - fixed.utf8.count)
            text = header + utf8Prefix(body, maxBytes: bodyBudget) + omission + planning + footer
        }

        let canonicalFacts = facts.sorted { $0.key < $1.key }.map {
            let number = $0.value.number.map { String($0) } ?? ""
            return "\($0.key)=\($0.value.value)|\(number)"
        }.joined(separator: "\n")
        let canonicalManifest = manifest.sorted { $0.key < $1.key }.map {
            "\($0.key)=\($0.value)"
        }.joined(separator: "\n")
        let hashInput = [
            source.lineage,
            scopeName(scope),
            text,
            canonicalFacts,
            canonicalManifest,
        ].map { "\($0.utf8.count):\($0)" }.joined()
        return SessionMapDigest(
            text: text,
            hash: sha256(hashInput),
            facts: facts,
            knownRefs: source.knownRefs,
            cursor: SessionMapCursor(
                lineage: source.lineage,
                entryID: source.entries.last?.id),
            sourceFingerprintManifest: manifest,
            statusEvidence: source.statusEvidence)
    }

    static func utf8Prefix(_ text: String, maxBytes: Int) -> String {
        guard maxBytes > 0 else { return "" }
        var result = ""
        var used = 0
        for character in text {
            let size = String(character).utf8.count
            guard used + size <= maxBytes else { break }
            result.append(character)
            used += size
        }
        return result
    }

    private static func scopedEntries(
        _ delta: [SessionMapSourceEntry],
        source: SessionMapSource,
        scope: SessionMapGenerationScope
    ) -> [SessionMapSourceEntry] {
        guard scope == .recentThreeTurns,
              let firstID = source.finishedTurnIDs.suffix(3).first,
              let boundary = source.entries.firstIndex(where: { $0.id == firstID })
        else { return delta }
        let allowed = Set(source.entries[boundary...].map(\.id))
        return delta.filter { allowed.contains($0.id) || $0.kind == .attention }
    }

    private static func record(_ entry: SessionMapSourceEntry) -> String {
        let textLimit = entry.kind == .assistant ? assistantExcerptBytes : 700
        let text = utf8Prefix(entry.text, maxBytes: textLimit)
        let primary = entry.primary.map { " | \(utf8Prefix($0, maxBytes: 240))" } ?? ""
        let outcome = entry.outcome.map { " | \(utf8Prefix($0, maxBytes: 240))" } ?? ""
        return "[\(entry.kind.rawValue)] \(entry.id) | \(text)\(primary)\(outcome)\n"
    }

    private static func prioritized(_ entries: [SessionMapSourceEntry]) -> [Int] {
        let newestFirst = Array(entries.indices.reversed())
        let attention = newestFirst.filter { entries[$0].kind == .attention }
        let substantive = newestFirst.filter {
            entries[$0].kind != .attention && !isRoutineRead(entries[$0])
        }
        let routine = newestFirst.filter {
            entries[$0].kind != .attention && isRoutineRead(entries[$0])
        }
        return attention + substantive + routine
    }

    private static func isRoutineRead(_ entry: SessionMapSourceEntry) -> Bool {
        entry.kind == .tool && entry.text.lowercased() == "read"
    }

    private static func planningRecords(_ excerpts: [SessionMapPlanningExcerpt]) -> String {
        guard !excerpts.isEmpty else { return "" }
        let records = excerpts.map { excerpt in
            "[planning] \(excerpt.ref) | \(excerpt.file) | hash=\(excerpt.hash)\n\(excerpt.text)\n"
        }.joined()
        return "Planning excerpts\n" + utf8Prefix(records, maxBytes: 4 * 1024)
    }

    private static func factsFooter(_ facts: [String: SessionMapFact]) -> String {
        let values = facts.sorted { $0.key < $1.key }.map { key, fact in
            let number = fact.number.map { " number=\($0)" } ?? ""
            return "- \(key): \(fact.value)\(number)"
        }
        return "Facts\n" + values.joined(separator: "\n") + "\n"
    }

    private static func scopeName(_ scope: SessionMapGenerationScope) -> String {
        switch scope {
        case .sinceCaughtUp: "sinceCaughtUp"
        case .recentThreeTurns: "recentThreeTurns"
        case .wholeSession: "wholeSession"
        }
    }

    private static func sha256(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
