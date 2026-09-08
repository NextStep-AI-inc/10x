import Foundation
import OmpKit
import Testing
@testable import TenXApp

/// Opt-in drift check for the hand-curated SettingMetadata table against the
/// installed omp binary. Every probe fails by construction, so the user's
/// config is never mutated. Run with:
/// `TEST_RUNNER_OMP_DRIFT_TESTS=1 xcodebuild ... -only-testing:TenXAppTests/SettingMetadataDriftTests test`
/// (macOS test hosts require the `TEST_RUNNER_` prefix; see docs/testing.md.)
///
/// Mechanism (verified against OMP 18.1.10):
/// - `omp config set <enum-key> <sentinel>` exits 1, stderr lists "Valid values: …"
/// - `omp config set <unknown-key> x` exits 1 with "Unknown setting"
@Suite(.serialized)
struct SettingMetadataDriftTests {
    struct Result { let exitCode: Int32; let stdout: String; let stderr: String }

    static let ompPath: String? = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [home.appending(path: ".bun/bin/omp").path,
                          "/opt/homebrew/bin/omp", "/usr/local/bin/omp"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    static func run(_ arguments: [String]) throws -> Result {
        let omp = try #require(ompPath, "omp binary not installed")
        let process = Process()
        process.executableURL = URL(filePath: omp)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let drain = DispatchGroup()
        var stdoutData = Data()
        var stderrData = Data()
        drain.enter()
        DispatchQueue.global().async {
            stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
            drain.leave()
        }
        drain.enter()
        DispatchQueue.global().async {
            stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            drain.leave()
        }
        try process.run()
        process.waitUntilExit()
        drain.wait()
        return Result(exitCode: process.terminationStatus,
                      stdout: String(decoding: stdoutData, as: UTF8.self),
                      stderr: String(decoding: stderrData, as: UTF8.self))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OMP_DRIFT_TESTS"] == "1"))
    func curatedEnumOptionsMatchOmp() async throws {
        for (key, options) in SettingMetadata.enumOptions.sorted(by: { $0.key < $1.key }) {
            let result = try Self.run(["config", "set", key, "__10x_drift_sentinel__"])
            #expect(result.exitCode != 0, "\(key): sentinel set unexpectedly succeeded")
            guard !result.stderr.contains("Unknown setting") else {
                Issue.record("\(key): no longer a known OMP setting")
                continue
            }
            guard let range = result.stderr.range(of: "Valid values: ") else {
                Issue.record("\(key): no Valid values list in error — \(result.stderr)")
                continue
            }
            let listed = result.stderr[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: ", ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let curatedValues = options.map(\.value)
            #expect(listed.count == Set(listed).count,
                    "\(key): OMP Valid values list has duplicates: \(listed)")
            #expect(listed.sorted() == curatedValues.sorted(),
                    "\(key): OMP has \(listed), curated table has \(curatedValues)")
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OMP_DRIFT_TESTS"] == "1"))
    func curatedKeysStillExist() async throws {
        let result = try Self.run(["config", "list", "--json"])
        #expect(result.exitCode == 0)
        let listed = try JSONDecoder().decode(JSONValue.self, from: Data(result.stdout.utf8))
        let keys = Set(listed.objectValue?.keys ?? [:].keys)
        let curated = Array(SettingMetadata.enumOptions.keys)
            + Array(SettingMetadata.knownArrayValues.keys)
            + SettingMetadata.catalogFedArrays
            + Array(SettingMetadata.descriptions.keys)
        for key in curated {
            #expect(keys.contains(key), "\(key): curated but no longer reported by omp config list")
        }
    }
}
