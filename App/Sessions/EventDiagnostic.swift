import Foundation
import OmpKit
import SwiftUI

enum EventDiagnosticDisplay {
    static let settledUpdateError = "Could not display this update"
}

struct EventDiagnostic: Identifiable, Equatable, Sendable {
    let id: String
    let type: String
    let byteCount: Int
    let isByteCountLowerBound: Bool
    let preview: String?
    let omittedEarlierCount: Int?

    init(
        id: String,
        type: String,
        byteCount: Int,
        isByteCountLowerBound: Bool,
        preview: String?,
        omittedEarlierCount: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.byteCount = byteCount
        self.isByteCountLowerBound = isByteCountLowerBound
        self.preview = preview
        self.omittedEarlierCount = omittedEarlierCount
    }

    static func make(id: String, type: String, payload: JSONValue) -> EventDiagnostic {
        let estimate = PayloadBoundary.estimate(payload)
        return EventDiagnostic(
            id: id,
            type: BoundaryText.sanitizeTitle(type),
            byteCount: estimate.byteCount,
            isByteCountLowerBound: estimate.isLowerBound,
            preview: nil)
    }

    static func earlierOmitted(count: Int) -> EventDiagnostic {
        EventDiagnostic(
            id: EventDiagnosticTranscript.omissionItemID,
            type: "",
            byteCount: 0,
            isByteCountLowerBound: false,
            preview: nil,
            omittedEarlierCount: count)
    }
}

enum EventDiagnosticTranscript {
    static let maxRetainedItems = 128
    static let omissionItemID = "diagnostic-earlier-omitted"

    @discardableResult
    static func upsert(
        _ diagnostic: EventDiagnostic,
        into items: inout [TranscriptItem]
    ) -> Bool {
        let item = TranscriptItem.diagnostic(diagnostic)
        if let index = items.firstIndex(where: { existing in
            guard case .diagnostic(let value) = existing else { return false }
            return value.id == diagnostic.id
        }) {
            guard items[index] != item else { return false }
            items[index] = item
        } else {
            items.append(item)
        }
        enforceCap(on: &items)
        return true
    }

    static func enforceCap(on items: inout [TranscriptItem], minimumOmittedCount: Int = 0) {
        let previousOmittedCount = max(currentOmittedCount(in: items), minimumOmittedCount)
        removeOmissionMarker(from: &items)

        var diagnosticIndices: [Int] = []
        for (index, item) in items.enumerated() {
            guard case .diagnostic = item else { continue }
            diagnosticIndices.append(index)
        }

        let excess = max(0, diagnosticIndices.count - maxRetainedItems)
        let totalOmitted = previousOmittedCount + excess

        if excess > 0 {
            for index in diagnosticIndices.prefix(excess).sorted(by: >) {
                items.remove(at: index)
            }
        }

        insertOmissionMarker(into: &items, count: totalOmitted)
    }

    /// Reconcile cannot union omitted ids from disjoint live/history windows.
    /// Use a conservative lower bound: max(live, history, rows evicted here).
    static func enforceCapAfterReconcile(
        on items: inout [TranscriptItem],
        liveOmitted: Int,
        historyOmitted: Int
    ) {
        removeOmissionMarker(from: &items)

        var diagnosticIndices: [Int] = []
        for (index, item) in items.enumerated() {
            guard case .diagnostic = item else { continue }
            diagnosticIndices.append(index)
        }

        let excess = max(0, diagnosticIndices.count - maxRetainedItems)
        let totalOmitted = max(liveOmitted, historyOmitted, excess)

        if excess > 0 {
            for index in diagnosticIndices.prefix(excess).sorted(by: >) {
                items.remove(at: index)
            }
        }

        insertOmissionMarker(into: &items, count: totalOmitted)
    }

    private static func insertOmissionMarker(into items: inout [TranscriptItem], count: Int) {
        guard count > 0 else { return }

        guard let firstDiagnosticIndex = items.firstIndex(where: { item in
            guard case .diagnostic(let diagnostic) = item else { return false }
            return diagnostic.omittedEarlierCount == nil
        }) else { return }

        items.insert(
            .diagnostic(.earlierOmitted(count: count)),
            at: firstDiagnosticIndex)
    }

    private static func currentOmittedCount(in items: [TranscriptItem]) -> Int {
        for item in items {
            guard case .diagnostic(let diagnostic) = item,
                  let count = diagnostic.omittedEarlierCount
            else { continue }
            return count
        }
        return 0
    }

    private static func removeOmissionMarker(from items: inout [TranscriptItem]) {
        items.removeAll { item in
            guard case .diagnostic(let diagnostic) = item else { return false }
            return diagnostic.omittedEarlierCount != nil
        }
    }
}

enum PayloadBoundaryTesting {
    struct Estimate: Equatable {
        let byteCount: Int
        let isLowerBound: Bool
    }

    static func estimate(_ value: JSONValue, nodeLimit: Int = 256) -> Estimate {
        let estimate = PayloadBoundary.estimate(value, nodeLimit: nodeLimit)
        return Estimate(byteCount: estimate.byteCount, isLowerBound: estimate.isLowerBound)
    }
}

private enum PayloadBoundary {
    struct Estimate: Equatable {
        let byteCount: Int
        let isLowerBound: Bool
    }

    static func estimate(_ value: JSONValue, nodeLimit: Int = 256) -> Estimate {
        var nodesVisited = 0
        var bytes = 0
        var saturated = false

        func visit(_ value: JSONValue) -> Bool {
            guard nodesVisited < nodeLimit else {
                saturated = true
                return false
            }
            nodesVisited += 1
            switch value {
            case .string(let text):
                bytes += text.utf8.count
            case .array(let values):
                for child in values {
                    guard visit(child) else { return false }
                }
            case .object(let values):
                for (key, child) in values {
                    guard nodesVisited < nodeLimit else {
                        saturated = true
                        return false
                    }
                    bytes += key.utf8.count
                    guard visit(child) else { return false }
                }
            case .int, .double, .bool, .null:
                break
            }
            return true
        }

        _ = visit(value)
        if nodesVisited >= nodeLimit { saturated = true }
        // ponytail: no transport byte count on this path; traversal is always conservative.
        return Estimate(byteCount: bytes, isLowerBound: true)
    }
}

struct DiagnosticCardView: View {
    let diagnostic: EventDiagnostic

    var body: some View {
        CornerCard(color: TenXPalette.color(TenXPalette.mutedTextHex)) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Self.title(for: diagnostic))
                    .font(TenXTypography.body(size: 12, weight: .semibold))
                    .foregroundStyle(TenXPalette.color(TenXPalette.nearBlackHex))

                if let omittedCount = diagnostic.omittedEarlierCount {
                    Text(Self.omissionBody(omittedCount))
                        .font(TenXTypography.body(size: 11))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                } else if !diagnostic.type.isEmpty {
                    Text(diagnostic.type)
                        .font(TenXTypography.mono(size: 10))
                        .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    if diagnostic.byteCount > 0 || diagnostic.isByteCountLowerBound {
                        Text(Self.sizeLabel(diagnostic))
                            .font(TenXTypography.mono(size: 10))
                            .foregroundStyle(TenXPalette.color(TenXPalette.mutedTextHex))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.accessibilityLabel(for: diagnostic))
    }

    nonisolated static func title(for diagnostic: EventDiagnostic) -> String {
        diagnostic.omittedEarlierCount == nil ? "Additional activity" : "Earlier activity omitted"
    }

    nonisolated static func omissionBody(_ count: Int) -> String {
        count == 1
            ? "At least 1 earlier item omitted"
            : "At least \(count) earlier items omitted"
    }

    nonisolated static func sizeLabel(_ diagnostic: EventDiagnostic) -> String {
        let prefix = diagnostic.isByteCountLowerBound ? "At least " : ""
        let count = diagnostic.byteCount
        if count < 1_000 {
            let unit = count == 1 ? "byte" : "bytes"
            return "\(prefix)\(count) \(unit)"
        }
        return String(format: "\(prefix)%.1f KB", Double(count) / 1_000)
    }

    nonisolated static func accessibilityLabel(for diagnostic: EventDiagnostic) -> String {
        if let omittedCount = diagnostic.omittedEarlierCount {
            let itemCount = omittedCount == 1 ? "1 item" : "\(omittedCount) items"
            return "Earlier activity omitted, at least \(itemCount)"
        }
        var parts = [title(for: diagnostic), diagnostic.type]
        if diagnostic.byteCount > 0 || diagnostic.isByteCountLowerBound {
            parts.append(sizeLabel(diagnostic))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
