import Testing
import Foundation
@testable import OmpKit

// Captured from a live `omp --mode rpc` probe on 2026-08-24 (omp 18.0.4).
let readyLine = #"{"type":"ready","protocolVersion":1,"supportedProtocolVersions":[1,2],"maxFrameBytes":1048576,"maxReassembledFrameBytes":67108864}"#
let responseLine = #"{"id":"n1","type":"response","command":"negotiate_protocol","success":true,"data":{"protocolVersion":2}}"#
let widgetLine = #"{"type":"extension_ui_request","id":"1564dcc6257a3714","method":"setWidget","widgetKey":"autoresearch"}"#
let noticeLine = #"{"type":"notice","level":"info","message":"xd://: mounted","source":"xdev"}"#

@Test func decodesReadyFrame() throws {
    guard case .ready(let r) = try RpcFrame.decode(line: Data(readyLine.utf8)) else {
        Issue.record("not a ready frame"); return
    }
    #expect(r.supportedProtocolVersions == [1, 2])
    #expect(r.maxFrameBytes == 1_048_576)
}

@Test func decodesResponseFrame() throws {
    guard case .response(let r) = try RpcFrame.decode(line: Data(responseLine.utf8)) else {
        Issue.record("not a response"); return
    }
    #expect(r.id == "n1")
    #expect(r.success)
    #expect(r.data?["protocolVersion"]?.intValue == 2)
}

@Test func unknownFrameBecomesEvent() throws {
    guard case .event(let type, let payload) = try RpcFrame.decode(line: Data(noticeLine.utf8)) else {
        Issue.record("not an event"); return
    }
    #expect(type == "notice")
    #expect(payload["level"]?.stringValue == "info")
}

@Test func extensionUIRequestKeepsFullPayload() throws {
    guard case .extensionUIRequest(let req) = try RpcFrame.decode(line: Data(widgetLine.utf8)) else {
        Issue.record("not an extension UI request"); return
    }
    #expect(req.method == "setWidget")
    #expect(req.payload["widgetKey"]?.stringValue == "autoresearch")
}

@Test func chunkRejectsBooleanIndex() {
    let bad = #"{"type":"rpc_chunk","chunkId":"c1","index":true,"count":2,"byteLength":10,"data":"aGk="}"#
    #expect(throws: (any Error).self) { _ = try RpcFrame.decode(line: Data(bad.utf8)) }
}

@Test func frameWithoutTypeThrows() {
    #expect(throws: (any Error).self) { _ = try RpcFrame.decode(line: Data(#"{"id":"x"}"#.utf8)) }
}

@Test func decodesValidChunkFrame() throws {
    let line = #"{"type":"rpc_chunk","chunkId":"rpc-1","index":0,"count":3,"byteLength":42,"data":"aGk="}"#
    guard case .chunk(let c) = try RpcFrame.decode(line: Data(line.utf8)) else {
        Issue.record("not a chunk"); return
    }
    #expect(c.chunkId == "rpc-1")
    #expect(c.index == 0)
    #expect(c.count == 3)
    #expect(c.byteLength == 42)
}

@Test func responseCarriesErrorAndCode() throws {
    let line = #"{"id":"p1","type":"response","command":"get_messages_page","success":false,"error":"busy","code":"session_busy"}"#
    guard case .response(let r) = try RpcFrame.decode(line: Data(line.utf8)) else {
        Issue.record("not a response"); return
    }
    #expect(!r.success)
    #expect(r.error == "busy")
    #expect(r.code == "session_busy")
}

@Test func jsonValueSeparatesBoolFromInt() throws {
    let v = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"b":true,"i":1}"#.utf8))
    #expect(v["b"]?.boolValue == true)
    #expect(v["b"]?.intValue == nil)   // a bool must NOT read as an int
    #expect(v["i"]?.intValue == 1)
    #expect(v["i"]?.boolValue == nil)
}

@Test func loneSurrogateEscapesAreReplacedWithoutDroppingTheFrame() throws {
    let line = Data(#"{"type":"notice","message":"before \uD800 after"}"#.utf8)
    guard case .event(_, let payload) = try RpcFrame.decode(line: line) else {
        Issue.record("not an event"); return
    }
    #expect(payload["message"]?.stringValue == "before � after")
}

@Test func validSurrogatePairsAndEscapedBackslashesRemainIntact() throws {
    let pair = Data(#"{"type":"notice","message":"\uD83D\uDE00"}"#.utf8)
    guard case .event(_, let pairedPayload) = try RpcFrame.decode(line: pair) else {
        Issue.record("not an event"); return
    }
    #expect(pairedPayload["message"]?.stringValue == "😀")

    let literal = Data(#"{"type":"notice","message":"\\uD800"}"#.utf8)
    guard case .event(_, let literalPayload) = try RpcFrame.decode(line: literal) else {
        Issue.record("not an event"); return
    }
    #expect(literalPayload["message"]?.stringValue == #"\uD800"#)
}

@Test func invalidUTF8AndLoneSurrogatesUseTheFinalRepairCandidate() throws {
    var line = Data(#"{"type":"notice","message":"before "#.utf8)
    line.append(0xFF)
    line.append(contentsOf: Data(#" \uD800 after"}"#.utf8))

    guard case .event(_, let payload) = try RpcFrame.decode(line: line) else {
        Issue.record("not an event"); return
    }

    #expect(payload["message"]?.stringValue == "before � � after")
}

@Test func irreparableJSONReportsTheOriginalDecodeError() {
    let line = Data(#"{"type":"notice","message":"unterminated"#.utf8)
    var directError: String?
    var repairedError: String?

    do { _ = try JSONDecoder().decode(JSONValue.self, from: line) }
    catch { directError = String(describing: error) }
    do { _ = try JSONValue.decode(from: line) }
    catch { repairedError = String(describing: error) }

    #expect(repairedError == directError)
}
