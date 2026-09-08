import CoreGraphics
import Darwin
import Foundation

// ponytail: SkyLight private SPI for background input; symbols probed at runtime.
// Ceiling: macOS may remove or change these exports; multi-window keyboard is refused upstream.

struct ProcessSerialNumber {
    var high: UInt32 = 0
    var low: UInt32 = 0
}

enum SkyLight {
    private static let eventRecordLength = 248
    private static let eventRecordLengthByte: UInt8 = 0xf8
    private static let eventRecordKind: UInt8 = 0x0d
    private static let windowIDOffset = 0x3c
    private static let focusMarkerOffset = 0x8a

    private typealias SLEventPostToPidFn = @convention(c) (pid_t, UnsafeMutableRawPointer?) -> Void
    private typealias SLEventSetIntegerValueFieldFn = @convention(c) (UnsafeMutableRawPointer?, UInt32, Int64) -> Void
    private typealias SLPSPostEventRecordToFn = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<UInt8>) -> Int32
    private typealias SLPSGetFrontProcessFn = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias CGSMainConnectionIDFn = @convention(c) () -> UInt32
    private typealias SLSGetWindowOwnerFn = @convention(c) (UInt32, UInt32, UnsafeMutablePointer<UInt32>) -> Int32
    private typealias SLSGetConnectionPSNFn = @convention(c) (UInt32, UnsafeMutableRawPointer) -> Int32
    private typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32
    private typealias CGEventSetWindowLocationFn = @convention(c) (UnsafeMutableRawPointer?, CGPoint) -> Void
    private typealias SLEventSetAuthenticationMessageFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    private typealias ObjcGetClassFn = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
    private typealias SelRegisterNameFn = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
    private typealias ClassRespondsToSelectorFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Bool
    private typealias AuthenticationFactoryFn = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, UInt32
    ) -> UnsafeMutableRawPointer?

    private struct RequiredSPI {
        let postToPid: SLEventPostToPidFn
        let setInteger: SLEventSetIntegerValueFieldFn
        let postRecord: SLPSPostEventRecordToFn
        let getFront: SLPSGetFrontProcessFn
        let setWindowLocation: CGEventSetWindowLocationFn
        let mainConnection: CGSMainConnectionIDFn?
        let getWindowOwner: SLSGetWindowOwnerFn?
        let getConnectionPSN: SLSGetConnectionPSNFn?
        let getProcessForPID: GetProcessForPIDFn?
    }

    private struct AuthenticationSPI {
        let setMessage: SLEventSetAuthenticationMessageFn
        let objcGetClass: ObjcGetClassFn
        let selRegisterName: SelRegisterNameFn
        let classResponds: ClassRespondsToSelectorFn
        let factory: AuthenticationFactoryFn
    }

    private static let frameworkPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    private static let requiredSPI: RequiredSPI? = {
        guard ensureSkyLightLoaded() else { return nil }
        let mainConnection: CGSMainConnectionIDFn? = symbol("CGSMainConnectionID")
        let getWindowOwner: SLSGetWindowOwnerFn? = symbol("SLSGetWindowOwner")
        let getConnectionPSN: SLSGetConnectionPSNFn? = symbol("SLSGetConnectionPSN")
        let getProcessForPID: GetProcessForPIDFn? = symbol("GetProcessForPID")
        let psnResolvable = (mainConnection != nil && getWindowOwner != nil && getConnectionPSN != nil) || getProcessForPID != nil
        guard psnResolvable,
              let postToPid: SLEventPostToPidFn = symbol("SLEventPostToPid"),
              let setInteger: SLEventSetIntegerValueFieldFn = symbol("SLEventSetIntegerValueField"),
              let postRecord: SLPSPostEventRecordToFn = symbol("SLPSPostEventRecordTo"),
              let getFront: SLPSGetFrontProcessFn = symbol("_SLPSGetFrontProcess"),
              let setWindowLocation: CGEventSetWindowLocationFn = symbol("CGEventSetWindowLocation") else {
            return nil
        }
        return RequiredSPI(
            postToPid: postToPid,
            setInteger: setInteger,
            postRecord: postRecord,
            getFront: getFront,
            setWindowLocation: setWindowLocation,
            mainConnection: mainConnection,
            getWindowOwner: getWindowOwner,
            getConnectionPSN: getConnectionPSN,
            getProcessForPID: getProcessForPID
        )
    }()

    private static let authenticationSPI: AuthenticationSPI? = {
        guard ensureSkyLightLoaded(),
              let setMessage: SLEventSetAuthenticationMessageFn = symbol("SLEventSetAuthenticationMessage"),
              let objcGetClass: ObjcGetClassFn = symbol("objc_getClass"),
              let selRegisterName: SelRegisterNameFn = symbol("sel_registerName"),
              let classResponds: ClassRespondsToSelectorFn = symbol("class_respondsToSelector"),
              let factory: AuthenticationFactoryFn = symbol("objc_msgSend") else {
            return nil
        }
        return AuthenticationSPI(
            setMessage: setMessage,
            objcGetClass: objcGetClass,
            selRegisterName: selRegisterName,
            classResponds: classResponds,
            factory: factory
        )
    }()

    private static let skyLightLoaded: Bool = {
        dlopen(frameworkPath, RTLD_NOW | RTLD_GLOBAL) != nil
    }()

    private static func ensureSkyLightLoaded() -> Bool { skyLightLoaded }

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle = UnsafeMutableRawPointer(bitPattern: -2),
              let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }

    private static func required() throws -> RequiredSPI {
        guard let requiredSPI else {
            throw ComputerError("background_unavailable: required SkyLight background input symbols are unavailable")
        }
        return requiredSPI
    }

    private static func eventPtr(_ event: CGEvent) -> UnsafeMutableRawPointer {
        Unmanaged.passUnretained(event).toOpaque()
    }

    static func stamp(
        event: CGEvent,
        pid: pid_t,
        wid: CGWindowID,
        windowLocal: CGPoint,
        phase: Int64,
        clickState: Int64,
        button: Int64,
        clickGroup: Int64
    ) throws {
        let spi = try required()
        let ptr = eventPtr(event)
        spi.setInteger(ptr, 0, phase)
        spi.setInteger(ptr, 1, clickState)
        spi.setInteger(ptr, 3, button)
        spi.setInteger(ptr, 7, 3)
        spi.setInteger(ptr, 40, Int64(pid))
        spi.setInteger(ptr, 51, Int64(wid))
        spi.setInteger(ptr, 58, clickGroup)
        spi.setInteger(ptr, 91, Int64(wid))
        spi.setInteger(ptr, 92, Int64(wid))
        spi.setWindowLocation(ptr, windowLocal)
    }

    static func postDual(pid: pid_t, event: CGEvent) throws {
        let spi = try required()
        let ptr = eventPtr(event)
        spi.postToPid(pid, ptr)
        event.postToPid(pid)
    }

    static func postKeyboard(pid: pid_t, event: CGEvent) throws {
        let spi = try required()
        attachKeyboardAuthentication(pid: pid, event: event)
        spi.postToPid(pid, eventPtr(event))
    }

    static func activateWithoutRaise(pid: pid_t, wid: CGWindowID) throws {
        let spi = try required()
        var previous = ProcessSerialNumber()
        let frontResolved = withUnsafeMutableBytes(of: &previous) { previousBytes in
            guard let previousBase = previousBytes.baseAddress else { return false }
            return spi.getFront(previousBase) == 0
        }
        guard frontResolved else {
            throw ComputerError("background_unavailable: window \(wid) could not resolve the front process for background input")
        }
        guard var target = processPSN(spi: spi, pid: pid, wid: wid) else {
            throw ComputerError("background_unavailable: window \(wid) could not resolve its process serial number for background input")
        }
        var record = [UInt8](repeating: 0, count: eventRecordLength)
        record[0x04] = eventRecordLengthByte
        record[0x08] = eventRecordKind
        withUnsafeBytes(of: wid.littleEndian) { bytes in
            record.replaceSubrange(windowIDOffset..<(windowIDOffset + 4), with: bytes)
        }
        record[focusMarkerOffset] = 0x02
        let defocused = withUnsafeMutableBytes(of: &previous) { previousBytes in
            record.withUnsafeBufferPointer { recordBytes in
                guard let previousBase = previousBytes.baseAddress, let recordBase = recordBytes.baseAddress else { return false }
                return spi.postRecord(previousBase, recordBase) == 0
            }
        }
        record[focusMarkerOffset] = 0x01
        let focused = withUnsafeMutableBytes(of: &target) { targetBytes in
            record.withUnsafeBufferPointer { recordBytes in
                guard let targetBase = targetBytes.baseAddress, let recordBase = recordBytes.baseAddress else { return false }
                return spi.postRecord(targetBase, recordBase) == 0
            }
        }
        guard defocused, focused else {
            throw ComputerError("background_unavailable: window \(wid) rejected the SkyLight focus-without-raise record")
        }
        Thread.sleep(forTimeInterval: 0.05)
    }

    private static func processPSN(spi: RequiredSPI, pid: pid_t, wid: CGWindowID) -> ProcessSerialNumber? {
        if let mainConnection = spi.mainConnection,
           let getWindowOwner = spi.getWindowOwner,
           let getConnectionPSN = spi.getConnectionPSN {
            let connection = mainConnection()
            var ownerConnection: UInt32 = 0
            if getWindowOwner(connection, wid, &ownerConnection) == 0, ownerConnection != 0 {
                var psn = ProcessSerialNumber()
                let resolved = withUnsafeMutableBytes(of: &psn) { psnBytes in
                    guard let psnBase = psnBytes.baseAddress else { return false }
                    return getConnectionPSN(ownerConnection, psnBase) == 0
                }
                if resolved {
                    return psn
                }
            }
        }
        guard let getProcessForPID = spi.getProcessForPID else { return nil }
        var psn = ProcessSerialNumber()
        let resolved = withUnsafeMutableBytes(of: &psn) { psnBytes in
            guard let psnBase = psnBytes.baseAddress else { return false }
            return getProcessForPID(pid, psnBase) == 0
        }
        return resolved ? psn : nil
    }

    private static func attachKeyboardAuthentication(pid: pid_t, event: CGEvent) {
        guard let spi = authenticationSPI else { return }
        guard let className = "SLSEventAuthenticationMessage".cString(using: .utf8),
              let selectorName = "messageWithEventRecord:pid:version:".cString(using: .utf8) else { return }
        guard let classPtr = spi.objcGetClass(className),
              let selector = spi.selRegisterName(selectorName) else { return }
        // ponytail: class_respondsToSelector returns false on some macOS 15+ builds even
        // though messageWithEventRecord:pid:version: works; attempt the factory when the
        // SLSEventRecord pointer is found and attach only a non-null message.

        let eventRaw = eventPtr(event)
        var record: UnsafeMutableRawPointer?
        for offset in [24, 32, 16] {
            let bitPattern = eventRaw.advanced(by: offset).load(as: UInt.self)
            guard bitPattern != 0, let candidate = UnsafeMutableRawPointer(bitPattern: bitPattern) else { continue }
            record = candidate
            break
        }
        guard let record else { return }
        guard let message = spi.factory(classPtr, selector, record, pid, 0) else { return }
        spi.setMessage(eventRaw, message)
    }
}
