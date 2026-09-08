import Foundation

struct ComputerUseInstaller {
    static let installPath = NSHomeDirectory() + "/Library/Application Support/10x/tenx-computer"
    static let defaultOmpConfigPath = NSHomeDirectory() + "/.omp/agent/mcp.json"

    let binaryPath: String
    let ompConfigPath: String

    init(binaryPath: String = ComputerUseInstaller.installPath,
         ompConfigPath: String = ComputerUseInstaller.defaultOmpConfigPath) {
        self.binaryPath = binaryPath
        self.ompConfigPath = ompConfigPath
    }

    var isInstalled: Bool { FileManager.default.fileExists(atPath: binaryPath) }

    /// Merge (never clobber) the tenx-computer entry into omp's user MCP config.
    func ensureMounted() throws {
        let url = URL(fileURLWithPath: ompConfigPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var config: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = existing
        }
        var servers = config["mcpServers"] as? [String: Any] ?? [:]
        let entry: [String: Any] = ["command": binaryPath, "args": ["mcp"]]
        if let existing = servers["tenx-computer"] as? [String: Any],
           NSDictionary(dictionary: existing).isEqual(to: entry) { return } // idempotent
        servers["tenx-computer"] = entry
        config["mcpServers"] = servers
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
