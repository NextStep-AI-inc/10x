import Foundation
import OmpKit

@main struct PerformanceAudit {
    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    static func measure(_ label: String, repeats: Int = 3, _ operation: () throws -> Int) rethrows {
        var timings: [Double] = []
        var checksum = 0
        for _ in 0..<repeats {
            let start = ContinuousClock.now
            checksum += try operation()
            timings.append(milliseconds(start.duration(to: .now)))
        }
        timings.sort()
        print("BENCH \(label) median_ms=\(String(format: "%.3f", timings[timings.count / 2])) checksum=\(checksum)")
    }

    static func main() async throws {
        let unit = "A paragraph with **bold** and `code` plus [a link](https://example.com).\n\n"
        let finalText = String(repeating: unit, count: 500)
        let frames: [RpcFrame] = (1...1_000).map { index in
            let raw: JSONValue = .object([
                "id": .string("stream"), "role": .string("assistant"),
                "content": .array([.object(["type": .string("text"), "text": .string(String(finalText.prefix(index * finalText.count / 1_000)))])])])
            return .event(type: "message_update", payload: .object(["message": raw]))
        }
        var streamTimes: [Double] = []
        for _ in 0..<3 {
            let processor = TranscriptEventProcessor(publicationInterval: .milliseconds(50))
            _ = await processor.load(.messages([]), threadStartDate: nil, hasReconciliationWarning: false, runtimeState: .idle)
            let start = ContinuousClock.now
            for frame in frames { await processor.consume(frame) }
            _ = await processor.flush()
            let snapshot = await processor.currentSnapshot()
            guard case .message(let message) = snapshot.items.last else { preconditionFailure() }
            precondition(message.visibleText == finalText)
            streamTimes.append(milliseconds(start.duration(to: .now)))
            await processor.stop()
        }
        print("BENCH processor_1000_growing_updates median_ms=\(String(format: "%.3f", streamTimes.sorted()[1])) final_bytes=\(finalText.utf8.count)")
        for count in [50, 500] {
            let text = String(repeating: unit, count: count)
            let result: JSONValue = .object(["content": .array([.object(["type": .string("text"), "text": .string(text)])])])
            let date = Date(timeIntervalSince1970: 1)
            measure("tool_update_setters_100_\(text.utf8.count)_bytes") {
                var reducer = ToolEventReducer()
                let payload: JSONValue = .object(["toolCallId": .string("tool"), "toolName": .string("browser"), "args": .object([:]), "partialResult": result])
                reducer.consume(type: "tool_execution_start", payload: payload, at: date)
                for _ in 0..<100 { reducer.consume(type: "tool_execution_update", payload: payload, at: date) }
                return reducer.presentations.count
            }
            let changingResults: [JSONValue] = (0..<100).map { index in
                .object(["content": .array([.object(["type": .string("text"), "text": .string(text + "\nUpdate \(index)")])])])
            }
            measure("tool_changed_updates_100_\(text.utf8.count)_bytes") {
                var reducer = ToolEventReducer()
                for result in changingResults {
                    let payload: JSONValue = .object(["toolCallId": .string("tool"), "toolName": .string("browser"), "args": .object([:]), "partialResult": result])
                    reducer.consume(type: "tool_execution_update", payload: payload, at: date)
                }
                precondition(reducer.presentations.last?.result == changingResults.last)
                return reducer.presentations.count
            }
            measure("tool_single_construction_100_\(text.utf8.count)_bytes") {
                var checksum = 0
                for i in 0..<100 {
                    let value = ToolPresentation(id: "tool-\(i)", name: "browser", arguments: .object([:]), result: result, phase: .running, startDate: date, endDate: nil)
                    checksum += value.content.title.count
                }
                return checksum
            }
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: "tenx-audit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let loader = SessionTimelineLoader()
        for count in [100, 1_000, 3_000] {
            var data = try JSONSerialization.data(withJSONObject: ["type": "session", "version": 3, "id": "audit", "cwd": directory.path, "timestamp": "2026-09-04T00:00:00.000Z"])
            data.append(10)
            for i in 0..<count {
                let row: [String: Any] = ["type": "message", "id": "m\(i)", "parentId": i == 0 ? NSNull() : "m\(i-1)", "timestamp": "2026-09-04T00:00:00.000Z", "message": ["role": "assistant", "content": [["type": "text", "text": String(repeating: unit, count: 10)]]]]
                data.append(try JSONSerialization.data(withJSONObject: row))
                data.append(10)
            }
            let url = directory.appending(path: "history-\(count).jsonl")
            try data.write(to: url)
            var timings: [Double] = []
            for _ in 0..<3 {
                let start = ContinuousClock.now
                let history = try await loader.load(path: url.path)
                timings.append(milliseconds(start.duration(to: .now)))
                precondition(history?.items.count == count + 1)
            }
            let cold = timings[0]
            timings.sort()
            print("BENCH timeline_\(count)_messages_\(data.count)_bytes median_ms=\(String(format: "%.3f", timings[1])) cold_ms=\(String(format: "%.3f", cold)) verified_items=\(count + 1)")
        }
    }
}
