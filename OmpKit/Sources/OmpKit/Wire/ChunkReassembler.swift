import Foundation

/// Protocol violations in a chunked frame sequence. Every case aborts the
/// in-flight sequence — a partially reassembled frame is never delivered.
public enum ChunkError: Error, Equatable, Sendable {
    case invalidStart(index: Int)
    case mismatchedSequence(field: String)
    case outOfOrder(expected: Int, got: Int)
    case interleaved
    case tooLarge(byteLength: Int, cap: Int)
    case invalidCount(Int)
    case invalidIndex(Int)
    case invalidByteLength(Int)
    case badBase64
    case lengthMismatch(declared: Int, actual: Int)
    case notUTF8
    case invalidChunkId
    /// One chunk's decoded payload exceeded the per-chunk transport limit.
    case payloadTooLarge(bytes: Int, cap: Int)
    /// Accumulated bytes passed the declared total before the sequence ended.
    case overrun(received: Int, declared: Int)
}

/// Reassembles `rpc_chunk` sequences into whole frames (protocol v2).
///
/// omp emits oversized stdout objects as an uninterrupted run of base64 chunks.
/// The run must arrive contiguously and in order; any deviation is a protocol
/// violation rather than something to repair. The owning client treats every
/// violation as terminal, so an open sequence stays poisoned after a failure.
public struct ChunkReassembler: Sendable {
    private struct Sequence {
        let chunkId: String
        let count: Int
        let byteLength: Int
        var nextIndex: Int
        var buffer: Data
    }

    /// omp's advertised transport limits.
    public static let maxPhysicalFrameBytes = 1_048_576
    public static let maxReassembledFrameBytes = 67_108_864
    public static let chunkPayloadBytes = 262_144
    /// ceil(maxReassembled / chunkPayload)
    public static let maxChunkCount = 256

    private let minimumReassembledBytes: Int
    private let maxReassembledBytes: Int
    private let maxChunkPayloadBytes: Int
    private let maxChunkCount: Int
    private var sequence: Sequence?

    /// Defaults mirror omp's transport limits. Tests override them to exercise
    /// the same rules on small payloads.
    public init(maxReassembledBytes: Int = ChunkReassembler.maxReassembledFrameBytes) {
        self.init(
            minimumReassembledBytes: ChunkReassembler.maxPhysicalFrameBytes,
            maxReassembledBytes: maxReassembledBytes,
            maxChunkPayloadBytes: ChunkReassembler.chunkPayloadBytes,
            maxChunkCount: ChunkReassembler.maxChunkCount)
    }

    init(
        minimumReassembledBytes: Int,
        maxReassembledBytes: Int,
        maxChunkPayloadBytes: Int,
        maxChunkCount: Int
    ) {
        self.minimumReassembledBytes = minimumReassembledBytes
        self.maxReassembledBytes = maxReassembledBytes
        self.maxChunkPayloadBytes = maxChunkPayloadBytes
        self.maxChunkCount = maxChunkCount
    }

    public var isReassembling: Bool { sequence != nil }

    /// Feeds one chunk. Returns the completed payload on the final chunk of a
    /// sequence, `nil` while more are expected.
    public mutating func ingest(_ chunk: RpcChunk) throws -> Data? {
        try ingestChecked(chunk)
    }

    /// Must be called for every non-chunk frame: a sequence in flight may not be
    /// interrupted by other output.
    public mutating func noteNonChunkFrame() throws {
        guard sequence == nil else {
            throw ChunkError.interleaved
        }
    }

    private mutating func ingestChecked(_ chunk: RpcChunk) throws -> Data? {
        guard !chunk.chunkId.isEmpty, chunk.chunkId.utf16.count <= 128 else {
            throw ChunkError.invalidChunkId
        }
        guard chunk.count >= 2, chunk.count <= maxChunkCount else {
            throw ChunkError.invalidCount(chunk.count)
        }
        guard chunk.index >= 0, chunk.index < chunk.count else {
            throw ChunkError.invalidIndex(chunk.index)
        }
        guard chunk.byteLength >= minimumReassembledBytes else {
            throw ChunkError.invalidByteLength(chunk.byteLength)
        }
        guard chunk.byteLength <= maxReassembledBytes else {
            throw ChunkError.tooLarge(byteLength: chunk.byteLength, cap: maxReassembledBytes)
        }
        guard !chunk.data.isEmpty,
              let decoded = Data(base64Encoded: chunk.data),
              decoded.base64EncodedString() == chunk.data
        else { throw ChunkError.badBase64 }
        guard decoded.count <= maxChunkPayloadBytes else {
            throw ChunkError.payloadTooLarge(bytes: decoded.count, cap: maxChunkPayloadBytes)
        }

        if sequence == nil {
            guard chunk.index == 0 else { throw ChunkError.invalidStart(index: chunk.index) }
            sequence = Sequence(
                chunkId: chunk.chunkId, count: chunk.count, byteLength: chunk.byteLength,
                nextIndex: 0, buffer: Data())
        }

        guard var current = sequence else { return nil }
        guard chunk.chunkId == current.chunkId else {
            throw ChunkError.mismatchedSequence(field: "chunkId")
        }
        guard chunk.count == current.count else {
            throw ChunkError.mismatchedSequence(field: "count")
        }
        guard chunk.byteLength == current.byteLength else {
            throw ChunkError.mismatchedSequence(field: "byteLength")
        }
        guard chunk.index == current.nextIndex else {
            throw ChunkError.outOfOrder(expected: current.nextIndex, got: chunk.index)
        }
        current.buffer.append(decoded)
        // Check the running total, not just the final size: otherwise a lying
        // sequence can buffer without bound before the last chunk arrives.
        guard current.buffer.count <= current.byteLength else {
            throw ChunkError.overrun(
                received: current.buffer.count, declared: current.byteLength)
        }
        current.nextIndex += 1
        sequence = current

        guard current.nextIndex == current.count else { return nil }

        guard current.buffer.count == current.byteLength else {
            throw ChunkError.lengthMismatch(
                declared: current.byteLength, actual: current.buffer.count)
        }
        sequence = nil
        guard String(data: current.buffer, encoding: .utf8) != nil else {
            throw ChunkError.notUTF8
        }
        return current.buffer
    }
}
