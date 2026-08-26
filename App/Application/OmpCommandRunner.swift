import Darwin
import Foundation
import Synchronization

enum OmpCommandRunnerError: Error, Sendable {
    case spawnFailed(Int32)
    case waitFailed(Int32)
    case nonzeroExit(Int32)
}

struct OmpCommandRunner: Sendable {
    func run(executableURL: URL, arguments: [String]) async throws -> Data {
        let state = OmpCommandProcessState()
        let worker = Task.detached {
            try await state.run(
                executableURL: executableURL,
                arguments: arguments)
        }

        return try await withTaskCancellationHandler {
            let data = try await worker.value
            try Task.checkCancellation()
            return data
        } onCancel: {
            worker.cancel()
            state.cancel()
        }
    }
}

private struct OmpCommandProcessStorage {
    var isCancellationRequested = false
    var hasSentTermination = false
    var processID: pid_t?
    var waitStatus: Int32?
}

private struct OmpSpawnedCommand {
    let processID: pid_t
    let output: FileHandle
    let error: FileHandle
}

private final class OmpCommandProcessState: Sendable {
    private let storage = Mutex(OmpCommandProcessStorage())

    func run(executableURL: URL, arguments: [String]) async throws -> Data {
        try Task.checkCancellation()
        let command = try storage.withLock { storage in
            guard !storage.isCancellationRequested else { throw CancellationError() }
            let command = try Self.spawn(
                executableURL: executableURL,
                arguments: arguments)
            storage.processID = command.processID
            return command
        }

        async let outputData = Self.drain(command.output)
        async let errorData = Self.drain(command.error)

        do {
            let waitStatus = try await waitForLeader()
            let terminationStatus = Self.terminationStatus(from: waitStatus)
            if terminationStatus != 0 {
                await terminateAndReapProcessGroup()
                _ = try? await outputData
                _ = try? await errorData
                throw OmpCommandRunnerError.nonzeroExit(terminationStatus)
            }
            let data = try await outputData
            _ = try await errorData
            try Task.checkCancellation()
            try finish()
            return data
        } catch is CancellationError {
            await terminateAndReapProcessGroup()
            _ = try? await outputData
            _ = try? await errorData
            throw CancellationError()
        } catch OmpCommandRunnerError.nonzeroExit(let status) {
            throw OmpCommandRunnerError.nonzeroExit(status)
        } catch {
            await terminateAndReapProcessGroup()
            _ = try? await outputData
            _ = try? await errorData
            throw error
        }
    }

    func cancel() {
        let processID = storage.withLock { storage -> pid_t? in
            storage.isCancellationRequested = true
            guard !storage.hasSentTermination else { return nil }
            storage.hasSentTermination = true
            return storage.processID
        }
        if let processID { killpg(processID, SIGTERM) }
    }

    private func waitForLeader() async throws -> Int32 {
        while true {
            try Task.checkCancellation()
            if let status = try pollLeader() { return status }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func finish() throws {
        try storage.withLock { storage in
            guard !storage.isCancellationRequested else { throw CancellationError() }
            storage.processID = nil
        }
    }

    private func terminateAndReapProcessGroup() async {
        guard let processID = storage.withLock({ $0.processID }) else { return }
        let shouldSendTermination = storage.withLock { storage in
            guard !storage.hasSentTermination else { return false }
            storage.hasSentTermination = true
            return true
        }
        if shouldSendTermination, Self.processGroupExists(processID) {
            killpg(processID, SIGTERM)
        }

        let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
        while ContinuousClock.now < deadline, Self.processGroupExists(processID) {
            _ = try? pollLeader()
            await Self.delay()
        }
        if Self.processGroupExists(processID) {
            killpg(processID, SIGKILL)
        }
        while Self.processGroupExists(processID) {
            _ = try? pollLeader()
            await Self.delay()
        }
        while storage.withLock({ $0.waitStatus == nil }) {
            _ = try? pollLeader()
            if storage.withLock({ $0.waitStatus == nil }) {
                await Self.delay()
            }
        }
    }

    private func pollLeader() throws -> Int32? {
        try storage.withLock { storage in
            if let waitStatus = storage.waitStatus { return waitStatus }
            guard let processID = storage.processID else { return nil }
            var waitStatus: Int32 = 0
            let result = waitpid(processID, &waitStatus, WNOHANG)
            if result == processID {
                storage.waitStatus = waitStatus
                return waitStatus
            }
            if result == -1, errno != EINTR {
                throw OmpCommandRunnerError.waitFailed(errno)
            }
            return nil
        }
    }

    private static func processGroupExists(_ processGroupID: pid_t) -> Bool {
        if killpg(processGroupID, 0) == 0 { return true }
        return errno == EPERM
    }

    private static func delay() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(10)) {
                continuation.resume()
            }
        }
    }

    private static func drain(_ handle: FileHandle) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    continuation.resume(returning: try handle.readToEnd() ?? Data())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func terminationStatus(from waitStatus: Int32) -> Int32 {
        let signal = waitStatus & 0x7f
        return signal == 0 ? (waitStatus >> 8) & 0xff : signal
    }

    private static func spawn(
        executableURL: URL,
        arguments: [String]
    ) throws -> OmpSpawnedCommand {
        var outputDescriptors: [Int32] = [0, 0]
        guard pipe(&outputDescriptors) == 0 else {
            throw OmpCommandRunnerError.spawnFailed(errno)
        }
        var errorDescriptors: [Int32] = [0, 0]
        guard pipe(&errorDescriptors) == 0 else {
            let code = errno
            close(outputDescriptors[0])
            close(outputDescriptors[1])
            throw OmpCommandRunnerError.spawnFailed(code)
        }

        var ownsReadDescriptors = true
        defer {
            if ownsReadDescriptors {
                close(outputDescriptors[0])
                close(errorDescriptors[0])
            }
            close(outputDescriptors[1])
            close(errorDescriptors[1])
        }

        var fileActions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        var fileActionsInitialized = false
        var attributesInitialized = false
        defer {
            if attributesInitialized { posix_spawnattr_destroy(&attributes) }
            if fileActionsInitialized { posix_spawn_file_actions_destroy(&fileActions) }
        }

        var result = posix_spawn_file_actions_init(&fileActions)
        guard result == 0 else { throw OmpCommandRunnerError.spawnFailed(result) }
        fileActionsInitialized = true
        result = posix_spawnattr_init(&attributes)
        guard result == 0 else { throw OmpCommandRunnerError.spawnFailed(result) }
        attributesInitialized = true

        let fileActionResults = [
            posix_spawn_file_actions_adddup2(
                &fileActions, outputDescriptors[1], STDOUT_FILENO),
            posix_spawn_file_actions_adddup2(
                &fileActions, errorDescriptors[1], STDERR_FILENO),
            posix_spawn_file_actions_addclose(&fileActions, outputDescriptors[0]),
            posix_spawn_file_actions_addclose(&fileActions, outputDescriptors[1]),
            posix_spawn_file_actions_addclose(&fileActions, errorDescriptors[0]),
            posix_spawn_file_actions_addclose(&fileActions, errorDescriptors[1]),
        ]
        if let fileActionError = fileActionResults.first(where: { $0 != 0 }) {
            throw OmpCommandRunnerError.spawnFailed(fileActionError)
        }

        var defaultSignals = sigset_t()
        sigemptyset(&defaultSignals)
        sigaddset(&defaultSignals, SIGTERM)
        result = posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
        guard result == 0 else { throw OmpCommandRunnerError.spawnFailed(result) }
        var signalMask = sigset_t()
        sigemptyset(&signalMask)
        result = posix_spawnattr_setsigmask(&attributes, &signalMask)
        guard result == 0 else { throw OmpCommandRunnerError.spawnFailed(result) }
        result = posix_spawnattr_setflags(
            &attributes,
            Int16(
                POSIX_SPAWN_SETPGROUP
                    | POSIX_SPAWN_SETSIGDEF
                    | POSIX_SPAWN_SETSIGMASK))
        guard result == 0 else { throw OmpCommandRunnerError.spawnFailed(result) }
        result = posix_spawnattr_setpgroup(&attributes, 0)
        guard result == 0 else { throw OmpCommandRunnerError.spawnFailed(result) }

        let executablePath = executableURL.path
        var argumentPointers = ([executablePath] + arguments).map { strdup($0) }
        var environmentPointers = ProcessInfo.processInfo.environment.map {
            strdup("\($0.key)=\($0.value)")
        }
        defer {
            argumentPointers.compactMap { $0 }.forEach { free($0) }
            environmentPointers.compactMap { $0 }.forEach { free($0) }
        }
        guard argumentPointers.allSatisfy({ $0 != nil }),
              environmentPointers.allSatisfy({ $0 != nil })
        else { throw OmpCommandRunnerError.spawnFailed(ENOMEM) }
        argumentPointers.append(nil)
        environmentPointers.append(nil)

        var processID: pid_t = 0
        result = executablePath.withCString { path in
            argumentPointers.withUnsafeMutableBufferPointer { arguments in
                environmentPointers.withUnsafeMutableBufferPointer { environment in
                    posix_spawn(
                        &processID,
                        path,
                        &fileActions,
                        &attributes,
                        arguments.baseAddress,
                        environment.baseAddress)
                }
            }
        }
        guard result == 0 else { throw OmpCommandRunnerError.spawnFailed(result) }

        let output = FileHandle(
            fileDescriptor: outputDescriptors[0],
            closeOnDealloc: true)
        let error = FileHandle(
            fileDescriptor: errorDescriptors[0],
            closeOnDealloc: true)
        ownsReadDescriptors = false
        return OmpSpawnedCommand(
            processID: processID,
            output: output,
            error: error)
    }
}
