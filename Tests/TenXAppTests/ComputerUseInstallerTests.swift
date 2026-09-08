import XCTest
@testable import TenXApp

final class ComputerUseInstallerTests: XCTestCase {
    func test_mcpMount_mergesIntoExistingConfig() throws {
        let dir = NSTemporaryDirectory() + "tenx-install-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let configPath = dir + "/mcp.json"
        try #"{"mcpServers":{"other":{"command":"/usr/bin/other"}}}"#.write(toFile: configPath, atomically: true, encoding: .utf8)

        let installer = ComputerUseInstaller(binaryPath: "/x/tenx-computer", ompConfigPath: configPath)
        try installer.ensureMounted()

        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let config = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let servers = config["mcpServers"] as! [String: Any]
        XCTAssertNotNil(servers["other"]) // preserved
        let entry = servers["tenx-computer"] as! [String: Any]
        XCTAssertEqual(entry["command"] as? String, "/x/tenx-computer")
        XCTAssertEqual(entry["args"] as? [String], ["mcp"])
    }

    func test_mcpMount_createsConfigWhenMissing() throws {
        let dir = NSTemporaryDirectory() + "tenx-install-\(UUID().uuidString)"
        let configPath = dir + "/mcp.json"
        let installer = ComputerUseInstaller(binaryPath: "/x/tenx-computer", ompConfigPath: configPath)
        try installer.ensureMounted()
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath))
    }

    func test_mcpMount_isIdempotent() throws {
        let dir = NSTemporaryDirectory() + "tenx-install-\(UUID().uuidString)"
        let configPath = dir + "/mcp.json"
        let installer = ComputerUseInstaller(binaryPath: "/x/tenx-computer", ompConfigPath: configPath)
        try installer.ensureMounted()
        let first = try String(contentsOfFile: configPath)
        try installer.ensureMounted()
        XCTAssertEqual(first, try String(contentsOfFile: configPath))
    }

    func test_mcpMount_malformedJson_throwsAndLeavesFileUntouched() throws {
        let dir = NSTemporaryDirectory() + "tenx-install-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let configPath = dir + "/mcp.json"
        let malformed = "{ not valid json"
        try malformed.write(toFile: configPath, atomically: true, encoding: .utf8)

        let installer = ComputerUseInstaller(binaryPath: "/x/tenx-computer", ompConfigPath: configPath)
        XCTAssertThrowsError(try installer.ensureMounted()) { error in
            XCTAssertTrue(error is ComputerUseInstallerError)
        }
        XCTAssertEqual(try String(contentsOfFile: configPath), malformed)
    }
}
