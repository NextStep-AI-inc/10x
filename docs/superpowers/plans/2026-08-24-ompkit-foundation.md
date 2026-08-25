# OmpKit Foundation Implementation Plan (Plan 1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and test OmpKit — the zero-UI Swift package that speaks omp's RPC protocol (spawn, frame codec, chunk reassembly, correlation, events) and reads omp's session files (metadata, status, tree) — gating all UI work.

**Architecture:** A SwiftPM library with two subsystems: `Wire/` (frame types, chunk reassembler, command encoder, process transport, `RpcClient` actor) and `Sessions/` (title-slot/header/entry parsing, tree reconstruction, bucket listing, file watching, process manager). Ported from omp's bundled Python reference client and the session layer's documented on-disk contract. Unknown wire frames and unknown session entries are ALWAYS tolerated (decoded as `.unknown`), never fatal — the live probe showed extension frames (`setWidget`, `notice`, `available_commands_update`) arrive immediately at startup on this machine.

**Tech Stack:** Swift 6 (toolchain 6.3.3 / Xcode 26.6), SwiftPM, Swift Testing (`@Test`), Foundation `Process`. Zero external dependencies in OmpKit. Test fakes are small Python 3 scripts (mirroring omp's own test approach).

## Global Constraints

- Tested against **omp 18.0.4**, RPC protocol **v2**. Contract docs in `docs/contracts/` are extracted from that exact version — cite them, don't re-derive.
- Package platform: `.macOS(.v15)`. Strict concurrency (Swift 6 language mode). No `!` force-unwraps, no `try!` outside tests.
- Zero SwiftPM dependencies for OmpKit. Test fixtures may use `python3` (present on this machine).
- Unknown frame types / entry types / enum values decode to `.unknown` carrying the raw payload — never `throw` on unrecognized *values*; `throw` only on structural protocol violations (chunk rules, non-JSON lines are recoverable-skipped with a diagnostic).
- Conventional commits, atomic, no attribution lines. Work happens on a branch in a worktree (`superpowers:using-git-worktrees`), never the main checkout.
- Wire constants (from `docs/contracts/rpc-client-port-spec.md` §0, quoted): maxFrameBytes `1_048_576`, maxReassembled `67_108_864`, chunk payload `262_144`, request ids `"req_{n}"` from 1, default request timeout 30 s, startup timeout 30 s.
- Session constants (from `docs/contracts/session-file-contract.md`): title slot exactly **256 bytes**, `CURRENT_SESSION_VERSION = 3`, list prefix window `4096` B, status suffix window `32_768` B, sort by mtime descending, listing glob depth exactly 2 (`*/*.jsonl`).
- **The package lives in `OmpKit/`** (per the spec's repo layout — the app target lands beside it in Plan 2). Every `Sources/…` and `Tests/…` path in the tasks below is relative to `OmpKit/`, and every `swift test` runs from inside `OmpKit/`.

---

### Task 1: Package scaffold

**Files:**
- Create: `OmpKit/Package.swift`, `OmpKit/Sources/OmpKit/OmpKit.swift`, `OmpKit/Tests/OmpKitTests/SmokeTests.swift`, `.gitignore` (repo root)

**Interfaces:**
- Produces: SwiftPM targets `OmpKit` (library) and `OmpKitTests` that later tasks add files into.

- [x] **Step 1: Write Package.swift**

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "OmpKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "OmpKit", targets: ["OmpKit"])],
    targets: [
        .target(name: "OmpKit"),
        .testTarget(
            name: "OmpKitTests",
            dependencies: ["OmpKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [x] **Step 2: Create the source and test stubs**

`Sources/OmpKit/OmpKit.swift`:
```swift
/// OmpKit — Swift client for the oh-my-pi (omp) coding agent.
/// Wire protocol: docs/contracts/rpc-wire-contract.md, rpc-client-port-spec.md.
/// Session files: docs/contracts/session-file-contract.md.
public enum OmpKitInfo {
    /// omp version these contracts were extracted from.
    public static let testedOmpVersion = "18.0.4"
}
```

`Tests/OmpKitTests/SmokeTests.swift`:
```swift
import Testing
@testable import OmpKit

@Test func packageBuilds() {
    #expect(OmpKitInfo.testedOmpVersion == "18.0.4")
}
```

Create `Tests/OmpKitTests/Fixtures/.gitkeep` (empty file) so the resource directory exists.

`.gitignore`:
```
.build/
.swiftpm/
*.xcodeproj
DerivedData/
```

- [x] **Step 3: Run tests**

Run: `cd OmpKit && swift test`
Expected: `Test run with 1 test passed`

- [x] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: scaffold OmpKit SwiftPM package"
```

---

### Task 2: JSONValue + frame types + envelope decoding

**Files:**
- Create: `Sources/OmpKit/Wire/JSONValue.swift`, `Sources/OmpKit/Wire/RpcFrame.swift`
- Test: `Tests/OmpKitTests/FrameDecodingTests.swift`

**Interfaces:**
- Produces:
  - `public enum JSONValue: Sendable, Equatable, Codable` with cases `.null, .bool(Bool), .int(Int), .double(Double), .string(String), .array([JSONValue]), .object([String: JSONValue])` and accessors `var stringValue: String?`, `var intValue: Int?`, `var boolValue: Bool?`, `var objectValue: [String: JSONValue]?`, `subscript(key: String) -> JSONValue?`.
  - `public struct ReadyFrame: Sendable, Decodable` — `protocolVersion: Int`, `supportedProtocolVersions: [Int]?`, `maxFrameBytes: Int?`, `maxReassembledFrameBytes: Int?`.
  - `public struct RpcResponse: Sendable` — `id: String?`, `command: String`, `success: Bool`, `data: JSONValue?`, `error: String?`, `code: String?`.
  - `public struct RpcChunk: Sendable, Decodable` — `chunkId: String`, `index: Int`, `count: Int`, `byteLength: Int`, `data: String`. **Custom `init(from:)` must reject JSON booleans in the numeric fields** (decode as `JSONValue` and require `.int`; the reference client explicitly rejects bool-masquerading-as-int — port-spec §caveat 3).
  - `public struct ExtensionUIRequest: Sendable` — `id: String`, `method: String`, `payload: JSONValue` (full object; typed accessors come in Plan 2).
  - `public enum RpcFrame: Sendable` — `.ready(ReadyFrame)`, `.response(RpcResponse)`, `.chunk(RpcChunk)`, `.extensionUIRequest(ExtensionUIRequest)`, `.event(type: String, payload: JSONValue)` (everything else, including `notice`, `available_commands_update`, all `AgentSessionEvent`s), and `static func decode(line: Data) throws -> RpcFrame`.
- Consumes: nothing prior.

- [x] **Step 1: Write failing tests with real captured frames**

```swift
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
```

- [x] **Step 2: Run to verify failure** — `swift test 2>&1 | tail -5` — Expected: compile FAILS (types undefined).

- [x] **Step 3: Implement**

`JSONValue.swift`: standard recursive Codable enum. Decode order in `init(from:)`: try `Bool` FIRST, then `Int`, then `Double`, then `String`, then `[JSONValue]`, then `[String: JSONValue]`, then null — Bool-before-Int is what makes `.intValue` on a `true` return nil, giving the strict bool/int separation the wire contract requires. `intValue` returns the int case only (plus a whole `Double` like `2.0` — `data.protocolVersion` may decode as either).

`RpcFrame.swift`:
```swift
public enum RpcFrameError: Error, Sendable {
    case notAnObject
    case missingType
    case malformedFrame(type: String, underlying: String)
}

public enum RpcFrame: Sendable {
    case ready(ReadyFrame)
    case response(RpcResponse)
    case chunk(RpcChunk)
    case extensionUIRequest(ExtensionUIRequest)
    case event(type: String, payload: JSONValue)

    public static func decode(line: Data) throws -> RpcFrame {
        let value = try JSONDecoder().decode(JSONValue.self, from: line)
        guard case .object(let obj) = value else { throw RpcFrameError.notAnObject }
        guard let type = obj["type"]?.stringValue else { throw RpcFrameError.missingType }
        switch type {
        case "ready":
            return .ready(try JSONDecoder().decode(ReadyFrame.self, from: line))
        case "response":
            return .response(try RpcResponse(from: obj, type: type))
        case "rpc_chunk":
            return .chunk(try RpcChunk(from: obj))
        case "extension_ui_request":
            guard let id = obj["id"]?.stringValue, let method = obj["method"]?.stringValue else {
                throw RpcFrameError.malformedFrame(type: type, underlying: "missing id/method")
            }
            return .extensionUIRequest(ExtensionUIRequest(id: id, method: method, payload: value))
        default:
            return .event(type: type, payload: value)
        }
    }
}
```

`RpcResponse.init(from:type:)` requires `command: String` and `success: Bool` (throw `.malformedFrame` otherwise); `id`, `data`, `error`, `code` optional. `RpcChunk.init(from:)` requires `chunkId` string, `index`/`count`/`byteLength` via `.intValue` (bools have no intValue → throws `.malformedFrame`), `data` string.

- [x] **Step 4: Run tests** — `swift test` — Expected: all PASS.

- [x] **Step 5: Commit** — `git add -A && git commit -m "feat: RPC frame types and envelope decoding"`

---

### Task 3: Chunk reassembly state machine

**Files:**
- Create: `Sources/OmpKit/Wire/ChunkReassembler.swift`
- Test: `Tests/OmpKitTests/ChunkReassemblerTests.swift`

**Interfaces:**
- Consumes: `RpcChunk`, `RpcFrame` (Task 2).
- Produces:
  ```swift
  public struct ChunkReassembler: Sendable {
      public init(maxReassembledBytes: Int = 67_108_864)
      /// Feed one chunk. Returns the completed payload when the sequence finishes, nil mid-sequence.
      public mutating func ingest(_ chunk: RpcChunk) throws -> Data?
      /// Call for every NON-chunk frame; throws if a sequence is open (interleaving is a protocol violation).
      public mutating func noteNonChunkFrame() throws
      public var isReassembling: Bool { get }
  }
  public enum ChunkError: Error, Equatable, Sendable {
      case invalidStart(index: Int)         // first chunk of a sequence must have index 0
      case mismatchedSequence(field: String) // chunkId/count/byteLength changed mid-sequence
      case outOfOrder(expected: Int, got: Int)
      case interleaved                       // non-chunk frame while a sequence is open
      case tooLarge(byteLength: Int, cap: Int)
      case invalidCount(Int)                 // count < 1
      case badBase64
      case lengthMismatch(declared: Int, actual: Int)
      case notUTF8
  }
  ```

Validation rules (port-spec §2 — the reference algorithm, port exactly): a sequence opens only on `index == 0`; `count >= 1`; `byteLength <= cap` checked at open; every subsequent chunk must match `chunkId`, `count`, `byteLength` and arrive with `index == previous + 1`; base64 decodes strictly (reject invalid); on final chunk (`index == count - 1`) concatenated bytes must equal `byteLength` exactly, then decode strict UTF-8 (the payload is a JSON object re-fed to `RpcFrame.decode`; UTF-8 validation happens here, JSON parse happens in the caller). Any violation throws AND resets the state machine to idle.

- [x] **Step 1: Write failing tests**

```swift
import Testing
import Foundation
@testable import OmpKit

private func chunks(of payload: String, id: String = "rpc-1", size: Int = 4) -> [RpcChunk] {
    let bytes = Array(payload.utf8)
    let parts = stride(from: 0, to: bytes.count, by: size).map { Array(bytes[$0..<min($0 + size, bytes.count)]) }
    return parts.enumerated().map { i, part in
        RpcChunk(chunkId: id, index: i, count: parts.count,
                 byteLength: bytes.count, data: Data(part).base64EncodedString())
    }
}

@Test func reassemblesValidSequence() throws {
    var r = ChunkReassembler()
    let seq = chunks(of: #"{"type":"response","command":"get_messages","success":true}"#)
    var out: Data?
    for c in seq { out = try r.ingest(c) }
    #expect(out.map { String(decoding: $0, as: UTF8.self) }?.contains("get_messages") == true)
    #expect(!r.isReassembling)
}

@Test func rejectsInterleavedFrame() throws {
    var r = ChunkReassembler()
    _ = try r.ingest(chunks(of: "0123456789")[0])
    #expect(throws: ChunkError.interleaved) { try r.noteNonChunkFrame() }
    #expect(!r.isReassembling)  // violation resets to idle
}

@Test func rejectsOutOfOrder() throws {
    var r = ChunkReassembler()
    let seq = chunks(of: "0123456789ABCDEF")
    _ = try r.ingest(seq[0])
    #expect(throws: ChunkError.outOfOrder(expected: 1, got: 2)) { _ = try r.ingest(seq[2]) }
}

@Test func rejectsMidSequenceStart() {
    var r = ChunkReassembler()
    let seq = chunks(of: "0123456789")
    #expect(throws: ChunkError.invalidStart(index: 1)) { _ = try r.ingest(seq[1]) }
}

@Test func rejectsOversizedDeclaration() {
    var r = ChunkReassembler(maxReassembledBytes: 64)
    let c = RpcChunk(chunkId: "c", index: 0, count: 2, byteLength: 100, data: "")
    #expect(throws: ChunkError.tooLarge(byteLength: 100, cap: 64)) { _ = try r.ingest(c) }
}

@Test func rejectsLengthMismatch() throws {
    var r = ChunkReassembler()
    var seq = chunks(of: "0123456789")
    seq[seq.count - 1] = RpcChunk(chunkId: "rpc-1", index: seq.count - 1, count: seq.count,
                                  byteLength: 10, data: Data("XYZ!".utf8).base64EncodedString())
    for c in seq.dropLast() { _ = try r.ingest(c) }
    #expect(throws: ChunkError.lengthMismatch(declared: 10, actual: 12)) { _ = try r.ingest(seq.last!) }
}

@Test func rejectsInvalidUTF8() throws {
    var r = ChunkReassembler()
    let c = RpcChunk(chunkId: "u", index: 0, count: 1, byteLength: 2,
                     data: Data([0xFF, 0xFE]).base64EncodedString())
    #expect(throws: ChunkError.notUTF8) { _ = try r.ingest(c) }
}
```

(`RpcChunk` needs a memberwise `public init` — add it in this task.)

- [x] **Step 2: Run to verify failure** — `swift test 2>&1 | tail -5` — Expected: compile FAILS.

- [x] **Step 3: Implement** the state machine exactly per the rules above: internal state `(chunkId, count, byteLength, nextIndex, buffer: Data)?`; every throw path sets state to nil first. Strict UTF-8 check: `String(data:encoding:)` returning nil → `.notUTF8` (also reset).

- [x] **Step 4: Run tests** — `swift test` — Expected: PASS.

- [x] **Step 5: Commit** — `git add -A && git commit -m "feat: rpc_chunk reassembly state machine"`

---

### Task 4: Command encoding

**Files:**
- Create: `Sources/OmpKit/Wire/RpcCommand.swift`
- Test: `Tests/OmpKitTests/CommandEncodingTests.swift`

**Interfaces:**
- Consumes: `JSONValue`.
- Produces:
  ```swift
  public struct RpcCommand: Sendable {
      public let type: String
      public let fields: [String: JSONValue]   // everything except id/type
      public init(type: String, fields: [String: JSONValue])
      /// Serialize with an assigned request id: {"id":id,"type":type, ...fields}
      public func encodedLine(id: String) throws -> Data   // JSON + trailing \n

      // Factories for every command v1 uses (exact field names per docs/contracts/rpc-wire-contract.md):
      public static func negotiateProtocol(version: Int) -> RpcCommand      // negotiate_protocol, protocolVersion
      public static func getState() -> RpcCommand
      public static func prompt(message: String, streamingBehavior: StreamingBehavior?) -> RpcCommand
      public static func abort() -> RpcCommand
      public static func newSession(parentSession: String?) -> RpcCommand
      public static func switchSession(path: String) -> RpcCommand          // switch_session, sessionPath
      public static func getMessagesPage(cursor: String?, limit: Int?) -> RpcCommand
      public static func getMessages() -> RpcCommand
      public static func setModel(provider: String, modelId: String) -> RpcCommand
      public static func getAvailableModels() -> RpcCommand
      public static func setThinkingLevel(_ level: String) -> RpcCommand
      public static func compact(customInstructions: String?) -> RpcCommand
      public static func getSessionStats() -> RpcCommand
      public static func setSessionName(_ name: String) -> RpcCommand
      public static func setSubagentSubscription(level: SubagentSubscriptionLevel) -> RpcCommand
      public static func extensionUIResponse(id: String, body: [String: JSONValue]) -> RpcCommand
      // extension_ui_response is NOT an RpcCommand on the wire (no id echo); model it as a raw frame:
      // encodedLine(id:) must special-case type == "extension_ui_response" to omit the request id.
  }
  public enum StreamingBehavior: String, Sendable { case steer, followUp }
  public enum SubagentSubscriptionLevel: String, Sendable { case off, progress, events }
  ```
  Note: `StreamingBehavior.followUp` must encode as `"followUp"` (camelCase on the wire — rawValue already matches).

- [x] **Step 1: Write failing tests**

```swift
import Testing
import Foundation
@testable import OmpKit

private func json(_ data: Data) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: data.dropLast()) as! [String: Any]  // dropLast strips \n
}

@Test func encodesPromptWithBehavior() throws {
    let line = try RpcCommand.prompt(message: "hi", streamingBehavior: .followUp).encodedLine(id: "req_1")
    let obj = try json(line)
    #expect(obj["id"] as? String == "req_1")
    #expect(obj["type"] as? String == "prompt")
    #expect(obj["message"] as? String == "hi")
    #expect(obj["streamingBehavior"] as? String == "followUp")
    #expect(line.last == UInt8(ascii: "\n"))
}

@Test func omitsNilFields() throws {
    let obj = try json(try RpcCommand.prompt(message: "x", streamingBehavior: nil).encodedLine(id: "req_2"))
    #expect(obj["streamingBehavior"] == nil)
}

@Test func switchSessionUsesSessionPathKey() throws {
    let obj = try json(try RpcCommand.switchSession(path: "/tmp/s.jsonl").encodedLine(id: "req_3"))
    #expect(obj["type"] as? String == "switch_session")
    #expect(obj["sessionPath"] as? String == "/tmp/s.jsonl")
}

@Test func extensionUIResponseHasNoRequestId() throws {
    let cmd = RpcCommand.extensionUIResponse(id: "abc", body: ["confirmed": .bool(true)])
    let obj = try json(try cmd.encodedLine(id: "req_9"))
    #expect(obj["type"] as? String == "extension_ui_response")
    #expect(obj["id"] as? String == "abc")        // the UI request id, NOT req_9
    #expect(obj["confirmed"] as? Bool == true)
}
```

- [x] **Step 2: Run to verify failure** — `swift test 2>&1 | tail -5` — Expected: compile FAILS.
- [x] **Step 3: Implement.** Encode via `JSONValue.object` → `JSONEncoder` (sorted keys for determinism), append `\n`.
- [x] **Step 4: Run tests** — `swift test` — Expected: PASS.
- [x] **Step 5: Commit** — `git add -A && git commit -m "feat: RPC command encoding"`

---

### Task 5: Process transport + fake server fixture

**Files:**
- Create: `Sources/OmpKit/Wire/LineTransport.swift`, `Tests/OmpKitTests/Fixtures/fake_server.py`
- Test: `Tests/OmpKitTests/LineTransportTests.swift`

**Interfaces:**
- Consumes: nothing prior (pure byte transport; framing sits above).
- Produces:
  ```swift
  public actor LineTransport {
      public init(executable: String, arguments: [String],
                  currentDirectory: URL?, environment: [String: String]?)
      public func start() throws
      /// Newline-delimited stdout lines, ending when the process's stdout closes.
      public nonisolated var lines: AsyncStream<Data> { get }
      public func write(_ line: Data) throws          // throws TransportError.closed after exit
      public func stderrSnapshot() -> String           // bounded ring buffer, 512 chunks
      /// Graceful teardown: close stdin → wait 1.0 s → SIGTERM → wait 1.0 s → SIGKILL.
      public func shutdown() async
      public var exitStatus: Int32? { get }
      public nonisolated var onExit: AsyncStream<Int32> { get }
  }
  public enum TransportError: Error, Sendable { case closed, spawnFailed(String) }
  ```
  Line splitting: buffer stdout bytes, split on `\n` (strip a trailing `\r` if present), skip empty lines. Cap the line buffer at `maxFrameBytes + 64 KiB` slack; an unterminated line beyond that is discarded with a diagnostic (matches the reference's bounded behavior).

- [x] **Step 1: Write the fake server fixture** — `Tests/OmpKitTests/Fixtures/fake_server.py` (mirrors the reference suite's inline-Python approach; used by Tasks 5–6):

```python
#!/usr/bin/env python3
"""Scripted omp RPC stand-in. Modes via argv[1]:
  basic     — ready, negotiate ok, echoes get_state with canned data
  chunked   — get_state answered as a 3-part rpc_chunk sequence
  late-error— prompt acked ok, then error response with the same id
  silent    — ready, then never answers anything (timeout testing)
  noisy     — like basic, but emits unknown frames + setWidget before each response
"""
import json, sys, base64

mode = sys.argv[1] if len(sys.argv) > 1 else "basic"
W = sys.stdout

def emit(obj):
    W.write(json.dumps(obj) + "\n"); W.flush()

emit({"type": "ready", "protocolVersion": 1, "supportedProtocolVersions": [1, 2],
      "maxFrameBytes": 1048576, "maxReassembledFrameBytes": 67108864})
if mode == "noisy":
    emit({"type": "available_commands_update", "commands": []})
    emit({"type": "extension_ui_request", "id": "w1", "method": "setWidget", "widgetKey": "x"})

STATE = {"model": {"id": "fake", "provider": "test"}, "isStreaming": False,
         "sessionId": "fake-session", "sessionFile": "/tmp/fake.jsonl"}

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        cmd = json.loads(line)
    except json.JSONDecodeError:
        emit({"type": "response", "command": "parse", "success": False, "error": "malformed"})
        continue
    cid, ctype = cmd.get("id"), cmd.get("type")
    if mode == "silent" and ctype != "negotiate_protocol":
        continue
    if ctype == "negotiate_protocol":
        emit({"id": cid, "type": "response", "command": "negotiate_protocol",
              "success": True, "data": {"protocolVersion": 2}})
    elif ctype == "get_state":
        if mode == "noisy":
            emit({"type": "notice", "level": "info", "message": "before response", "source": "fake"})
        if mode == "chunked":
            payload = json.dumps({"id": cid, "type": "response", "command": "get_state",
                                  "success": True, "data": STATE}).encode()
            n = 3
            size = (len(payload) + n - 1) // n
            for i in range(n):
                part = payload[i * size:(i + 1) * size]
                emit({"type": "rpc_chunk", "chunkId": "ck1", "index": i, "count": n,
                      "byteLength": len(payload), "data": base64.b64encode(part).decode()})
        else:
            emit({"id": cid, "type": "response", "command": "get_state", "success": True, "data": STATE})
    elif ctype == "prompt":
        emit({"id": cid, "type": "response", "command": "prompt", "success": True,
              "data": {"agentInvoked": True}})
        if mode == "late-error":
            emit({"id": cid, "type": "response", "command": "prompt", "success": False,
                  "error": "late scheduling failure"})
        else:
            emit({"type": "agent_start"})
            emit({"type": "agent_end", "messages": [], "isTerminal": True})
    elif ctype == "bad_command_test":
        emit({"id": cid, "type": "response", "command": "bad_command_test",
              "success": False, "error": "nope", "code": "test_code"})
    else:
        emit({"id": cid, "type": "response", "command": ctype or "parse", "success": True})
```

- [x] **Step 2: Write failing transport tests**

```swift
import Testing
import Foundation
@testable import OmpKit

func fixtureURL(_ name: String) -> URL {
    Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
        ?? Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(name)")
}

func makeFakeTransport(mode: String) -> LineTransport {
    LineTransport(executable: "/usr/bin/env",
                  arguments: ["python3", fixtureURL("fake_server.py").path, mode],
                  currentDirectory: nil, environment: nil)
}

@Test func readsReadyLineAndShutsDown() async throws {
    let t = makeFakeTransport(mode: "basic")
    try await t.start()
    var it = t.lines.makeAsyncIterator()
    let first = await it.next()
    #expect(first.map { String(decoding: $0, as: UTF8.self) }?.contains(#""type":"ready""#) == true)
    await t.shutdown()
    #expect(await t.exitStatus != nil)
}

@Test func writeAfterExitThrowsClosed() async throws {
    let t = makeFakeTransport(mode: "basic")
    try await t.start()
    await t.shutdown()
    await #expect(throws: TransportError.closed) { try await t.write(Data("{}\n".utf8)) }
}
```

- [x] **Step 3: Run to verify failure** — `swift test 2>&1 | tail -5` — Expected: compile FAILS.
- [x] **Step 4: Implement** with `Foundation.Process` + `Pipe`; stdout read on `FileHandle.readabilityHandler` feeding a continuation; stderr into a 512-chunk ring. `shutdown()` per the documented sequence (`interrupt`/`terminate` map to SIGTERM; use `kill(pid, SIGKILL)` for the final escalation).
- [x] **Step 5: Run tests** — `swift test` — Expected: PASS.
- [x] **Step 6: Commit** — `git add -A && git commit -m "feat: process line transport with fake-server fixture"`

---

### Task 6: RpcClient actor

**Files:**
- Create: `Sources/OmpKit/RpcClient.swift`, `Sources/OmpKit/Wire/RpcErrors.swift`
- Test: `Tests/OmpKitTests/RpcClientTests.swift`

**Interfaces:**
- Consumes: `LineTransport`, `RpcFrame`, `ChunkReassembler`, `RpcCommand` (Tasks 2–5).
- Produces:
  ```swift
  public struct RpcClientConfiguration: Sendable {
      public var executable: String = "omp"          // resolved via PATH or absolute
      public var extraArguments: [String] = []       // appended after: --mode rpc --no-title
      public var cwd: URL?                            // the session's project directory — REQUIRED for real use
      public var resumeSessionPath: String?           // adds: -r <path>
      public var noSession: Bool = false              // adds: --no-session
      public var startupTimeout: Duration = .seconds(30)
      public var requestTimeout: Duration = .seconds(30)
      /// Test-only: when true, spawn arguments are extraArguments verbatim
      /// (no --mode rpc / --no-title / session flags prepended).
      public var rawArgv: Bool = false
  }
  public actor RpcClient {
      public init(configuration: RpcClientConfiguration)
      /// Spawn, await ready frame (startupTimeout), negotiate v2 when advertised.
      public func start() async throws -> ReadyFrame
      /// Send one command, await the matching response. success:false → RpcCommandError.
      @discardableResult
      public func send(_ command: RpcCommand, timeout: Duration? = nil) async throws -> RpcResponse
      /// Fire-and-forget frame (extension_ui_response) — no response expected.
      public func sendRaw(_ command: RpcCommand) async throws
      /// All non-response frames in arrival order: events, extension UI requests, notices…
      public nonisolated var events: AsyncStream<RpcFrame> { get }
      public func shutdown() async
      public private(set) var protocolErrors: [RpcProtocolError]   // bounded 128, unmatched error responses
      public func stderrSnapshot() async -> String
  }
  public enum RpcClientError: Error, Sendable {
      case timeout(command: String)
      case processExited(code: Int32?, stderrTail: String)
      case commandFailed(command: String, error: String, code: String?)   // == RpcCommandError
      case notStarted
  }
  public struct RpcProtocolError: Sendable { public let command: String?; public let requestId: String?; public let remoteError: String? }
  ```
  Argv construction: `[--mode, rpc, --no-title]` + (`--no-session` | `-r <resumeSessionPath>`) + extraArguments; spawn cwd = `configuration.cwd` (this is the workspace tools run in — spec's correctness requirement).
  Semantics ported from the reference (port-spec §1): request ids `req_1, req_2, …`; responses matched on `id`, never order; a matched `success:false` throws `commandFailed`; a response whose id matches a request already completed (the `late-error` case after an async ack) is recorded into `protocolErrors`, not thrown; chunk payloads reassembled then re-fed through `RpcFrame.decode`; every non-chunk frame calls `noteNonChunkFrame()` (chunk violations recorded as protocol errors, sequence dropped); transport EOF fails all pending requests with `processExited(code:stderrTail:)`.

- [x] **Step 1: Write failing tests (each mirrors a reference-suite behavior; fake server from Task 5)**

```swift
import Testing
import Foundation
@testable import OmpKit

func makeClient(mode: String) -> RpcClient {
    var cfg = RpcClientConfiguration()
    cfg.executable = "/usr/bin/env"
    cfg.extraArguments = ["python3", fixtureURL("fake_server.py").path, mode]
    cfg.rawArgv = true   // extraArguments become the full argv — no omp flags prepended
    cfg.noSession = true
    return RpcClient(configuration: cfg)
}

@Test func startNegotiatesV2() async throws {
    let c = makeClient(mode: "basic")
    let ready = try await c.start()
    #expect(ready.supportedProtocolVersions?.contains(2) == true)
    await c.shutdown()
}

@Test func getStateRoundTrip() async throws {
    let c = makeClient(mode: "basic")
    _ = try await c.start()
    let resp = try await c.send(.getState())
    #expect(resp.data?["sessionId"]?.stringValue == "fake-session")
    await c.shutdown()
}

@Test func chunkedResponseReassembles() async throws {
    let c = makeClient(mode: "chunked")
    _ = try await c.start()
    let resp = try await c.send(.getState())
    #expect(resp.data?["sessionId"]?.stringValue == "fake-session")
    await c.shutdown()
}

@Test func failureResponseThrowsCommandFailed() async throws {
    let c = makeClient(mode: "basic")
    _ = try await c.start()
    await #expect(throws: RpcClientError.self) {
        _ = try await c.send(RpcCommand(type: "bad_command_test", fields: [:]))
    }
    await c.shutdown()
}

@Test func lateErrorRecordedNotThrown() async throws {
    let c = makeClient(mode: "late-error")
    _ = try await c.start()
    let ack = try await c.send(.prompt(message: "x", streamingBehavior: nil))
    #expect(ack.success)
    try await Task.sleep(for: .milliseconds(300))   // let the late frame arrive
    let errors = await c.protocolErrors
    #expect(errors.count == 1)
    #expect(errors[0].remoteError == "late scheduling failure")
    await c.shutdown()
}

@Test func timeoutThrows() async throws {
    let c = makeClient(mode: "silent")
    _ = try await c.start()
    await #expect(throws: RpcClientError.self) {
        _ = try await c.send(.getState(), timeout: .milliseconds(200))
    }
    await c.shutdown()
}

@Test func unknownFramesFlowToEventsWithoutBreakingRequests() async throws {
    let c = makeClient(mode: "noisy")
    _ = try await c.start()
    let collector = Task { () -> [String] in
        var seen: [String] = []
        for await frame in c.events {
            if case .event(let type, _) = frame { seen.append(type) }
            if case .extensionUIRequest = frame { seen.append("extension_ui_request") }
            if seen.count >= 3 { break }
        }
        return seen
    }
    _ = try await c.send(.getState())
    let seen = await collector.value
    #expect(seen.contains("available_commands_update"))
    #expect(seen.contains("extension_ui_request"))
    #expect(seen.contains("notice"))
    await c.shutdown()
}

@Test func eofFailsPendingRequests() async throws {
    let c = makeClient(mode: "silent")
    _ = try await c.start()
    async let pending = c.send(.getState(), timeout: .seconds(10))
    try await Task.sleep(for: .milliseconds(100))
    await c.shutdown()   // closes stdin → fake exits → EOF
    await #expect(throws: RpcClientError.self) { _ = try await pending }
}
```

- [x] **Step 2: Run to verify failure** — `swift test 2>&1 | tail -5` — Expected: compile FAILS.
- [x] **Step 3: Implement.** One reader task consumes `transport.lines`: decode → chunk bookkeeping → route `.response` by id to waiting continuations (`[String: CheckedContinuation<RpcResponse, Error>]`), everything else into the events stream (buffered `AsyncStream`). Decode failures on a line: skip + diagnostic (recoverable). Timeouts via `Task` race helper. `start()` awaits the first `.ready` frame with `startupTimeout`, then `negotiate_protocol` if `supportedProtocolVersions` contains 2.
- [x] **Step 4: Run tests** — `swift test` — Expected: PASS.
- [x] **Step 5: Commit** — `git add -A && git commit -m "feat: RpcClient actor with correlation, chunking, error taxonomy"`

---

### Task 7: Integration smoke test against real omp

**Files:**
- Create: `Tests/OmpKitTests/IntegrationTests.swift`

**Interfaces:**
- Consumes: `RpcClient` (Task 6).
- Produces: the evidence gate — OmpKit verified against omp 18.0.4 itself.

- [x] **Step 1: Write the gated test**

```swift
import Testing
import Foundation
@testable import OmpKit

/// Runs only when OMPKIT_INTEGRATION=1 — needs `omp` on PATH. No model calls are made.
@Test(.enabled(if: ProcessInfo.processInfo.environment["OMPKIT_INTEGRATION"] == "1"))
func realOmpReadyStateRoundTrip() async throws {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ompkit-int-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    var cfg = RpcClientConfiguration()
    cfg.cwd = tmp
    cfg.noSession = true
    let c = RpcClient(configuration: cfg)
    let ready = try await c.start()
    #expect(ready.supportedProtocolVersions?.contains(2) == true)
    #expect(ready.maxFrameBytes == 1_048_576)

    let state = try await c.send(.getState(), timeout: .seconds(20))
    #expect(state.success)
    #expect(state.data?["sessionId"]?.stringValue?.isEmpty == false)
    #expect(state.data?["isStreaming"]?.boolValue == false)
    await c.shutdown()
}
```

- [x] **Step 2: Run it for real** — `OMPKIT_INTEGRATION=1 swift test --filter realOmpReadyStateRoundTrip`
Expected: PASS in under ~30 s. If it hangs: `omp --version` in the same shell first (PATH), and check `stderrSnapshot()` output in the failure message.
- [x] **Step 3: Run the full suite without the env var** — `swift test` — Expected: integration test SKIPPED, everything else PASS.
- [x] **Step 4: Commit** — `git add -A && git commit -m "test: integration smoke against real omp RPC"`

---

### Task 8: Session file parsing — title slot, header, entries

**Files:**
- Create: `Sources/OmpKit/Sessions/SessionFile.swift`, `Sources/OmpKit/Sessions/SessionEntry.swift`
- Test: `Tests/OmpKitTests/SessionFileTests.swift`

Contract: `docs/contracts/session-file-contract.md` §1 (quote-level authority — field names below are copied from it).

**Interfaces:**
- Consumes: `JSONValue`.
- Produces:
  ```swift
  public struct SessionTitleSlot: Sendable { public let title: String; public let source: String?; public let updatedAt: String }
  public struct SessionHeader: Sendable {
      public let id: String; public let cwd: String; public let timestamp: String
      public let version: Int?          // nil ⇒ v1
      public let title: String?         // AFTER slot folding (slot overrides; empty slot title clears)
      public let titleSource: String?
      public let parentSession: String? // PATH to parent file, not an id
  }
  public struct SessionEntryBase: Sendable { public let id: String; public let parentId: String?; public let timestamp: String }
  public enum SessionEntry: Sendable {
      case message(base: SessionEntryBase, message: JSONValue)      // AgentMessage stays raw until Plan 2
      case modelChange(base: SessionEntryBase, model: String)
      case thinkingLevelChange(base: SessionEntryBase, thinkingLevel: String?)
      case compaction(base: SessionEntryBase, summary: String, firstKeptEntryId: String)
      case labelEntry(base: SessionEntryBase, targetId: String, label: String?)
      case resetBoundary(base: SessionEntryBase)
      case unknown(type: String, base: SessionEntryBase, raw: JSONValue)  // the other 9 variants + future ones
      public var base: SessionEntryBase { get }
  }
  public struct ParsedSessionFile: Sendable {
      public let header: SessionHeader
      public let entries: [SessionEntry]
      public let malformedLineCount: Int
  }
  public enum SessionFileError: Error, Sendable { case invalidHeader, empty }

  public enum SessionFileParser {
      /// Full parse. Lenient: malformed interior lines skipped and counted;
      /// v1 files (no version) get synthetic ids chained in file order (migration §1.5).
      public static func parse(data: Data) throws -> ParsedSessionFile
      /// Header-only parse from the first 4096 bytes (list metadata; §5 of the contract).
      public static func parseHeader(prefix: Data) throws -> (slot: SessionTitleSlot?, header: SessionHeader)
  }
  ```
  Parsing rules (contract §1.2–1.3): line 1 MAY be the 256-byte slot — accept only `{type:"title", v:1, title, updatedAt, pad}`; otherwise it's the header. Header must be `type:"session"` with non-empty string `id`, else `invalidHeader`. Slot title overrides header title; empty slot title clears it. v1 migration: assign each entry `id = String(format: "gen-%06d", i)`, `parentId` = previous entry's id (pure chain).

- [x] **Step 1: Create fixtures + failing tests.** Fixture `Tests/OmpKitTests/Fixtures/session_v3.jsonl` — build it exactly like the real file observed on this machine (title slot line padded to exactly 256 bytes including newline, then):

```
{"type":"session","version":3,"id":"019f1feb-011a-7000-8ccc-3b1d8e69df68","timestamp":"2026-07-01T23:02:02.778Z","cwd":"/tmp"}
{"type":"model_change","id":"ba9a4190","parentId":null,"timestamp":"2026-07-01T23:02:02.962Z","model":"anthropic/claude-opus-4-8"}
{"type":"message","id":"aa11bb22","parentId":"ba9a4190","timestamp":"2026-07-01T23:03:00.000Z","message":{"role":"user","content":"hello"}}
{"type":"future_entry_kind","id":"cc33dd44","parentId":"aa11bb22","timestamp":"2026-07-01T23:03:01.000Z","mystery":true}
not json at all
{"type":"message","id":"ee55ff66","parentId":"cc33dd44","timestamp":"2026-07-01T23:04:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]}}
```

Generate the slot line in a test helper and prepend at load:

```swift
func makeTitleSlotLine(title: String) -> String {
    var pad = ""
    while true {
        let line = #"{"type":"title","v":1,"title":"\#(title)","source":"auto","updatedAt":"2026-07-01T23:07:41.244Z","pad":"\#(pad)"}"#
        let bytes = line.utf8.count + 1  // +1 for \n
        if bytes == 256 { return line }
        precondition(bytes < 256, "title too long for slot")
        pad += " "
    }
}

func fixtureSessionV3() -> Data {
    let body = try! String(contentsOf: fixtureURL("session_v3.jsonl"), encoding: .utf8)
    return Data((makeTitleSlotLine(title: "Fixture") + "\n" + body).utf8)
}
```

Tests:

```swift
@Test func parsesV3FileWithSlot() throws {
    let parsed = try SessionFileParser.parse(data: fixtureSessionV3())
    #expect(parsed.header.id == "019f1feb-011a-7000-8ccc-3b1d8e69df68")
    #expect(parsed.header.cwd == "/tmp")
    #expect(parsed.header.title == "Fixture")            // slot folded in
    #expect(parsed.entries.count == 4)                    // unknown kept, non-JSON skipped
    #expect(parsed.malformedLineCount == 1)
    guard case .unknown(let type, _, _) = parsed.entries[2] else { Issue.record("expected unknown"); return }
    #expect(type == "future_entry_kind")
}

@Test func headerOnlyParseFromPrefix() throws {
    let (slot, header) = try SessionFileParser.parseHeader(prefix: fixtureSessionV3().prefix(4096))
    #expect(slot?.title == "Fixture")
    #expect(header.cwd == "/tmp")
}

@Test func v1FileGetsSyntheticIdChain() throws {
    let v1 = Data("""
    {"type":"session","id":"old","timestamp":"2025-01-01T00:00:00Z","cwd":"/x"}
    {"type":"message","timestamp":"2025-01-01T00:01:00Z","message":{"role":"user","content":"a"}}
    {"type":"message","timestamp":"2025-01-01T00:02:00Z","message":{"role":"assistant","content":"b"}}
    """.utf8)
    let parsed = try SessionFileParser.parse(data: v1)
    #expect(parsed.entries[0].base.parentId == nil)
    #expect(parsed.entries[1].base.parentId == parsed.entries[0].base.id)
}

@Test func nonSessionFirstEntryIsInvalid() {
    #expect(throws: SessionFileError.invalidHeader) {
        _ = try SessionFileParser.parse(data: Data(#"{"type":"message","id":"x"}"#.utf8))
    }
}
```

- [x] **Step 2: Run to verify failure** — `swift test 2>&1 | tail -5` — Expected: compile FAILS.
- [x] **Step 3: Implement** per the contract sections cited above.
- [x] **Step 4: Run tests** — `swift test` — Expected: PASS.
- [x] **Step 5: Commit** — `git add -A && git commit -m "feat: session file parsing with title slot and lenient entries"`

---

### Task 9: Tree path reconstruction

**Files:**
- Create: `Sources/OmpKit/Sessions/SessionTree.swift`
- Test: `Tests/OmpKitTests/SessionTreeTests.swift`

**Interfaces:**
- Consumes: `SessionEntry`, `ParsedSessionFile` (Task 8).
- Produces:
  ```swift
  public enum SessionTree {
      /// Active path root→leaf. Leaf = last entry in file order (the persisted leaf).
      /// Walk leaf→root via parentId with a mandatory cycle guard; reverse. (Contract §2 pseudocode.)
      public static func activePath(of file: ParsedSessionFile) -> [SessionEntry]
      /// Entries hidden behind the newest compaction on the path (before firstKeptEntryId),
      /// so callers can collapse them behind its summary.
      public static func compactedPrefix(of path: [SessionEntry]) -> (hidden: ArraySlice<SessionEntry>, summary: String)?
  }
  ```

- [x] **Step 1: Write failing tests** — linear chain returns all entries in order; a branch (two entries sharing one parent) resolves to the file-order-last leaf's path only; a corrupt parent cycle terminates (cycle guard) instead of hanging; `compactedPrefix` returns the entries before `firstKeptEntryId` for the newest compaction entry on the path and nil when no compaction exists. Build entries inline with `SessionEntryBase(id:parentId:timestamp:)` — no fixtures needed. Test code follows the same `#expect` style as Task 8; the branch test is the load-bearing one:

```swift
func testHeader() -> SessionHeader {
    SessionHeader(id: "test", cwd: "/tmp", timestamp: "2026-01-01T00:00:00Z",
                  version: 3, title: nil, titleSource: nil, parentSession: nil)
}

@Test func branchResolvesToFileOrderLeaf() throws {
    // a ← b (first branch tip), a ← c (second tip, later in file) ⇒ path is [a, c]
    let a = SessionEntry.resetBoundary(base: .init(id: "a", parentId: nil, timestamp: "t1"))
    let b = SessionEntry.resetBoundary(base: .init(id: "b", parentId: "a", timestamp: "t2"))
    let c = SessionEntry.resetBoundary(base: .init(id: "c", parentId: "a", timestamp: "t3"))
    let file = ParsedSessionFile(header: testHeader(), entries: [a, b, c], malformedLineCount: 0)
    #expect(SessionTree.activePath(of: file).map(\.base.id) == ["a", "c"])
}
```

- [x] **Step 2: Run to verify failure** — Expected: compile FAILS.
- [x] **Step 3: Implement** (dictionary by id, walk with `seen` set, reverse).
- [x] **Step 4: Run tests** — `swift test` — Expected: PASS.
- [x] **Step 5: Commit** — `git add -A && git commit -m "feat: session tree active-path reconstruction"`

---

### Task 10: SessionLibrary — listing, status, watching

**Files:**
- Create: `Sources/OmpKit/Sessions/SessionLibrary.swift`, `Sources/OmpKit/Sessions/SessionStatus.swift`
- Test: `Tests/OmpKitTests/SessionLibraryTests.swift`

Contract: `docs/contracts/session-file-contract.md` §4–5.

**Interfaces:**
- Consumes: `SessionFileParser` (Task 8).
- Produces:
  ```swift
  public enum SessionStatus: String, Sendable { case complete, error, aborted, interrupted, pending, unknown }
  public struct SessionMetadata: Sendable, Identifiable {
      public var id: String { path }
      public let path: String            // absolute JSONL path
      public let sessionId: String
      public let cwd: String             // from header — bucket names are NOT decodable
      public let title: String?
      public let created: Date           // header timestamp
      public let modified: Date          // file mtime
      public let sizeBytes: Int
      public let status: SessionStatus
  }
  public actor SessionLibrary {
      /// root default: ~/.omp/agent/sessions
      public init(root: URL = FileManager.default.homeDirectoryForCurrentUser
          .appendingPathComponent(".omp/agent/sessions"))
      /// Depth-exactly-2 scan (bucket/*.jsonl), newest mtime first. Nested subagent files never surface.
      public func listAll() async -> [SessionMetadata]
      /// Re-scan signal on any change under root (DispatchSource on the root dir + per-bucket sources, coalesced 500 ms).
      public nonisolated var changes: AsyncStream<Void> { get }
  }
  ```
  Per-file scan (port of contract §4): read first **4096** bytes → `parseHeader` (tolerating a truncated second line by falling back to raw string-property extraction of `"id"`, `"cwd"`, `"timestamp"`); read last **32 768** bytes → walk lines backwards, skip any line not starting with `{` (drops the leading partial fragment), find last `"type":"message"` line and classify with this exact table:

  | last message | status |
  |---|---|
  | assistant, `stopReason == "error"` | `.error` |
  | assistant, `stopReason == "aborted"` | `.aborted` |
  | assistant, `stopReason == "length"` | `.interrupted` |
  | assistant with trailing `toolCall` blocks lacking results | `.interrupted` |
  | assistant otherwise | `.complete` |
  | toolResult | `.interrupted` |
  | user | `.pending` |
  | none found | `.unknown` |

  Memoize per path keyed on `(mtime, size)` **both matching** (title-slot rewrites keep size but bump mtime — cache must miss then). Unparseable files: skip, but cache the negative result under the same key.

- [x] **Step 1: Write failing tests**

```swift
import Testing
import Foundation
@testable import OmpKit

/// Writes a minimal session file whose LAST message line drives the status classifier.
func writeSession(at url: URL, id: String, cwd: String, lastMessage: String) throws {
    let content = """
    {"type":"session","version":3,"id":"\(id)","timestamp":"2026-01-01T00:00:00Z","cwd":"\(cwd)"}
    \(lastMessage)
    """
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(content.utf8).write(to: url)
}

let userLast = #"{"type":"message","id":"m1","parentId":null,"timestamp":"t","message":{"role":"user","content":"q"}}"#
let abortedLast = #"{"type":"message","id":"m1","parentId":null,"timestamp":"t","message":{"role":"assistant","stopReason":"aborted","content":"x"}}"#
let completeLast = #"{"type":"message","id":"m1","parentId":null,"timestamp":"t","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}"#

@Test func listsSortsAndClassifies() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lib-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let b1 = root.appendingPathComponent("-proj-a"), b2 = root.appendingPathComponent("-proj-b")
    try writeSession(at: b1.appendingPathComponent("2026-01-01T00-00-00-000Z_s1.jsonl"), id: "s1", cwd: "/tmp/a", lastMessage: userLast)
    try writeSession(at: b1.appendingPathComponent("2026-01-02T00-00-00-000Z_s2.jsonl"), id: "s2", cwd: "/tmp/a", lastMessage: abortedLast)
    try writeSession(at: b2.appendingPathComponent("2026-01-03T00-00-00-000Z_s3.jsonl"), id: "s3", cwd: "/tmp/b", lastMessage: completeLast)
    // Depth-3 nested subagent transcript must NOT appear:
    try writeSession(at: b1.appendingPathComponent("2026-01-01T00-00-00-000Z_s1/sub.jsonl"), id: "sub", cwd: "/tmp/a", lastMessage: userLast)

    let lib = SessionLibrary(root: root)
    let all = await lib.listAll()
    #expect(all.count == 3)
    #expect(all.map(\.sessionId).contains("sub") == false)
    #expect(all.first?.modified == all.map(\.modified).max())   // mtime desc
    let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.sessionId, $0) })
    #expect(byId["s1"]?.status == .pending)
    #expect(byId["s2"]?.status == .aborted)
    #expect(byId["s3"]?.status == .complete)
    #expect(byId["s1"]?.cwd == "/tmp/a")   // from header, not the bucket name
}

@Test func watcherSignalsOnNewFile() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("watch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let lib = SessionLibrary(root: root)
    _ = await lib.listAll()
    let signal = Task { await lib.changes.first { _ in true } }
    try await Task.sleep(for: .milliseconds(100))
    try writeSession(at: root.appendingPathComponent("-x/2026-01-01T00-00-00-000Z_n1.jsonl"),
                     id: "n1", cwd: "/x", lastMessage: userLast)
    let got = await withTaskGroup(of: Bool.self) { group in
        group.addTask { await signal.value != nil }
        group.addTask { try? await Task.sleep(for: .seconds(2)); return false }
        let first = await group.next()!; group.cancelAll(); return first
    }
    #expect(got)
}
```

Also add a cache-invalidation test: list once, rewrite the file's title-slot bytes in place (same size, mtime bumps), list again → the new title appears (proves the `(mtime, size)` cache key misses on mtime change). Use `FileHandle(forWritingTo:)` + `write(contentsOf:)` at offset 0 with a regenerated 256-byte slot from Task 8's `makeTitleSlotLine`.
- [x] **Step 2: Run to verify failure** — Expected: compile FAILS.
- [x] **Step 3: Implement.**
- [x] **Step 4: Run tests** — `swift test` — Expected: PASS.
- [x] **Step 5: Commit** — `git add -A && git commit -m "feat: session library listing with status and change watching"`

---

### Task 11: Bucket encoding + SessionProcessManager

**Files:**
- Create: `Sources/OmpKit/Sessions/SessionPathEncoding.swift`, `Sources/OmpKit/SessionProcessManager.swift`
- Test: `Tests/OmpKitTests/PathEncodingTests.swift`, `Tests/OmpKitTests/ProcessManagerTests.swift`

**Interfaces:**
- Consumes: `RpcClient`, `RpcClientConfiguration` (Task 6).
- Produces:
  ```swift
  public enum SessionPathEncoding {
      /// ENCODE-ONLY port of getDefaultSessionDirName (contract §3). Decoding is impossible by design;
      /// consumers read the header's cwd. Canonicalize symlinks (resolvingSymlinksInPath) before classifying.
      public static func bucketName(forCwd cwd: String,
                                    home: String = NSHomeDirectory(),
                                    tmp: String = NSTemporaryDirectory()) -> String
  }
  public actor SessionProcessManager {
      public init(clientFactory: @Sendable (RpcClientConfiguration) -> RpcClient = { RpcClient(configuration: $0) })
      public struct Handle: Sendable { public let sessionPath: String; public let client: RpcClient }
      /// Spawn `omp --mode rpc --no-title -r <path>` with cwd = the session header's cwd. Idempotent per path.
      public func open(sessionPath: String, cwd: String) async throws -> Handle
      /// New session in a project dir: spawns without -r, cwd = projectDirectory.
      public func openNew(projectDirectory: String) async throws -> Handle
      public func close(sessionPath: String) async     // shutdown + remove
      public func closeAll() async
      /// Exit notifications for sessions that died without close() — the UI's crash banner feed.
      public nonisolated var unexpectedExits: AsyncStream<(sessionPath: String, code: Int32?, stderrTail: String)> { get }
  }
  ```
  Encoding rules to port verbatim (contract §3): home-relative → `"-" + rel` with `/ \ :` each replaced by `-` (home itself = `"-"`); tmp-relative → `"-tmp"` prefix same replacement; otherwise `"--" + abs-minus-leading-slash with separators replaced + "--"`.

- [x] **Step 1: Write failing tests**

```swift
@Test func encodesHomeRelative() {
    #expect(SessionPathEncoding.bucketName(forCwd: "/Users/me/CS Projects/foo",
        home: "/Users/me", tmp: "/tmp/t") == "-CS Projects-foo")
}
@Test func encodesHomeItself() {
    #expect(SessionPathEncoding.bucketName(forCwd: "/Users/me", home: "/Users/me", tmp: "/tmp/t") == "-")
}
@Test func encodesTmp() {
    #expect(SessionPathEncoding.bucketName(forCwd: "/tmp/t/x", home: "/Users/me", tmp: "/tmp/t") == "-tmp-x")
}
@Test func encodesAbsolute() {
    #expect(SessionPathEncoding.bucketName(forCwd: "/Volumes/X/repo",
        home: "/Users/me", tmp: "/tmp/t") == "--Volumes-X-repo--")
}
```

Process-manager tests reuse the Task 6 fake server through the factory:

```swift
@Test func openIsIdempotentPerPath() async throws {
    let mgr = SessionProcessManager(clientFactory: { cfg in
        var c = cfg
        c.executable = "/usr/bin/env"
        c.extraArguments = ["python3", fixtureURL("fake_server.py").path, "basic"]
        c.rawArgv = true
        return RpcClient(configuration: c)   // rawArgv path, as in Task 6
    })
    let h1 = try await mgr.open(sessionPath: "/tmp/s.jsonl", cwd: "/tmp")
    let h2 = try await mgr.open(sessionPath: "/tmp/s.jsonl", cwd: "/tmp")
    #expect(h1.client === h2.client)
    await mgr.closeAll()
}

@Test func unexpectedExitIsSurfaced() async throws {
    let mgr = SessionProcessManager(clientFactory: { cfg in
        var c = cfg
        c.executable = "/usr/bin/env"
        c.extraArguments = ["python3", fixtureURL("fake_server.py").path, "basic"]
        c.rawArgv = true
        return RpcClient(configuration: c)
    })
    let h = try await mgr.open(sessionPath: "/tmp/dies.jsonl", cwd: "/tmp")
    let exitEvent = Task { await mgr.unexpectedExits.first { _ in true } }
    await h.client.shutdown()   // dies behind the manager's back
    let got = await withTaskGroup(of: Bool.self) { group in
        group.addTask { await exitEvent.value != nil }
        group.addTask { try? await Task.sleep(for: .seconds(2)); return false }
        let first = await group.next()!; group.cancelAll(); return first
    }
    #expect(got)
}
```

(`Handle.client ===` requires `RpcClient` to be a class-like reference — actors are; `#expect(h1.client === h2.client)` compiles with actors.)

- [x] **Step 2: Run to verify failure** — Expected: compile FAILS.
- [x] **Step 3: Implement.**
- [x] **Step 4: Run full suite** — `swift test` — Expected: ALL tests PASS.
- [x] **Step 5: Update `docs/contracts/` provenance** — append to each contract doc's header comment: `Verified against OmpKit tests <today's date>.`
- [x] **Step 6: Commit** — `git add -A && git commit -m "feat: bucket encoding and session process manager"`

---

## Done criteria (gate to Plan 2)

- `swift test` green; `OMPKIT_INTEGRATION=1 swift test` green against omp 18.0.4 on this machine.
- Evidence attached per `verifying-work`: full test output + the integration test's real `get_state` payload.
- Plan 2 (app shell: NavigationSplitView, transcript reducer, composer, generic tool card, extension-UI dialogs, Bauhaus token layer) is written only after this gate passes, against `docs/contracts/event-stream-reference.md`.

Deliberately deferred to Plan 2 (documented so they aren't mistaken for gaps): the `get_messages_page` drain-with-fallback helper (`session_busy`/`stale_cursor` → legacy snapshot, per port-spec constants), typed extension-UI request accessors, and typed `AgentSessionEvent` decoding — all sit on top of the raw `JSONValue` payloads OmpKit already surfaces.
