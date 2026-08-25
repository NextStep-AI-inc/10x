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
    case badBase64
    case lengthMismatch(declared: Int, actual: Int)
    case notUTF8
}

/// Reassembles `rpc_chunk` sequences into whole frames (protocol v2).
///
/// omp emits oversized stdout objects as an uninterrupted run of base64 chunks.
/// The run must arrive contiguously and in order; any deviation is a protocol
/// violation rather than something to repair, so every check resets to idle.
public struct ChunkReassembler: Sendable {
    private struct Sequence {
        let chunkId: String
        let count: Int
        let byteLength: Int
        var nextIndex: Int
        var buffer: Data
    }

    private let maxReassembledBytes: Int
    private var sequence: Sequence?

    public init(maxReassembledBytes: Int = 67_108_864) {
        self.maxReassembledBytes = maxReassembledBytes
    }

    public var isReassembling: Bool { sequence != nil }

    /// Feeds one chunk. Returns the completed payload on the final chunk of a
    /// sequence, `nil` while more are expected.
    public mutating func ingest(_ chunk: RpcChunk) throws -> Data? {
        do {
            return try ingestChecked(chunk)
        } catch {
            sequence = nil
            throw error
        }
    }

    /// Must be called for every non-chunk frame: a sequence in flight may not be
    /// interrupted by other output.
    public mutating func noteNonChunkFrame() throws {
        guard sequence == nil else {
            sequence = nil
            throw ChunkError.interleaved
        }
    }

    private mutating func ingestChecked(_ chunk: RpcChunk) throws -> Data? {
        if sequence == nil {
            guard chunk.index == 0 else { throw ChunkError.invalidStart(index: chunk.index) }
            guard chunk.count >= 1 else { throw ChunkError.invalidCount(chunk.count) }
            guard chunk.byteLength >= 0, chunk.byteLength <= maxReassembledBytes else {
                throw ChunkError.tooLarge(byteLength: chunk.byteLength, cap: maxReassembledBytes)
            }
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
        guard let decoded = Data(base64Encoded: chunk.data) else { throw ChunkError.badBase64 }

        current.buffer.append(decoded)
        current.nextIndex += 1
        sequence = current

        guard current.nextIndex == current.count else { return nil }

        guard current.buffer.count == current.byteLength else {
            throw ChunkError.lengthMismatch(
                declared: current.byteLength, actual: current.buffer.count)
        }
        guard String(data: current.buffer, encoding: .utf8) != nil else {
            throw ChunkError.notUTF8
        }
        sequence = nil
        return current.buffer
    }
}
