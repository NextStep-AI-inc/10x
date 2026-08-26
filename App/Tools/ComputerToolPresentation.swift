import Foundation
import ImageIO
import OmpKit
import UniformTypeIdentifiers

struct ComputerImage: Identifiable, Equatable {
    let id: String
    let data: Data
    let mimeType: String
}

enum ComputerControlMode: Equatable {
    case readOnly
    case background
    case handoff

    var label: String {
        switch self {
        case .readOnly: "Read only"
        case .background: "Background"
        case .handoff: "Handoff"
        }
    }
}

struct ComputerToolPresentation: Equatable {
    let target: String?
    let output: String
    let returnValue: String?
    let code: String
    let isReadOnly: Bool
    let mode: ComputerControlMode
    let images: [ComputerImage]
    let capabilities: ComputerCapabilities
    let rawDetails: JSONValue?

    init?(_ presentation: ToolPresentation) {
        guard presentation.name.lowercased() == "computer" else { return nil }
        let details = presentation.result?["details"]
        code = presentation.arguments["code"]?.stringValue
            ?? details?["code"]?.stringValue
            ?? ""
        isReadOnly = presentation.arguments["read_only"]?.boolValue
            ?? details?["readOnly"]?.boolValue
            ?? false
        output = ToolContentExtractor.outputText(presentation.result) ?? ""
        returnValue = details?["returnValue"]?.stringValue
        images = Self.decodeImages(presentation.result?["content"])
        capabilities = ComputerCapabilities(json: details) ?? .unknown
        target = details?["screenshots"]?.arrayValue?.last?["target"]?.stringValue
            ?? details?["target"]?.stringValue
        rawDetails = details
        if isReadOnly {
            mode = .readOnly
        } else if details?["foregroundHandoff"]?.boolValue == true
            || details?["mode"]?.stringValue == "handoff" {
            mode = .handoff
        } else {
            mode = .background
        }
    }

    private static let maximumDecodedImageBytes = 20 * 1_024 * 1_024
    private static let maximumBase64Characters = ((maximumDecodedImageBytes + 2) / 3) * 4

    private static func decodeImages(_ content: JSONValue?) -> [ComputerImage] {
        content?.arrayValue?.enumerated().compactMap { index, block in
            guard block["type"]?.stringValue == "image",
                  let encoded = block["data"]?.stringValue,
                  encoded.utf8.count <= maximumBase64Characters,
                  let mimeType = block["mimeType"]?.stringValue,
                  mimeType == "image/png" || mimeType == "image/jpeg",
                  let data = Data(base64Encoded: encoded),
                  !data.isEmpty,
                  data.count <= maximumDecodedImageBytes,
                  isValidatedImage(data, mimeType: mimeType)
            else { return nil }
            return ComputerImage(
                id: "\(index)-\(mimeType)-\(data.count)",
                data: data,
                mimeType: mimeType)
        } ?? []
    }

    private static func isValidatedImage(_ data: Data, mimeType: String) -> Bool {
        let expectedType: UTType
        switch mimeType {
        case "image/png":
            guard data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else {
                return false
            }
            expectedType = .png
        case "image/jpeg":
            guard data.starts(with: [0xFF, 0xD8, 0xFF]),
                  data.suffix(2).elementsEqual([0xFF, 0xD9])
            else { return false }
            expectedType = .jpeg
        default:
            return false
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let sourceType = CGImageSourceGetType(source),
              let uniformType = UTType(sourceType as String),
              uniformType.conforms(to: expectedType),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                  as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0,
              height.intValue > 0
        else { return false }
        return true
    }
}
