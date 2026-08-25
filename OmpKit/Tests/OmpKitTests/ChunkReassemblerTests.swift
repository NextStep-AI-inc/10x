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

private func testReassembler(
    maxReassembledBytes: Int = 1_024,
    maxChunkPayloadBytes: Int = 256,
    maxChunkCount: Int = 256
) -> ChunkReassembler {
    ChunkReassembler(
        minimumReassembledBytes: 0,
        maxReassembledBytes: maxReassembledBytes,
        maxChunkPayloadBytes: maxChunkPayloadBytes,
        maxChunkCount: maxChunkCount)
}

@Test func reassemblesValidSequence() throws {
    var r = testReassembler()
    let seq = chunks(of: #"{"type":"response","command":"get_messages","success":true}"#)
    var out: Data?
    for c in seq { out = try r.ingest(c) }
    #expect(out.map { String(decoding: $0, as: UTF8.self) }?.contains("get_messages") == true)
    #expect(!r.isReassembling)
}

@Test func rejectsInterleavedFrame() throws {
    var r = testReassembler()
    _ = try r.ingest(chunks(of: "0123456789")[0])
    #expect(throws: ChunkError.interleaved) { try r.noteNonChunkFrame() }
    #expect(r.isReassembling)  // terminal violations leave the decoder poisoned
}

@Test func rejectsOutOfOrder() throws {
    var r = testReassembler()
    let seq = chunks(of: "0123456789ABCDEF")
    _ = try r.ingest(seq[0])
    #expect(throws: ChunkError.outOfOrder(expected: 1, got: 2)) { _ = try r.ingest(seq[2]) }
}

@Test func rejectsMidSequenceStart() {
    var r = testReassembler()
    let seq = chunks(of: "0123456789")
    #expect(throws: ChunkError.invalidStart(index: 1)) { _ = try r.ingest(seq[1]) }
}

@Test func rejectsOversizedDeclaration() {
    var r = testReassembler(maxReassembledBytes: 64)
    let c = RpcChunk(chunkId: "c", index: 0, count: 2, byteLength: 100, data: "eA==")
    #expect(throws: ChunkError.tooLarge(byteLength: 100, cap: 64)) { _ = try r.ingest(c) }
}

@Test func rejectsLengthMismatch() throws {
    var r = testReassembler()
    let seq = [
        RpcChunk(chunkId: "rpc-1", index: 0, count: 2, byteLength: 10,
                 data: Data("0123".utf8).base64EncodedString()),
        RpcChunk(chunkId: "rpc-1", index: 1, count: 2, byteLength: 10,
                 data: Data("4567".utf8).base64EncodedString()),
    ]
    _ = try r.ingest(seq[0])
    #expect(throws: ChunkError.lengthMismatch(declared: 10, actual: 8)) {
        _ = try r.ingest(seq[1])
    }
}

@Test func rejectsInvalidUTF8() throws {
    var r = testReassembler()
    let chunks = [
        RpcChunk(chunkId: "u", index: 0, count: 2, byteLength: 2,
                 data: Data([0xFF]).base64EncodedString()),
        RpcChunk(chunkId: "u", index: 1, count: 2, byteLength: 2,
                 data: Data([0xFE]).base64EncodedString()),
    ]
    _ = try r.ingest(chunks[0])
    #expect(throws: ChunkError.notUTF8) { _ = try r.ingest(chunks[1]) }
}

@Test func rejectsMismatchedChunkId() throws {
    var r = testReassembler()
    let seq = chunks(of: "0123456789ABCDEF")
    _ = try r.ingest(seq[0])
    let impostor = RpcChunk(chunkId: "other", index: 1, count: seq.count,
                            byteLength: 16, data: seq[1].data)
    #expect(throws: ChunkError.mismatchedSequence(field: "chunkId")) { _ = try r.ingest(impostor) }
}

@Test func rejectsInvalidCount() {
    var r = testReassembler()
    let c = RpcChunk(chunkId: "c", index: 0, count: 0, byteLength: 4, data: "aGk=")
    #expect(throws: ChunkError.invalidCount(0)) { _ = try r.ingest(c) }
}

@Test func rejectsBadBase64() {
    var r = testReassembler()
    let c = RpcChunk(chunkId: "c", index: 0, count: 2, byteLength: 4, data: "not!valid!base64")
    #expect(throws: ChunkError.badBase64) { _ = try r.ingest(c) }
}

@Test func nonChunkFrameWhenIdleIsFine() throws {
    var r = ChunkReassembler()
    try r.noteNonChunkFrame()
    #expect(!r.isReassembling)
}

@Test func singleChunkSequenceIsRejected() throws {
    var r = testReassembler()
    let payload = #"{"ok":true}"#
    let c = RpcChunk(chunkId: "solo", index: 0, count: 1, byteLength: payload.utf8.count,
                     data: Data(payload.utf8).base64EncodedString())
    #expect(throws: ChunkError.invalidCount(1)) { _ = try r.ingest(c) }
}

@Test func violationPoisonsTheOpenSequence() throws {
    var r = testReassembler()
    let seq = chunks(of: "0123456789ABCDEF")
    _ = try r.ingest(seq[0])
    #expect(throws: ChunkError.self) { _ = try r.ingest(seq[2]) }
    #expect(r.isReassembling)
}

@Test func rejectsContractInvalidMetadata() {
    var r = ChunkReassembler()
    let small = RpcChunk(chunkId: "rpc-1", index: 0, count: 2, byteLength: 10,
                         data: Data("hello".utf8).base64EncodedString())
    #expect(throws: ChunkError.self) { _ = try r.ingest(small) }

    var bounded = testReassembler(maxChunkCount: 2)
    let tooMany = RpcChunk(chunkId: "rpc-1", index: 0, count: 3, byteLength: 12,
                           data: Data("four".utf8).base64EncodedString())
    #expect(throws: ChunkError.invalidCount(3)) { _ = try bounded.ingest(tooMany) }

    var indexed = testReassembler()
    let badIndex = RpcChunk(chunkId: "rpc-1", index: 2, count: 2, byteLength: 8,
                            data: Data("four".utf8).base64EncodedString())
    #expect(throws: ChunkError.self) { _ = try indexed.ingest(badIndex) }
}

@Test func rejectsEmptyNonCanonicalAndOversizedPayloads() {
    var empty = testReassembler()
    let emptyChunk = RpcChunk(chunkId: "rpc-1", index: 0, count: 2, byteLength: 4, data: "")
    #expect(throws: ChunkError.badBase64) { _ = try empty.ingest(emptyChunk) }

    var nonCanonical = testReassembler()
    let nonCanonicalChunk = RpcChunk(
        chunkId: "rpc-1", index: 0, count: 2, byteLength: 4, data: "Zh==")
    #expect(throws: ChunkError.badBase64) { _ = try nonCanonical.ingest(nonCanonicalChunk) }

    var oversized = testReassembler(maxChunkPayloadBytes: 3)
    let oversizedChunk = RpcChunk(
        chunkId: "rpc-1", index: 0, count: 2, byteLength: 8,
        data: Data("four".utf8).base64EncodedString())
    #expect(throws: ChunkError.payloadTooLarge(bytes: 4, cap: 3)) {
        _ = try oversized.ingest(oversizedChunk)
    }
}

@Test func rejectsRunningByteOverrunImmediately() throws {
    var r = testReassembler()
    let first = RpcChunk(
        chunkId: "rpc-1", index: 0, count: 2, byteLength: 3,
        data: Data("four".utf8).base64EncodedString())
    #expect(throws: ChunkError.overrun(received: 4, declared: 3)) {
        _ = try r.ingest(first)
    }
}
