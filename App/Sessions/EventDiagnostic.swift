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

    static func enforceCap(on items: inout [TranscriptItem]) {
        let previousOmittedCount = currentOmittedCount(in: items)
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

        guard totalOmitted > 0 else { return }

        guard let firstDiagnosticIndex = items.firstIndex(where: { item in
            guard case .diagnostic(let diagnostic) = item else { return false }
            return diagnostic.omittedEarlierCount == nil
        }) else { return }

        items.insert(
            .diagnostic(.earlierOmitted(count: totalOmitted)),
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

private enum PayloadBoundary {
    struct Estimate: Equatable {
        let byteCount: Int
        let isLowerBound: Bool
    }

    static func estimate(_ value: JSONValue, nodeLimit: Int = 256) -> Estimate {
        var nodesVisited = 0
        var bytes = 0
        var isLowerBound = false

        func visit(_ value: JSONValue) {
            guard nodesVisited < nodeLimit else {
                isLowerBound = true
                return
            }
            nodesVisited += 1
            switch value {
            case .string(let text):
                bytes += Data(text.utf8).count
            case .array(let values):
                for child in values { visit(child) }
            case .object(let values):
                for (key, child) in values {
                    bytes += Data(key.utf8).count
                    visit(child)
                }
            case .int, .double, .bool, .null:
                break
            }
        }

        visit(value)
        if nodesVisited >= nodeLimit { isLowerBound = true }
        return Estimate(byteCount: bytes, isLowerBound: isLowerBound)
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
                    if diagnostic.byteCount > 0 {
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
        count == 1 ? "1 earlier item omitted" : "\(count) earlier items omitted"
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
            return "Earlier activity omitted, \(itemCount)"
        }
        var parts = [title(for: diagnostic), diagnostic.type]
        if diagnostic.byteCount > 0 {
            parts.append(sizeLabel(diagnostic))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
