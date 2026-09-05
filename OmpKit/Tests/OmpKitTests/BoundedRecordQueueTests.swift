import Testing
import Foundation
@testable import OmpKit

private func makeQueue(
    memoryBytes: Int,
    memoryRecords: Int = 1_024,
    spillBytes: Int
) -> BoundedRecordQueue<Data> {
    BoundedRecordQueue<Data>(
        limits: BoundedRecordQueueLimits(
            memoryBytes: memoryBytes,
            memoryRecords: memoryRecords,
            spillBytes: spillBytes),
        decode: { $0 })
}

/// A record whose first bytes carry its index, so order checks fail loudly.
private func record(_ index: Int, size: Int) -> Data {
    var data = Data(repeating: UInt8(ascii: "."), count: size)
    let label = Array("\(index):".utf8).prefix(size)
    data.replaceSubrange(0..<label.count, with: label)
    return data
}

private func drain(_ queue: BoundedRecordQueue<Data>, count: Int) async -> [Data] {
    var received: [Data] = []
    for _ in 0..<count {
        guard let next = await queue.next() else { break }
        received.append(next)
    }
    return received
}

@Test func recordsKeepArrivalOrderThroughMemoryAndSpill() async throws {
    let queue = makeQueue(memoryBytes: 64, memoryRecords: 4, spillBytes: 8_192)
    let first = (0..<40).map { record($0, size: 20) }
    for data in first { try queue.enqueue(data, encoded: data) }
    let produced = queue.snapshot
    #expect(produced.memoryRecords == 3)
    #expect(produced.spilledRecords == 37)
    #expect(produced.spillFileBytes == 37 * 24)

    #expect(await drain(queue, count: 40) == first)
    let drained = queue.snapshot
    #expect(drained.memoryRecords == 0)
    #expect(drained.spilledRecords == 0)
    #expect(drained.spillFileBytes == 0)
    #expect(drained.totalSpilledRecords == 37)

    // Once the spill is consumed, records go back to memory until it is full.
    let second = (40..<50).map { record($0, size: 20) }
    for data in second { try queue.enqueue(data, encoded: data) }
    #expect(queue.snapshot.memoryRecords == 3)
    #expect(queue.snapshot.spilledRecords == 7)
    queue.finish()
    #expect(await drain(queue, count: 11) == second)
    #expect(await queue.next() == nil)
}

@Test func oversizedHeadRecordStaysInMemoryButOversizedQueuedRecordsSpill() async throws {
    let queue = makeQueue(memoryBytes: 16, spillBytes: 8_192)
    let head = record(0, size: 100)
    try queue.enqueue(head, encoded: head)
    #expect(queue.snapshot.memoryRecords == 1)
    #expect(queue.snapshot.memoryBytes == 100)
    #expect(queue.snapshot.spilledRecords == 0)

    let queued = record(1, size: 100)
    try queue.enqueue(queued, encoded: queued)
    #expect(queue.snapshot.spilledRecords == 1)
    #expect(await drain(queue, count: 2) == [head, queued])
}

@Test func overflowFailsTheProducerAndEndsTheConsumerAfterAcceptedRecords() async throws {
    let queue = makeQueue(memoryBytes: 32, memoryRecords: 2, spillBytes: 64)
    let records = (0..<8).map { record($0, size: 16) }
    for data in records[0..<5] { try queue.enqueue(data, encoded: data) }
    #expect(queue.snapshot.memoryRecords == 2)
    #expect(queue.snapshot.spilledRecords == 3)
    #expect(queue.snapshot.spillFileBytes == 60)

    #expect(throws: BoundedRecordQueueError.backlogExceeded(queuedBytes: 80, limitBytes: 64)) {
        try queue.enqueue(records[5], encoded: records[5])
    }
    #expect(queue.failure == .backlogExceeded(queuedBytes: 80, limitBytes: 64))
    // Later records are ignored rather than compounding the failure.
    try queue.enqueue(records[6], encoded: records[6])
    #expect(queue.snapshot.spilledRecords == 3)

    #expect(await drain(queue, count: 8) == Array(records[0..<2]))
    #expect(await queue.next() == nil)
}

@Test func consumedSpillPrefixIsCompactedBeforeTheCapFails() async throws {
    let queue = makeQueue(memoryBytes: 16, memoryRecords: 1, spillBytes: 200)
    let records = (0..<16).map { record($0, size: 16) }
    try queue.enqueue(records[0], encoded: records[0])
    for data in records[1..<10] { try queue.enqueue(data, encoded: data) }
    #expect(queue.snapshot.spillFileBytes == 180)

    #expect(await drain(queue, count: 7) == Array(records[0..<7]))
    // Six consumed spilled records leave 120 dead bytes ahead of three live
    // ones; appending six more only fits if that prefix is reclaimed.
    for data in records[10..<16] { try queue.enqueue(data, encoded: data) }
    #expect(queue.failure == nil)
    #expect(queue.snapshot.spillFileBytes <= 200)
    #expect(queue.snapshot.spilledRecords == 9)

    queue.finish()
    #expect(await drain(queue, count: 20) == Array(records[7..<16]))
}

@Test func cancelledConsumerWakesAndLaterRecordsAreStillDelivered() async throws {
    let queue = makeQueue(memoryBytes: 64, spillBytes: 1_024)
    let parked = Task { await queue.next() }
    try await Task.sleep(for: .milliseconds(50))
    parked.cancel()
    guard let outcome = await withTimeout(.seconds(2), operation: { await parked.value }) else {
        Issue.record("a cancelled consumer must return instead of staying parked")
        return
    }
    #expect(outcome == nil)

    let data = record(1, size: 8)
    try queue.enqueue(data, encoded: data)
    #expect(await queue.next() == data)
}

@Test func spillFileIsNeverVisibleOnDisk() async throws {
    let queue = makeQueue(memoryBytes: 8, spillBytes: 4_096)
    let temporary = FileManager.default.temporaryDirectory.path
    let before = try FileManager.default.contentsOfDirectory(atPath: temporary)
        .filter { $0.hasPrefix("ompkit-backlog.") }
    let data = record(0, size: 32)
    try queue.enqueue(data, encoded: data)
    try queue.enqueue(data, encoded: data)
    #expect(queue.snapshot.spilledRecords == 1)
    let during = try FileManager.default.contentsOfDirectory(atPath: temporary)
        .filter { $0.hasPrefix("ompkit-backlog.") }
    #expect(during == before)
    #expect(await drain(queue, count: 2) == [data, data])
}

@Test func closeDropsEverythingAndEndsTheConsumer() async throws {
    let queue = makeQueue(memoryBytes: 8, spillBytes: 4_096)
    let data = record(0, size: 32)
    try queue.enqueue(data, encoded: data)
    try queue.enqueue(data, encoded: data)
    queue.close()
    #expect(queue.snapshot == BoundedRecordQueue<Data>.Metrics(
        memoryBytes: 0, memoryRecords: 0, spilledBytes: 0, spilledRecords: 0,
        spillFileBytes: 0, peakMemoryBytes: 32, peakSpillFileBytes: 36, totalSpilledRecords: 1))
    #expect(await queue.next() == nil)
}
