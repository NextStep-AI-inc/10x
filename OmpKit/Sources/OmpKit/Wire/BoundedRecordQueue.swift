import Foundation

/// Budgets for one `BoundedRecordQueue`.
///
/// `memoryBytes` counts encoded record bytes, not the decoded values that sit
/// beside them, so the number is a floor on what a backlog costs rather than an
/// exact heap figure. The defaults are the per-queue budgets documented in
/// `docs/performance/2026-09-04-resource-usage.md`.
struct BoundedRecordQueueLimits: Sendable, Equatable {
    /// Encoded bytes held in memory before newer records spill to disk.
    var memoryBytes: Int
    /// Records held in memory regardless of size, so bookkeeping stays bounded.
    var memoryRecords: Int
    /// Physical bytes the spill file may occupy. Reaching it is a hard failure
    /// rather than a drop: the owner tears the runtime down and says why.
    var spillBytes: Int

    static let transport = BoundedRecordQueueLimits(
        memoryBytes: 4 * 1_048_576,
        memoryRecords: 1_024,
        spillBytes: 64 * 1_048_576)
}

enum BoundedRecordQueueError: Error, Equatable, Sendable {
    /// The spill store is full: the producer outran the consumer for longer
    /// than the storage budget allows.
    case backlogExceeded(queuedBytes: Int, limitBytes: Int)
    /// The spill file could not be created, written, or read back.
    case spillFailed(String)
    /// A spilled record did not decode when it was read back.
    case corruptRecord(String)
}

/// Bounded-memory FIFO between one synchronous producer and one asynchronous
/// consumer, preserving every record.
///
/// Records live in memory up to `limits.memoryBytes`; anything beyond that is
/// appended to a private, already-unlinked temporary file and read back in
/// order once the in-memory prefix drains. The file is capped at
/// `limits.spillBytes`; a record that would cross the cap fails `enqueue` with
/// `backlogExceeded` instead of being dropped, so the owner can fail loudly.
///
/// FIFO is kept by a simple invariant: once anything has spilled, every newer
/// record spills too, until the file is fully consumed and truncated. The one
/// record at the head of an otherwise empty queue may exceed the memory budget
/// transiently; only records queued behind others must fit the budget.
final class BoundedRecordQueue<Payload: Sendable>: @unchecked Sendable {
    typealias Decode = @Sendable (Data) throws -> Payload

    struct Metrics: Equatable, Sendable {
        var memoryBytes = 0
        var memoryRecords = 0
        var spilledBytes = 0
        var spilledRecords = 0
        var spillFileBytes = 0
        var peakMemoryBytes = 0
        var peakSpillFileBytes = 0
        var totalSpilledRecords = 0
    }

    private struct MemoryRecord {
        let payload: Payload
        let byteCount: Int
    }

    private let limits: BoundedRecordQueueLimits
    private let decode: Decode
    private let lock = NSLock()
    private var memory: [MemoryRecord] = []
    private var memoryHead = 0
    private var spill: SpillFile?
    private var metrics = Metrics()
    private var isFinished = false
    private var storedFailure: BoundedRecordQueueError?
    private var waiter: CheckedContinuation<Void, Never>?

    init(limits: BoundedRecordQueueLimits, decode: @escaping Decode) {
        self.limits = limits
        self.decode = decode
    }

    deinit {
        spill?.close()
    }

    /// Set once the queue has failed; `next()` returns nil after that.
    var failure: BoundedRecordQueueError? {
        lock.lock()
        defer { lock.unlock() }
        return storedFailure
    }

    var snapshot: Metrics {
        lock.lock()
        defer { lock.unlock() }
        return metrics
    }

    /// Appends one record. Never blocks on the consumer.
    ///
    /// `encoded` is the record's wire form: it is what spills to disk and what
    /// the memory budget counts. Throws `backlogExceeded` or `spillFailed` and
    /// marks the queue failed, after which further records are ignored.
    func enqueue(_ payload: Payload, encoded: Data) throws {
        lock.lock()
        guard !isFinished, storedFailure == nil else {
            lock.unlock()
            return
        }
        let byteCount = encoded.count
        let memoryRecords = memory.count - memoryHead
        let isSpilling = (spill?.unreadRecords ?? 0) > 0
        let fitsMemory = metrics.memoryBytes + byteCount <= limits.memoryBytes
            && memoryRecords < limits.memoryRecords
        let isHeadOfEmptyQueue = memoryRecords == 0 && !isSpilling
        if !isSpilling && (fitsMemory || isHeadOfEmptyQueue) {
            memory.append(MemoryRecord(payload: payload, byteCount: byteCount))
            metrics.memoryBytes += byteCount
            metrics.memoryRecords = memory.count - memoryHead
            metrics.peakMemoryBytes = max(metrics.peakMemoryBytes, metrics.memoryBytes)
        } else {
            do {
                if spill == nil {
                    spill = try SpillFile(capacity: limits.spillBytes)
                }
                try spill?.append(encoded)
            } catch let error as BoundedRecordQueueError {
                storedFailure = error
                let waiter = takeWaiter()
                lock.unlock()
                waiter?.resume()
                throw error
            } catch {
                let failure = BoundedRecordQueueError.spillFailed(String(describing: error))
                storedFailure = failure
                let waiter = takeWaiter()
                lock.unlock()
                waiter?.resume()
                throw failure
            }
            metrics.spilledBytes += byteCount
            metrics.spilledRecords += 1
            metrics.totalSpilledRecords += 1
            metrics.spillFileBytes = spill?.fileBytes ?? 0
            metrics.peakSpillFileBytes = max(metrics.peakSpillFileBytes, metrics.spillFileBytes)
        }
        let waiter = takeWaiter()
        lock.unlock()
        waiter?.resume()
    }

    /// Marks the end of input. Records already queued are still delivered.
    func finish() {
        lock.lock()
        isFinished = true
        let waiter = takeWaiter()
        lock.unlock()
        waiter?.resume()
    }

    /// Drops everything, releases the spill file, and ends the stream.
    func close() {
        lock.lock()
        isFinished = true
        memory.removeAll()
        memoryHead = 0
        spill?.close()
        spill = nil
        metrics.memoryBytes = 0
        metrics.memoryRecords = 0
        metrics.spilledBytes = 0
        metrics.spilledRecords = 0
        metrics.spillFileBytes = 0
        let waiter = takeWaiter()
        lock.unlock()
        waiter?.resume()
    }

    /// The next record in order, or nil once the queue is finished and drained,
    /// has failed, or the calling task is cancelled.
    ///
    /// Locking lives in the synchronous `poll` and `park` steps: the waiter is
    /// installed under the lock only after re-checking that nothing arrived
    /// since the last poll, so a racing producer can never be missed.
    func next() async -> Payload? {
        while true {
            switch poll() {
            case .record(let payload):
                return payload
            case .ended:
                return nil
            case .empty:
                if Task.isCancelled { return nil }
                await withTaskCancellationHandler {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        if !park(continuation) { continuation.resume() }
                    }
                } onCancel: {
                    wakeWaiter()
                }
            }
        }
    }

    private enum Poll {
        case record(Payload)
        case ended
        case empty
    }

    /// One locked step of `next()`; never suspends.
    private func poll() -> Poll {
        lock.lock()
        defer { lock.unlock() }
        if let record = popMemoryRecord() { return .record(record) }
        if storedFailure != nil { return .ended }
        if let spill, spill.unreadRecords > 0 {
            do {
                try refillFromSpill(spill)
            } catch let error as BoundedRecordQueueError {
                storedFailure = error
                return .ended
            } catch {
                storedFailure = .spillFailed(String(describing: error))
                return .ended
            }
            if let record = popMemoryRecord() { return .record(record) }
            return .empty
        }
        if isFinished {
            spill?.close()
            spill = nil
            return .ended
        }
        return .empty
    }

    /// Installs the consumer's continuation unless something arrived since the
    /// last poll; then the caller resumes at once and polls again.
    private func park(_ continuation: CheckedContinuation<Void, Never>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let hasMemoryRecords = memoryHead < memory.count
        let hasSpilledRecords = (spill?.unreadRecords ?? 0) > 0
        if hasMemoryRecords || hasSpilledRecords || isFinished || storedFailure != nil {
            return false
        }
        waiter = continuation
        return true
    }

    private func wakeWaiter() {
        lock.lock()
        let waiter = takeWaiter()
        lock.unlock()
        waiter?.resume()
    }

    // MARK: - Locked helpers

    private func takeWaiter() -> CheckedContinuation<Void, Never>? {
        let waiter = self.waiter
        self.waiter = nil
        return waiter
    }

    private func popMemoryRecord() -> Payload? {
        guard memoryHead < memory.count else { return nil }
        let record = memory[memoryHead]
        memoryHead += 1
        metrics.memoryBytes -= record.byteCount
        if memoryHead == memory.count {
            memory.removeAll(keepingCapacity: true)
            memoryHead = 0
        } else if memoryHead >= 256, memoryHead * 2 >= memory.count {
            memory.removeFirst(memoryHead)
            memoryHead = 0
        }
        metrics.memoryRecords = memory.count - memoryHead
        return record.payload
    }

    /// Moves the oldest spilled records back into memory, up to the budget but
    /// always at least one, and truncates the file once it is fully consumed.
    private func refillFromSpill(_ spill: SpillFile) throws {
        var loaded = 0
        while spill.unreadRecords > 0 {
            let memoryRecords = memory.count - memoryHead
            if loaded > 0,
               memoryRecords >= limits.memoryRecords
                || metrics.memoryBytes >= limits.memoryBytes {
                break
            }
            let encoded = try spill.readNext()
            let payload: Payload
            do {
                payload = try decode(encoded)
            } catch {
                throw BoundedRecordQueueError.corruptRecord(String(describing: error))
            }
            memory.append(MemoryRecord(payload: payload, byteCount: encoded.count))
            metrics.memoryBytes += encoded.count
            metrics.spilledBytes -= encoded.count
            metrics.spilledRecords -= 1
            loaded += 1
        }
        metrics.memoryRecords = memory.count - memoryHead
        metrics.peakMemoryBytes = max(metrics.peakMemoryBytes, metrics.memoryBytes)
        if spill.unreadRecords == 0 {
            try spill.truncate()
        }
        metrics.spillFileBytes = spill.fileBytes
    }
}

/// Length-prefixed records in a private temporary file that is unlinked as soon
/// as it is opened, so the kernel reclaims it even if the process dies.
///
/// Consumed bytes are compacted away only when a write would otherwise cross
/// the physical cap, so compaction cost is paid at most once per cap's worth of
/// traffic rather than on every read.
private final class SpillFile {
    private static let headerBytes = 4
    private var descriptor: Int32
    private let capacity: Int
    private var readOffset = 0
    private var writeOffset = 0
    private(set) var unreadRecords = 0

    var fileBytes: Int { writeOffset }

    init(capacity: Int) throws {
        self.capacity = capacity
        let directory = FileManager.default.temporaryDirectory.path
        var template = Array("\(directory)/ompkit-backlog.XXXXXX".utf8CString)
        let descriptor = template.withUnsafeMutableBufferPointer { buffer in
            mkstemp(buffer.baseAddress)
        }
        guard descriptor >= 0 else {
            throw BoundedRecordQueueError.spillFailed(
                "mkstemp failed with errno \(errno) in \(directory)")
        }
        let path = String(decoding: template.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        unlink(path)
        self.descriptor = descriptor
    }

    deinit { close() }

    func close() {
        guard descriptor >= 0 else { return }
        Darwin.close(descriptor)
        descriptor = -1
    }

    func append(_ record: Data) throws {
        let required = Self.headerBytes + record.count
        if writeOffset + required > capacity, readOffset > 0 {
            try compact()
        }
        guard writeOffset + required <= capacity else {
            throw BoundedRecordQueueError.backlogExceeded(
                queuedBytes: writeOffset - readOffset + required,
                limitBytes: capacity)
        }
        var header = UInt32(record.count).littleEndian
        try withUnsafeBytes(of: &header) { bytes in
            try writeFully(bytes, at: writeOffset)
        }
        try record.withUnsafeBytes { bytes in
            try writeFully(bytes, at: writeOffset + Self.headerBytes)
        }
        writeOffset += required
        unreadRecords += 1
    }

    func readNext() throws -> Data {
        precondition(unreadRecords > 0)
        var header: UInt32 = 0
        try withUnsafeMutableBytes(of: &header) { bytes in
            try readFully(into: bytes, at: readOffset)
        }
        let length = Int(UInt32(littleEndian: header))
        guard readOffset + Self.headerBytes + length <= writeOffset else {
            throw BoundedRecordQueueError.corruptRecord(
                "record length \(length) exceeds spilled bytes at offset \(readOffset)")
        }
        var record = Data(count: length)
        try record.withUnsafeMutableBytes { bytes in
            try readFully(into: bytes, at: readOffset + Self.headerBytes)
        }
        readOffset += Self.headerBytes + length
        unreadRecords -= 1
        return record
    }

    func truncate() throws {
        guard ftruncate(descriptor, 0) == 0 else {
            throw BoundedRecordQueueError.spillFailed("ftruncate failed with errno \(errno)")
        }
        readOffset = 0
        writeOffset = 0
    }

    /// Moves the unread tail to the start of the file in bounded chunks.
    private func compact() throws {
        var source = readOffset
        var destination = 0
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while source < writeOffset {
            let count = min(buffer.count, writeOffset - source)
            try buffer.withUnsafeMutableBytes { bytes in
                try readFully(into: UnsafeMutableRawBufferPointer(rebasing: bytes[..<count]), at: source)
            }
            try buffer.withUnsafeBytes { bytes in
                try writeFully(UnsafeRawBufferPointer(rebasing: bytes[..<count]), at: destination)
            }
            source += count
            destination += count
        }
        writeOffset = destination
        readOffset = 0
        guard ftruncate(descriptor, off_t(writeOffset)) == 0 else {
            throw BoundedRecordQueueError.spillFailed("ftruncate failed with errno \(errno)")
        }
    }

    private func writeFully(_ bytes: UnsafeRawBufferPointer, at offset: Int) throws {
        var written = 0
        while written < bytes.count {
            let result = pwrite(
                descriptor,
                bytes.baseAddress! + written,
                bytes.count - written,
                off_t(offset + written))
            if result < 0 {
                if errno == EINTR { continue }
                throw BoundedRecordQueueError.spillFailed("pwrite failed with errno \(errno)")
            }
            written += result
        }
    }

    private func readFully(into bytes: UnsafeMutableRawBufferPointer, at offset: Int) throws {
        var read = 0
        while read < bytes.count {
            let result = pread(
                descriptor,
                bytes.baseAddress! + read,
                bytes.count - read,
                off_t(offset + read))
            if result < 0 {
                if errno == EINTR { continue }
                throw BoundedRecordQueueError.spillFailed("pread failed with errno \(errno)")
            }
            if result == 0 {
                throw BoundedRecordQueueError.corruptRecord("unexpected end of spill file")
            }
            read += result
        }
    }
}
