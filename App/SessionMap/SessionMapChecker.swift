import AppKit
import CoreGraphics
import Foundation
import ImageIO
import OmpKit
import SwiftUI
import UniformTypeIdentifiers

enum SessionMapVerdictIssueType: String, CaseIterable, Equatable, Sendable {
    case clipped
    case empty
    case unsupportedClaim = "unsupported-claim"
    case wrongTone = "wrong-tone"
    case layout
}

struct SessionMapVerdictIssue: Equatable, Sendable {
    let type: SessionMapVerdictIssueType
    let nodeID: String?
    let description: String
}

struct SessionMapVerdict: Equatable, Sendable {
    let passes: Bool
    let issues: [SessionMapVerdictIssue]
}

enum SessionMapCheckerError: Error {
    case renderFailed
    case malformedVerdict
}

typealias SessionMapNativeRenderer = @MainActor @Sendable (
    _ document: SessionMapDocument,
    _ layout: SessionMapLayoutResult,
    _ width: CGFloat
) async throws -> Data

struct SessionMapChecker: Sendable {
    private let completion: SessionMapWriterCompletion
    private let renderer: SessionMapNativeRenderer

    init(
        completion: @escaping SessionMapWriterCompletion,
        renderer: SessionMapNativeRenderer? = nil
    ) {
        self.completion = completion
        self.renderer = renderer ?? Self.renderNativeGraph
    }

    @MainActor
    func render(
        document: SessionMapDocument,
        layout: SessionMapLayoutResult,
        width: CGFloat
    ) async throws -> Data {
        try await renderer(document, layout, width)
    }

    func check(
        png: Data,
        xml: String,
        digest: SessionMapDigest,
        model: SessionMapResolvedModel
    ) async throws -> SessionMapVerdict {
        let response = try await completion(
            SessionMapPrompt.checker(xml: xml, digest: digest),
            [PromptImage(base64Data: png.base64EncodedString(), mimeType: "image/png")],
            model)
        return try Self.parseVerdict(response)
    }

    static func parseVerdict(_ xml: String) throws -> SessionMapVerdict {
        guard xml.utf8.count <= 16 * 1024,
              !xml.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !xml.localizedCaseInsensitiveContains("<!ENTITY")
        else { throw SessionMapCheckerError.malformedVerdict }
        let parserDelegate = VerdictParserDelegate()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = parserDelegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), parserDelegate.depth == 0,
              let passes = parserDelegate.passes,
              parserDelegate.sawRoot
        else { throw SessionMapCheckerError.malformedVerdict }
        return SessionMapVerdict(passes: passes, issues: parserDelegate.issues)
    }

    static func prioritizedIssues(
        modelIssues: [SessionMapVerdictIssue],
        layoutDiagnostics: [SessionMapLayoutDiagnostic]
    ) -> [SessionMapVerdictIssue] {
        let deterministicIssues: [SessionMapVerdictIssue] = layoutDiagnostics.compactMap { diagnostic in
            guard diagnostic.code != "edge-label-hidden" else { return nil }
            return SessionMapVerdictIssue(
                type: .layout,
                nodeID: nil,
                description: String(diagnostic.message.prefix(240)))
        }
        return Array((deterministicIssues + modelIssues).prefix(12))
    }

    @MainActor
    private static func renderNativeGraph(
        document: SessionMapDocument,
        layout: SessionMapLayoutResult,
        width: CGFloat
    ) async throws -> Data {
        let renderedWidth = max(1, width - (2 * SessionMapPaneView.contentPadding))
        let renderedHeight = min(max(96, layout.size.height), 480) + 34
        let focus = Binding.constant(SessionMapFocus(
            selectedNodeID: nil,
            hoveredNodeID: nil,
            focusedNodeID: nil,
            flowStepIndex: nil))
        let root = SessionMapGraphView(
            document: document,
            layout: layout,
            focus: focus,
            activity: .empty,
            changes: .empty,
            onAction: { _ in })
            .frame(width: renderedWidth, height: renderedHeight)
            .background(TenXPalette.color(TenXPalette.canvasHex))
            .environment(\.sessionMapReduceMotionOverride, true)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        host.frame = CGRect(x: 0, y: 0, width: renderedWidth, height: renderedHeight)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw SessionMapCheckerError.renderFailed
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let image = bitmap.cgImage else { throw SessionMapCheckerError.renderFailed }
        return try await Task.detached {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil)
            else { throw SessionMapCheckerError.renderFailed }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw SessionMapCheckerError.renderFailed
            }
            return Data(referencing: data)
        }.value
    }
}

private final class VerdictParserDelegate: NSObject, XMLParserDelegate {
    var passes: Bool?
    var issues: [SessionMapVerdictIssue] = []
    var depth = 0
    var sawRoot = false
    private var currentIssue: (type: SessionMapVerdictIssueType, nodeID: String?)?
    private var currentText = ""
    private var isMalformed = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        depth += 1
        guard !isMalformed else { return }
        if depth == 1 {
            guard elementName == "verdict", !sawRoot,
                  let rawPass = attributeDict["pass"],
                  rawPass == "true" || rawPass == "false"
            else { isMalformed = true; return }
            sawRoot = true
            passes = rawPass == "true"
        } else if depth == 2, elementName == "issue", issues.count < 12,
                  let rawType = attributeDict["type"],
                  let type = SessionMapVerdictIssueType(rawValue: rawType)
        {
            currentIssue = (
                type,
                attributeDict["node"].map { String($0.prefix(SessionMapLimits.nodeID)) })
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentIssue != nil, currentText.count < 240 { currentText += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if depth == 2, elementName == "issue", let currentIssue {
            let description = String(currentText
                .trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
            issues.append(SessionMapVerdictIssue(
                type: currentIssue.type,
                nodeID: currentIssue.nodeID,
                description: description))
            self.currentIssue = nil
            currentText = ""
        }
        depth -= 1
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        if isMalformed { parser.abortParsing() }
    }
}
