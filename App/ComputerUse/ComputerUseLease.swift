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
    case unsafePath
    case permissionSetupFailed
}

actor ComputerUseLease {
    private let lockURL: URL
    private var heldDescriptor: LockedDescriptor?

    init(directory: URL? = nil) {
        let lockDirectory = directory ?? Self.defaultDirectory
        lockURL = lockDirectory.appending(path: "computer-use.lock")
    }

    func acquire(sessionID: String) throws {
        guard heldDescriptor == nil else {
            return
        }

        let descriptor = try openLockFile()
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            _ = close(descriptor)
            throw ComputerUseLeaseError.inUse
        }

        do {
            try writeOwner(
                ComputerUseLeaseOwner(
                    processID: getpid(),
                    sessionID: sanitizedSessionID(sessionID)),
                to: descriptor)
        } catch {
            _ = flock(descriptor, LOCK_UN)
            _ = close(descriptor)
            throw error
        }

        heldDescriptor = LockedDescriptor(descriptor: descriptor)
    }

    func release() {
        heldDescriptor?.release()
        heldDescriptor = nil
    }

    private static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "10x", directoryHint: .isDirectory)
    }

    private func openLockFile() throws -> Int32 {
        let directoryDescriptor = try openLockDirectory()
        defer { _ = close(directoryDescriptor) }

        let descriptor = "computer-use.lock".withCString {
            openat(directoryDescriptor, $0, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            if errno == ELOOP {
                throw ComputerUseLeaseError.unsafePath
            }
            throw ComputerUseLeaseError.openFailed
        }

        var information = stat()
        guard fstat(descriptor, &information) == 0 else {
            _ = close(descriptor)
            throw ComputerUseLeaseError.openFailed
        }
        guard information.st_mode & S_IFMT == S_IFREG else {
            _ = close(descriptor)
            throw ComputerUseLeaseError.unsafePath
        }
        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            _ = close(descriptor)
            throw ComputerUseLeaseError.permissionSetupFailed
        }
        return descriptor
    }

    private func openLockDirectory() throws -> Int32 {
        var information = stat()
        let path = lockURL.deletingLastPathComponent().path
        let didFindDirectory = path.withCString { lstat($0, &information) == 0 }
        if !didFindDirectory {
            guard errno == ENOENT else {
                throw ComputerUseLeaseError.openFailed
            }
            do {
                try FileManager.default.createDirectory(
                    at: lockURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: S_IRWXU])
            } catch {
                throw ComputerUseLeaseError.openFailed
            }
            guard path.withCString({ lstat($0, &information) == 0 }) else {
                throw ComputerUseLeaseError.openFailed
            }
        }

        let descriptor = path.withCString {
            open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            if errno != ELOOP && errno != ENOTDIR {
                throw ComputerUseLeaseError.openFailed
            }
            throw ComputerUseLeaseError.unsafePath
        }
        guard fstat(descriptor, &information) == 0, information.st_mode & S_IFMT == S_IFDIR else {
            _ = close(descriptor)
            throw ComputerUseLeaseError.unsafePath
        }
        guard fchmod(descriptor, S_IRWXU) == 0 else {
            _ = close(descriptor)
            throw ComputerUseLeaseError.permissionSetupFailed
        }
        return descriptor
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

private final class LockedDescriptor {
    private var descriptor: Int32

    init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    func release() {
        guard descriptor >= 0 else {
            return
        }
        _ = flock(descriptor, LOCK_UN)
        _ = close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}
