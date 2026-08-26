import Foundation
@testable import OmpKit

final class ConfigurationCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [RpcClientConfiguration] = []

    func append(_ value: RpcClientConfiguration) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [RpcClientConfiguration] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

final class CompletionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func markCompleted() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func isCompleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class ClientCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [RpcClient] = []

    func append(_ value: RpcClient) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [RpcClient] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

func capturingManager(
    _ capture: ConfigurationCapture, mode: String = "basic"
) -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        capture.append(configuration)
        var fake = configuration
        fake.executable = "/usr/bin/env"
        fake.extraArguments = ["python3", fixtureURL("fake_server.py").path, mode]
        fake.rawArgv = true
        fake.cwd = nil
        return RpcClient(configuration: fake)
    })
}

func fakeManager(mode: String = "basic") -> SessionProcessManager {
    SessionProcessManager(clientFactory: { configuration in
        var c = configuration
        c.executable = "/usr/bin/env"
        c.extraArguments = ["python3", fixtureURL("fake_server.py").path, mode]
        c.rawArgv = true
        return RpcClient(configuration: c)
    })
}
