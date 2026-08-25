import Darwin
import Foundation

struct ComputerUseLeaseOwner: Codable, Sendable {
    let processID: Int32
    let sessionID: String
}

enum ComputerUseLeaseError: Error, Equatable, Sendable {
    case openFailed
    case inUse
    case metadataWriteFailed
}

actor ComputerUseLease {
    private let lockURL: URL
    private var descriptor: Int32 = -1

    init(directory: URL? = nil) {
        let lockDirectory = directory ?? Self.defaultDirectory
        lockURL = lockDirectory.appending(path: "computer-use.lock")
    }

    func acquire(sessionID: String) throws {
        guard descriptor == -1 else {
            return
        }

        let newDescriptor = try openLockFile()
        guard flock(newDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            _ = close(newDescriptor)
            throw ComputerUseLeaseError.inUse
        }

        do {
            try writeOwner(
                ComputerUseLeaseOwner(
                    processID: getpid(),
                    sessionID: sanitizedSessionID(sessionID)),
                to: newDescriptor)
        } catch {
            _ = flock(newDescriptor, LOCK_UN)
            _ = close(newDescriptor)
            throw error
        }

        descriptor = newDescriptor
    }

    func release() {
        guard descriptor >= 0 else {
            return
        }

        _ = flock(descriptor, LOCK_UN)
        _ = close(descriptor)
        descriptor = -1
    }

    private static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "10x", directoryHint: .isDirectory)
    }

    private func openLockFile() throws -> Int32 {
        do {
            try FileManager.default.createDirectory(
                at: lockURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
        } catch {
            throw ComputerUseLeaseError.openFailed
        }

        let newDescriptor = lockURL.path.withCString {
            open($0, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard newDescriptor >= 0 else {
            throw ComputerUseLeaseError.openFailed
        }
        return newDescriptor
    }

    private func writeOwner(_ owner: ComputerUseLeaseOwner, to descriptor: Int32) throws {
        let data = try JSONEncoder().encode(owner)
        guard ftruncate(descriptor, 0) == 0, lseek(descriptor, 0, SEEK_SET) == 0 else {
            throw ComputerUseLeaseError.metadataWriteFailed
        }

        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) throws in
            guard let baseAddress = buffer.baseAddress else {
                throw ComputerUseLeaseError.metadataWriteFailed
            }

            var offset = 0
            while offset < buffer.count {
                let count = write(descriptor, baseAddress.advanced(by: offset), buffer.count - offset)
                guard count > 0 else {
                    throw ComputerUseLeaseError.metadataWriteFailed
                }
                offset += count
            }
        }
    }

    private func sanitizedSessionID(_ sessionID: String) -> String {
        let permitted = sessionID.filter {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "."
        }
        let truncated = String(permitted.prefix(128))
        return truncated.isEmpty ? "unknown" : truncated
    }
}
