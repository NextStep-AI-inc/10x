import Testing
import Foundation
@testable import OmpKit

private func chunks(of payload: String, id: String = "rpc-1", size: Int = 4) -> [RpcChunk] {
    let bytes = Array(payload.utf8)
    let parts = stride(from: 0, to: bytes.count, by: size).map {
        Array(bytes[$0..<min($0 + size, bytes.count)])
    }
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
    #expect(throws: ChunkError.lengthMismatch(declared: 10, actual: 12)) { _ = try r.ingest(seq[seq.count - 1]) }
}

@Test func rejectsInvalidUTF8() throws {
    var r = ChunkReassembler()
    let c = RpcChunk(chunkId: "u", index: 0, count: 1, byteLength: 2,
                     data: Data([0xFF, 0xFE]).base64EncodedString())
    #expect(throws: ChunkError.notUTF8) { _ = try r.ingest(c) }
}

@Test func rejectsMismatchedChunkId() throws {
    var r = ChunkReassembler()
    let seq = chunks(of: "0123456789ABCDEF")
    _ = try r.ingest(seq[0])
    let impostor = RpcChunk(chunkId: "other", index: 1, count: seq.count,
                            byteLength: 16, data: seq[1].data)
    #expect(throws: ChunkError.mismatchedSequence(field: "chunkId")) { _ = try r.ingest(impostor) }
}

@Test func rejectsInvalidCount() {
    var r = ChunkReassembler()
    let c = RpcChunk(chunkId: "c", index: 0, count: 0, byteLength: 4, data: "aGk=")
    #expect(throws: ChunkError.invalidCount(0)) { _ = try r.ingest(c) }
}

@Test func rejectsBadBase64() {
    var r = ChunkReassembler()
    let c = RpcChunk(chunkId: "c", index: 0, count: 1, byteLength: 4, data: "not!valid!base64")
    #expect(throws: ChunkError.badBase64) { _ = try r.ingest(c) }
}

@Test func nonChunkFrameWhenIdleIsFine() throws {
    var r = ChunkReassembler()
    try r.noteNonChunkFrame()
    #expect(!r.isReassembling)
}

@Test func singleChunkSequenceCompletesImmediately() throws {
    var r = ChunkReassembler()
    let payload = #"{"ok":true}"#
    let c = RpcChunk(chunkId: "solo", index: 0, count: 1, byteLength: payload.utf8.count,
                     data: Data(payload.utf8).base64EncodedString())
    let out = try r.ingest(c)
    #expect(out.map { String(decoding: $0, as: UTF8.self) } == payload)
    #expect(!r.isReassembling)
}

@Test func recoversAfterViolation() throws {
    var r = ChunkReassembler()
    let seq = chunks(of: "0123456789ABCDEF")
    _ = try r.ingest(seq[0])
    #expect(throws: ChunkError.self) { _ = try r.ingest(seq[2]) }   // aborts the sequence
    // A fresh sequence must still work after the reset.
    var out: Data?
    for c in chunks(of: "fresh payload here") { out = try r.ingest(c) }
    #expect(out.map { String(decoding: $0, as: UTF8.self) } == "fresh payload here")
}
