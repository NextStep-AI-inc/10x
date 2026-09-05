import Foundation

/// A dynamically-typed JSON value.
///
/// omp's RPC stream carries payloads whose shapes are version-dependent and
/// extension-supplied, so frames are decoded structurally and interpreted by
/// callers. Bool and Int are kept strictly separate: the wire contract requires
/// rejecting a JSON boolean where an integer is expected.
public enum JSONValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Foundation rejects lone UTF-16 surrogate escapes even though modern
    /// JavaScript producers preserve them in otherwise valid JSON. Replace
    /// only unpaired escapes with U+FFFD, while keeping valid pairs and literal
    /// `\\uXXXX` text intact. Invalid UTF-8 bytes follow the reference client
    /// and are decoded as replacement characters before the final attempt.
    static func decode(from data: Data) throws -> JSONValue {
        do { return try JSONDecoder().decode(JSONValue.self, from: data) }
        catch {
            let firstError = error

            let lossyUTF8 = Data(String(decoding: data, as: UTF8.self).utf8)
            let candidates = [
                replacingLoneSurrogates(in: data),
                replacingLoneSurrogates(in: lossyUTF8),
            ]
            var previous = data
            for candidate in candidates where candidate != previous {
                do { return try JSONDecoder().decode(JSONValue.self, from: candidate) }
                catch {}
                previous = candidate
            }
            throw firstError
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            // Bool first: Foundation would otherwise widen `true` to 1.
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// Integers only. A JSON boolean never reads as an int; a whole double does,
    /// since numeric fields may arrive either way depending on the encoder.
    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d) where d == d.rounded() && d.magnitude < Double(Int.max):
            return Int(d)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    public subscript(key: String) -> JSONValue? {
        guard case .object(let o) = self else { return nil }
        return o[key]
    }
}

private func replacingLoneSurrogates(in data: Data) -> Data {
    let bytes = Array(data)
    let replacement: [UInt8] = [0x5C, 0x75, 0x46, 0x46, 0x46, 0x44] // \\uFFFD
    var output: [UInt8] = []
    output.reserveCapacity(bytes.count)
    var index = 0
    var precedingBackslashes = 0

    while index < bytes.count {
        guard bytes[index] == 0x5C else {
            output.append(bytes[index])
            precedingBackslashes = 0
            index += 1
            continue
        }
        guard precedingBackslashes.isMultiple(of: 2),
              let codeUnit = unicodeEscape(in: bytes, at: index)
        else {
            output.append(bytes[index])
            precedingBackslashes += 1
            index += 1
            continue
        }

        if (0xD800...0xDBFF).contains(codeUnit),
           let low = unicodeEscape(in: bytes, at: index + 6),
           (0xDC00...0xDFFF).contains(low) {
            output.append(contentsOf: bytes[index..<(index + 12)])
            index += 12
        } else if (0xD800...0xDFFF).contains(codeUnit) {
            output.append(contentsOf: replacement)
            index += 6
        } else {
            output.append(contentsOf: bytes[index..<(index + 6)])
            index += 6
        }
        precedingBackslashes = 0
    }
    return Data(output)
}

private func unicodeEscape(in bytes: [UInt8], at index: Int) -> UInt16? {
    guard index >= 0, index + 5 < bytes.count,
          bytes[index] == 0x5C, bytes[index + 1] == 0x75
    else { return nil }
    var value: UInt16 = 0
    for byte in bytes[(index + 2)...(index + 5)] {
        let nibble: UInt16
        switch byte {
        case 0x30...0x39: nibble = UInt16(byte - 0x30)
        case 0x41...0x46: nibble = UInt16(byte - 0x41 + 10)
        case 0x61...0x66: nibble = UInt16(byte - 0x61 + 10)
        default: return nil
        }
        value = value * 16 + nibble
    }
    return value
}
