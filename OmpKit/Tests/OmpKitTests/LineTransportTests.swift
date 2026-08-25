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

/// Fails the test rather than hanging forever when a stream never yields.
func withTimeout<T: Sendable>(
    _ duration: Duration, operation: @escaping @Sendable () async -> T
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask { try? await Task.sleep(for: duration); return nil }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

@Test func readsReadyLineAndShutsDown() async throws {
    let t = makeFakeTransport(mode: "basic")
    try await t.start()
    let first = await withTimeout(.seconds(10)) {
        var it = t.lines.makeAsyncIterator()
        return try? await it.next()
    }
    let text = first.flatMap { $0 }.map { String(decoding: $0, as: UTF8.self) }
    #expect(text?.contains(#""type":"ready""#) == true)
    await t.shutdown()
    #expect(await t.exitStatus != nil)
}

@Test func writeAfterExitThrowsClosed() async throws {
    let t = makeFakeTransport(mode: "basic")
    try await t.start()
    await t.shutdown()
    await #expect(throws: TransportError.closed) { try await t.write(Data("{}\n".utf8)) }
}

@Test func deliversMultipleLinesInOrder() async throws {
    let t = makeFakeTransport(mode: "noisy")
    try await t.start()
    let collected = await withTimeout(.seconds(10)) {
        var out: [String] = []
        do {
            for try await line in t.lines {
                out.append(String(decoding: line, as: UTF8.self))
                if out.count >= 3 { break }
            }
        } catch {
            Issue.record("unexpected line transport failure: \(error)")
        }
        return out
    }
    let lines = collected ?? []
    #expect(lines.count == 3)
    #expect(lines[0].contains(#""type":"ready""#))
    #expect(lines[1].contains("available_commands_update"))
    #expect(lines[2].contains("extension_ui_request"))
    await t.shutdown()
}

@Test func roundTripsAWrittenCommand() async throws {
    let t = makeFakeTransport(mode: "basic")
    try await t.start()
    let response = await withTimeout(.seconds(10)) {
        var it = t.lines.makeAsyncIterator()
        _ = try? await it.next()   // ready
        try? await t.write(Data(#"{"id":"x1","type":"get_state"}"# .utf8 + [UInt8(ascii: "\n")]))
        return try? await it.next()
    }
    let text = response.flatMap { $0 }.map { String(decoding: $0, as: UTF8.self) }
    #expect(text?.contains("fake-session") == true)
    await t.shutdown()
}

@Test func exitStreamFiresWhenProcessEnds() async throws {
    let t = makeFakeTransport(mode: "basic")
    try await t.start()
    let exited = await withTimeout(.seconds(10)) { () -> Int32 in
        async let code = { () -> Int32 in
            for await c in t.onExit { return c }
            return Int32.min
        }()
        await t.shutdown()
        return await code
    }
    #expect(exited == 0)
}

@Test func spawnFailureIsReported() async {
    let t = LineTransport(executable: "/nonexistent/binary/xyz", arguments: [],
                          currentDirectory: nil, environment: nil)
    await #expect(throws: (any Error).self) { try await t.start() }
}

@Test func lineBufferReassemblesSplitReadsAndStripsCRLF() {
    let buffer = LineBuffer()
    #expect(buffer.append(Data(#"{"a":"hel"# .utf8), maxLineBytes: 100).lines.isEmpty)
    let completed = buffer.append(
        Data("lo\"}\r\n\n{\"b\":2}\r\n".utf8), maxLineBytes: 100)
    #expect(!completed.didOverflow)
    #expect(completed.lines.map { String(decoding: $0, as: UTF8.self) } == [
        #"{"a":"hello"}"#, #"{"b":2}"#,
    ])
}

@Test func lineBufferReportsOverflowInsteadOfSilentlyResynchronizing() {
    let buffer = LineBuffer()
    let overflow = buffer.append(
        Data(repeating: UInt8(ascii: "x"), count: 9), maxLineBytes: 8)
    #expect(overflow.lines.isEmpty)
    #expect(overflow.didOverflow)
    let completed = buffer.append(Data("tail\n{\"ok\":true}\n".utf8), maxLineBytes: 8)
    #expect(completed.lines.isEmpty)
    #expect(completed.didOverflow)
}

@Test func processTreeNeverSignalsReusedPIDsOrAReusedProcessGroup() throws {
    let table = FakeProcessTable([
        ProcessSnapshot(identity: .init(pid: 100, startSeconds: 1, startMicroseconds: 0),
                        parentPID: 1, processGroupID: 100),
        ProcessSnapshot(identity: .init(pid: 101, startSeconds: 1, startMicroseconds: 0),
                        parentPID: 100, processGroupID: 100),
    ])
    var tracker = ProcessTreeTracker(
        leader: try #require(table.snapshot(pid: 100)),
        processGroupID: 100,
        operations: table.operations)
    let initialRefresh = tracker.refresh(
        until: ContinuousClock.now.advanced(by: .seconds(1)))
    #expect(initialRefresh)
    #expect(tracker.knownIdentityCount == 1)

    table.replace([
        ProcessSnapshot(identity: .init(pid: 100, startSeconds: 2, startMicroseconds: 0),
                        parentPID: 1, processGroupID: 100),
        ProcessSnapshot(identity: .init(pid: 101, startSeconds: 2, startMicroseconds: 0),
                        parentPID: 100, processGroupID: 100),
    ])

    let signalCompleted = tracker.signal(
        SIGKILL, until: ContinuousClock.now.advanced(by: .seconds(1)))
    let isTerminated = tracker.isTerminated(
        until: ContinuousClock.now.advanced(by: .seconds(1)))
    #expect(signalCompleted)
    #expect(isTerminated)
    #expect(tracker.knownIdentityCount == 0)
    #expect(table.signaledProcesses.isEmpty)
    #expect(table.signaledGroups.isEmpty)
}

@Test func processTreeCanSignalAnOriginalGroupAfterItsLeaderDies() throws {
    let descendant = ProcessSnapshot(
        identity: .init(pid: 201, startSeconds: 1, startMicroseconds: 0),
        parentPID: 200,
        processGroupID: 200)
    let table = FakeProcessTable([
        ProcessSnapshot(identity: .init(pid: 200, startSeconds: 1, startMicroseconds: 0),
                        parentPID: 1, processGroupID: 200),
        descendant,
    ])
    var tracker = ProcessTreeTracker(
        leader: try #require(table.snapshot(pid: 200)),
        processGroupID: 200,
        operations: table.operations)
    let initialRefresh = tracker.refresh(
        until: ContinuousClock.now.advanced(by: .seconds(1)))
    #expect(initialRefresh)
    table.replace([descendant])

    let signalCompleted = tracker.signal(
        SIGTERM, until: ContinuousClock.now.advanced(by: .seconds(1)))
    #expect(signalCompleted)
    #expect(table.signaledGroups.count == 1)
    #expect(table.signaledGroups.first?.0 == 200)
    #expect(table.signaledGroups.first?.1 == SIGTERM)
    #expect(table.signaledProcesses.isEmpty)
}

@Test func reusedLeaderPreventsGroupSignalWhileOriginalDescendantIsSignaledDirectly() throws {
    let descendant = ProcessSnapshot(
        identity: .init(pid: 251, startSeconds: 1, startMicroseconds: 0),
        parentPID: 250,
        processGroupID: 250)
    let table = FakeProcessTable([
        ProcessSnapshot(identity: .init(pid: 250, startSeconds: 1, startMicroseconds: 0),
                        parentPID: 1, processGroupID: 250),
        descendant,
    ])
    var tracker = ProcessTreeTracker(
        leader: try #require(table.snapshot(pid: 250)),
        processGroupID: 250,
        operations: table.operations)
    let initialRefresh = tracker.refresh(
        until: ContinuousClock.now.advanced(by: .seconds(1)))
    #expect(initialRefresh)
    table.replace([
        ProcessSnapshot(identity: .init(pid: 250, startSeconds: 2, startMicroseconds: 0),
                        parentPID: 1, processGroupID: 250),
        descendant,
    ])

    let signalCompleted = tracker.signal(
        SIGKILL, until: ContinuousClock.now.advanced(by: .seconds(1)))
    #expect(signalCompleted)
    #expect(table.signaledGroups.isEmpty)
    #expect(table.signaledProcesses.count == 1)
    #expect(table.signaledProcesses.first?.0 == descendant.identity.pid)
}

@Test func processTreeTraversalStopsAtItsDeadlineAndTrackedSetStaysBounded() throws {
    let children = (301...10_000).map { pid in
        ProcessSnapshot(identity: .init(pid: pid_t(pid), startSeconds: 1, startMicroseconds: 0),
                        parentPID: 300, processGroupID: 300)
    }
    let table = FakeProcessTable([
        ProcessSnapshot(identity: .init(pid: 300, startSeconds: 1, startMicroseconds: 0),
                        parentPID: 1, processGroupID: 300),
    ] + children, snapshotDelay: .milliseconds(1))
    var tracker = ProcessTreeTracker(
        leader: try #require(table.snapshot(pid: 300)),
        processGroupID: 300,
        operations: table.operations)
    let started = ContinuousClock.now

    let completed = tracker.refresh(until: started.advanced(by: .milliseconds(10)))
    #expect(!completed)
    #expect(ContinuousClock.now - started < .milliseconds(100))
    #expect(tracker.knownIdentityCount <= ProcessTreeTracker.maximumTrackedProcesses)
    #expect(table.snapshotCallCount < children.count)
}

@Test func incompleteTreeObservationCannotLaterClaimConfirmedTermination() throws {
    let table = FakeProcessTable([
        ProcessSnapshot(identity: .init(pid: 400, startSeconds: 1, startMicroseconds: 0),
                        parentPID: 1, processGroupID: 400),
    ], listsAreComplete: false)
    var tracker = ProcessTreeTracker(
        leader: try #require(table.snapshot(pid: 400)),
        processGroupID: 400,
        operations: table.operations)
    let refreshCompleted = tracker.refresh(
        until: ContinuousClock.now.advanced(by: .seconds(1)))
    #expect(!refreshCompleted)
    table.replace([])

    let isTerminated = tracker.isTerminated(
        until: ContinuousClock.now.advanced(by: .seconds(1)))
    #expect(!isTerminated)
}

@Test func laterIncompleteObservationInvalidatesPriorTerminationCertification() throws {
    let leader = ProcessSnapshot(
        identity: .init(pid: 450, startSeconds: 1, startMicroseconds: 0),
        parentPID: 1,
        processGroupID: 450)
    let descendant = ProcessSnapshot(
        identity: .init(pid: 451, startSeconds: 1, startMicroseconds: 0),
        parentPID: 450,
        processGroupID: 450)
    let table = FakeProcessTable([leader, descendant])
    var tracker = ProcessTreeTracker(
        leader: leader,
        processGroupID: 450,
        operations: table.operations)
    let initialRefresh = tracker.refresh(
        until: ContinuousClock.now.advanced(by: .seconds(1)))
    #expect(initialRefresh)

    table.setListsAreComplete(false)
    let incompleteRefresh = tracker.refresh(
        until: ContinuousClock.now.advanced(by: .seconds(1)))
    #expect(!incompleteRefresh)
    table.replace([descendant])
    let terminatedAfterIncompleteRefresh = tracker.isTerminated(
        until: ContinuousClock.now.advanced(by: .seconds(1)))
    #expect(!terminatedAfterIncompleteRefresh)

    table.setListsAreComplete(true)
    let recoveryRefresh = tracker.refresh(
        until: ContinuousClock.now.advanced(by: .seconds(1)))
    #expect(recoveryRefresh)
    table.replace([])
    let terminatedAfterRecovery = tracker.isTerminated(
        until: ContinuousClock.now.advanced(by: .seconds(1)))
    #expect(terminatedAfterRecovery)
}

@Test func descendantTrackerStopsPollingWhenTransportShutsDown() async throws {
    let polls = LockedCounter()
    let transport = LineTransport(
        executable: "/usr/bin/env",
        arguments: ["python3", fixtureURL("fake_server.py").path, "basic"],
        currentDirectory: nil,
        environment: nil,
        trackerDidPoll: { polls.increment() })
    try await transport.start()
    #expect(await waitUntil { polls.value >= 2 })

    await transport.shutdown()
    let stoppedAt = polls.value
    try await Task.sleep(for: .milliseconds(100))
    #expect(polls.value == stoppedAt)
}

@Test func descendantTrackerDoesNotRetainAnAbandonedTransport() async throws {
    let polls = LockedCounter()
    let weakTransport = WeakTransportBox()
    do {
        let transport = LineTransport(
            executable: "/usr/bin/true",
            arguments: [],
            currentDirectory: nil,
            environment: nil,
            trackerDidPoll: { polls.increment() })
        weakTransport.value = transport
        try await transport.start()
    }

    #expect(await waitUntil { weakTransport.value == nil })
    let stoppedAt = polls.value
    try await Task.sleep(for: .milliseconds(100))
    #expect(polls.value == stoppedAt)
}

@Test func shutdownUnblocksAFullStdinPipe() async throws {
    let transport = LineTransport(
        executable: "/bin/sleep", arguments: ["60"],
        currentDirectory: nil, environment: nil)
    try await transport.start()
    let writer = Task { try await transport.write(Data(repeating: 0x61, count: 1_048_576)) }
    try await Task.sleep(for: .milliseconds(100))
    let clock = ContinuousClock()
    let started = clock.now
    await transport.shutdown()
    #expect(clock.now - started < .seconds(3))
    _ = await writer.result
}

@Test func shutdownKillsGrandchildrenAfterTheLeaderExitsOnEOF() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ompkit-heartbeat-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let transport = LineTransport(
        executable: "/usr/bin/env",
        arguments: ["python3", fixtureURL("fake_server.py").path, "grandchild", root.path],
        currentDirectory: nil, environment: nil)
    try await transport.start()

    let before = await withTimeout(.seconds(2)) { () -> Int in
        while !Task.isCancelled {
            let count = (try? Data(contentsOf: root))?.count ?? 0
            if count > 0 { return count }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return 0
    } ?? 0
    #expect(before > 0)
    await transport.shutdown()
    try await Task.sleep(for: .milliseconds(300))
    let after = (try? Data(contentsOf: root))?.count ?? 0
    try await Task.sleep(for: .milliseconds(300))
    let settled = (try? Data(contentsOf: root))?.count ?? 0
    #expect(after == settled)
}

@Test func drainsTrailingFramesWhenChildExits() async throws {
    let transport = makeFakeTransport(mode: "burst-exit")
    try await transport.start()
    let lines = await withTimeout(.seconds(5)) { () -> [Data] in
        var lines: [Data] = []
        do {
            for try await line in transport.lines { lines.append(line) }
        } catch {
            Issue.record("unexpected trailing-frame failure: \(error)")
        }
        return lines
    } ?? []
    #expect(lines.count == 201)  // ready + 200 notices
    let exitCode = await withTimeout(.seconds(1)) { () -> Int32? in
        for await code in transport.onExit { return code }
        return nil
    } ?? nil
    #expect(exitCode == 0)
}

@Test func lineBacklogOverflowFailsClosedInsteadOfDroppingFrames() async throws {
    let transport = makeFakeTransport(mode: "backlog-overflow")
    try await transport.start()
    try await Task.sleep(for: .milliseconds(200))

    let overflowed = await withTimeout(.seconds(2)) { () -> Bool in
        do {
            for try await _ in transport.lines {}
            return false
        } catch TransportError.backlogOverflow {
            return true
        } catch {
            return false
        }
    }
    let started = ContinuousClock.now
    let stopped = await transport.shutdown(
        deadline: started.advanced(by: .seconds(1)))

    #expect(overflowed == true)
    #expect(stopped)
    #expect(ContinuousClock.now - started < .seconds(1.2))
}

@Test func cumulativeLineBytesOverflowBeforeTheFrameCountCap() async throws {
    let transport = makeFakeTransport(mode: "byte-backlog-overflow")
    try await transport.start()
    _ = await withTimeout(.seconds(2)) { () -> Bool in
        while await transport.exitStatus == nil {
            if await transport.stderrSnapshot().contains("byte-backlog-complete") {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    let overflowed = await withTimeout(.seconds(2)) { () -> Bool in
        do {
            for try await _ in transport.lines {}
            return false
        } catch TransportError.backlogOverflow {
            return true
        } catch {
            return false
        }
    }
    let started = ContinuousClock.now
    let stopped = await transport.shutdown(
        deadline: started.advanced(by: .seconds(1)))

    #expect(overflowed == true)
    #expect(stopped)
    #expect(ContinuousClock.now - started < .seconds(1.2))
}

@Test func oneNearPhysicalLimitLineIsDelivered() async throws {
    let transport = makeFakeTransport(mode: "near-limit-line")
    try await transport.start()

    let lines = await withTimeout(.seconds(2)) { () -> [Data] in
        var received: [Data] = []
        do {
            for try await line in transport.lines {
                received.append(line)
            }
        } catch {
            Issue.record("unexpected near-limit line failure: \(error)")
        }
        return received
    } ?? []

    #expect(lines.count == 2)
    #expect(lines.last?.count == 1_000_030)
    #expect(await transport.shutdown())
}

private final class FakeProcessTable: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [pid_t: ProcessSnapshot]
    private let snapshotDelay: Duration
    private var listsAreComplete: Bool
    private var processSignals: [(pid_t, Int32)] = []
    private var groupSignals: [(pid_t, Int32)] = []
    private var snapshotCalls = 0

    init(
        _ values: [ProcessSnapshot],
        snapshotDelay: Duration = .zero,
        listsAreComplete: Bool = true
    ) {
        snapshots = Dictionary(uniqueKeysWithValues: values.map { ($0.identity.pid, $0) })
        self.snapshotDelay = snapshotDelay
        self.listsAreComplete = listsAreComplete
    }

    var operations: ProcessOperations {
        ProcessOperations(
            snapshot: { [self] pid in snapshot(pid: pid) },
            childPIDs: { [self] parent in
                lock.withLock {
                    .init(pids: snapshots.values.filter { $0.parentPID == parent }
                        .map(\.identity.pid), isComplete: listsAreComplete)
                }
            },
            groupPIDs: { [self] group in
                lock.withLock {
                    .init(pids: snapshots.values.filter { $0.processGroupID == group }
                        .map(\.identity.pid), isComplete: listsAreComplete)
                }
            },
            signalProcess: { [self] pid, signal in
                lock.withLock { processSignals.append((pid, signal)) }
            },
            signalGroup: { [self] group, signal in
                lock.withLock { groupSignals.append((group, signal)) }
            })
    }

    func snapshot(pid: pid_t) -> ProcessSnapshot? {
        if snapshotDelay > .zero { Thread.sleep(forTimeInterval: snapshotDelay.timeInterval) }
        return lock.withLock {
            snapshotCalls += 1
            return snapshots[pid]
        }
    }

    func replace(_ values: [ProcessSnapshot]) {
        lock.withLock {
            snapshots = Dictionary(uniqueKeysWithValues: values.map { ($0.identity.pid, $0) })
        }
    }

    func setListsAreComplete(_ isComplete: Bool) {
        lock.withLock { listsAreComplete = isComplete }
    }

    var signaledProcesses: [(pid_t, Int32)] { lock.withLock { processSignals } }
    var signaledGroups: [(pid_t, Int32)] { lock.withLock { groupSignals } }
    var snapshotCallCount: Int { lock.withLock { snapshotCalls } }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

private final class WeakTransportBox: @unchecked Sendable {
    weak var value: LineTransport?
}

private func waitUntil(_ condition: @escaping @Sendable () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
