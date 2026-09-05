import Darwin
import Foundation
import OmpKit

@main struct TransportAudit {
    static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }
    static func output(_ value: String) { FileHandle.standardOutput.write(Data((value + "\n").utf8)) }
    static func measure(_ label: String, repeats: Int = 3, _ operation: () throws -> Int) rethrows {
        var times: [Double] = []
        var sum = 0
        for _ in 0..<repeats {
            let start = ContinuousClock.now
            sum += try operation()
            times.append(ms(start.duration(to: .now)))
        }
        output("BENCH \(label) median_ms=\(String(format: "%.3f", times.sorted()[repeats / 2])) checksum=\(sum)")
    }
    static func cpu() -> Double {
        var usage = rusage()
        precondition(getrusage(RUSAGE_SELF, &usage) == 0)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }
    static func main() async throws {
        for (bytes, iterations) in [(4_096, 1_000), (65_536, 100), (1_048_576, 10)] {
            let data = try JSONSerialization.data(withJSONObject: ["type": "message_update", "text": String(repeating: "a", count: bytes)])
            try measure("rpc_current_\(iterations)_frames_\(bytes)_bytes") {
                var checksum = 0
                for _ in 0..<iterations {
                    guard case .event(_, let payload) = try RpcFrame.decode(line: data) else { preconditionFailure() }
                    checksum += payload["text"]?.stringValue?.utf8.count ?? 0
                }
                return checksum
            }
            try measure("rpc_valid_json_direct_\(iterations)_frames_\(bytes)_bytes") {
                var checksum = 0
                for _ in 0..<iterations {
                    let payload = try JSONDecoder().decode(JSONValue.self, from: data)
                    guard case .object = payload, payload["type"]?.stringValue != nil else { preconditionFailure() }
                    checksum += payload["text"]?.stringValue?.utf8.count ?? 0
                }
                return checksum
            }
        }
        for count in [100, 1_000] {
            let root = FileManager.default.temporaryDirectory.appending(path: "tenx-watch-audit-\(UUID().uuidString)")
            let bucket = root.appending(path: "bucket")
            try FileManager.default.createDirectory(at: bucket, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let header = Data("{\"type\":\"session\",\"version\":3,\"id\":\"audit\",\"cwd\":\"/tmp\",\"timestamp\":\"2026-09-04T00:00:00.000Z\"}\n".utf8)
            for i in 0..<count { try header.write(to: bucket.appending(path: "\(i).jsonl")) }
            let library = SessionLibrary(root: root)
            let initial = await library.listAll()
            precondition(initial.count == count)
            let start = ContinuousClock.now
            let warm = await library.listAll()
            output("BENCH library_warm_\(count)_files ms=\(String(format: "%.3f", ms(start.duration(to: .now)))) verified_count=\(warm.count)")
            let changes = library.changes
            let consumer = Task { for await _ in changes { if Task.isCancelled { return } } }
            try await Task.sleep(for: .milliseconds(300))
            // Serialize a read after initialization so watcher setup is excluded.
            _ = await library.listAll()
            let handle = try FileHandle(forWritingTo: bucket.appending(path: "0.jsonl"))
            defer { try? handle.close() }
            try handle.seekToEnd()
            let before = cpu()
            let wall = ContinuousClock.now
            for _ in 0..<100 {
                try handle.write(contentsOf: Data("\n".utf8))
                try await Task.sleep(for: .milliseconds(10))
            }
            _ = await library.listAll()
            try await Task.sleep(for: .milliseconds(300))
            output("BENCH watch_100_appends_\(count)_files cpu_ms=\(String(format: "%.3f", (cpu() - before) * 1_000)) wall_ms=\(String(format: "%.3f", ms(wall.duration(to: .now))))")
            consumer.cancel()
            await consumer.value
        }
    }
}
